import Foundation

@MainActor
final class PurchaseController: ObservableObject {
    @Published private(set) var state: PurchaseState
    @Published private(set) var product: ProProduct?
    @Published private(set) var hasProAccess: Bool
    @Published private(set) var lastError: String?
    @Published private(set) var isWorking = false
    let channel: PurchaseChannel
    var accessChanged: (@MainActor (Bool) -> Void)?
    private let provider: any PurchaseProviding
    private var updatesTask: Task<Void, Never>?
    private var refreshGeneration: UInt = 0

    init(provider: any PurchaseProviding, channel: PurchaseChannel = .current) {
        self.provider = provider
        self.channel = channel
        hasProAccess = channel == .preview
        state = channel == .preview ? .preview : .loading
    }

    func start() {
        guard channel == .appStore, updatesTask == nil else { return }
        updatesTask = provider.observeUpdates { [weak self] in _ = await self?.refreshEntitlement() }
        Task { [weak self] in _ = await self?.refreshEntitlement() }
    }

    func stop() { updatesTask?.cancel(); updatesTask = nil }
    deinit { updatesTask?.cancel() }

    func loadProduct() async {
        guard channel == .appStore else { return }
        do {
            product = try await provider.loadProduct()
            if product == nil { lastError = "Apple 尚未返回 Pro 商品，请稍后重试或使用恢复购买。" }
            else { lastError = nil }
        } catch { lastError = "无法读取 Apple 商品信息，请稍后重试。" }
    }

    @discardableResult
    func refreshEntitlement() async -> Bool {
        guard channel == .appStore else { return false }
        refreshGeneration &+= 1
        let operation = refreshGeneration
        do {
            let verified = try await provider.hasVerifiedEntitlement()
            guard operation == refreshGeneration else { return false }
            hasProAccess = verified
            accessChanged?(verified)
            if !isWorking { state = verified ? .purchased : (state == .pending ? .pending : .free) }
            lastError = nil
            return true
        } catch {
            guard operation == refreshGeneration else { return false }
            // 不把 UserDefaults 的布尔值当作购买凭据；临时读取失败只保留本次运行的可信权益。
            lastError = "Apple 权益验证失败，已保留本次运行中上一次可信结果；可稍后恢复购买。"
            if !isWorking { state = .failed }
            return false
        }
    }

    func purchase() async {
        guard channel == .appStore, !isWorking, !hasProAccess, state != .pending else { return }
        isWorking = true
        state = .purchasing
        lastError = nil
        defer { isWorking = false }
        do {
            switch try await provider.purchase() {
            case .purchased:
                guard await refreshEntitlement() else { state = .failed; return }
                state = hasProAccess ? .purchased : .failed
                if !hasProAccess { lastError = "交易完成，但 Apple 尚未确认权益。请稍后恢复购买。" }
            case .pending: state = .pending
            case .cancelled: state = .cancelled
            }
        } catch {
            state = .failed
            lastError = "购买未完成或交易未通过 Apple 验证，请稍后重试。"
        }
    }

    func restore() async {
        guard channel == .appStore, !isWorking else { return }
        isWorking = true
        state = .restoring
        lastError = nil
        defer { isWorking = false }
        do {
            try await provider.restore()
            guard await refreshEntitlement() else { state = .failed; return }
            state = hasProAccess ? .purchased : .free
        } catch {
            state = .failed
            lastError = "恢复购买失败，已有本地数据和本次可信权益保持可用。"
        }
    }
}
