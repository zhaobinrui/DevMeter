import Foundation

struct ProProduct: Equatable, Sendable {
    let id: String
    let displayName: String
    let displayPrice: String
}

enum PurchaseOutcome: Sendable { case purchased, pending, cancelled }
enum PurchaseChannel: Sendable {
    case preview, appStore
    static var current: Self {
        #if APP_STORE
        .appStore
        #elseif DEBUG
        ProcessInfo.processInfo.environment["DEVMETER_STOREKIT_TESTING"] == "1" ? .appStore : .preview
        #else
        .preview
        #endif
    }
}

enum PurchaseState: Equatable, Sendable {
    case preview, loading, free, purchasing, pending, restoring, purchased, cancelled, failed
    var summary: String {
        switch self {
        case .preview: "本地预览版，未启用收费"
        case .loading: "正在读取 Apple 购买权益"
        case .free: "Free"
        case .purchasing: "正在购买"
        case .pending: "购买待批准，请稍后查看"
        case .restoring: "正在恢复购买"
        case .purchased: "Pro · 已买断"
        case .cancelled: "购买已取消"
        case .failed: "购买服务暂不可用"
        }
    }
}

@MainActor
protocol PurchaseProviding {
    func loadProduct() async throws -> ProProduct?
    func hasVerifiedEntitlement() async throws -> Bool
    func purchase() async throws -> PurchaseOutcome
    func restore() async throws
    func observeUpdates(_ changed: @escaping @MainActor @Sendable () async -> Void) -> Task<Void, Never>
}
