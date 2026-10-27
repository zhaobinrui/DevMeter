import Foundation
import StoreKit

@MainActor
final class StoreKitPurchaseProvider: PurchaseProviding {
    static let productID = "com.zhaobinrui.devspace.meter.pro.lifetime"
    private var product: Product?

    func loadProduct() async throws -> ProProduct? {
        let products = try await Product.products(for: [Self.productID])
        guard let product = products.first(where: { $0.id == Self.productID }),
              product.type == .nonConsumable else { return nil }
        self.product = product
        return ProProduct(id: product.id, displayName: product.displayName, displayPrice: product.displayPrice)
    }

    func hasVerifiedEntitlement() async throws -> Bool {
        var purchased = false
        for await result in StoreKit.Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if transaction.productID == Self.productID {
                    purchased = purchased || accepts(transaction)
                }
            case .unverified(let transaction, _):
                if transaction.productID == Self.productID { throw PurchaseVerificationError.unverified }
            }
        }
        return purchased
    }

    func purchase() async throws -> PurchaseOutcome {
        if product == nil { _ = try await loadProduct() }
        guard let product, product.type == .nonConsumable else { throw PurchaseVerificationError.productUnavailable }
        switch try await product.purchase() {
        case .success(let result):
            guard case .verified(let transaction) = result, accepts(transaction) else {
                throw PurchaseVerificationError.unverified
            }
            await transaction.finish()
            return .purchased
        case .pending: return .pending
        case .userCancelled: return .cancelled
        @unknown default: throw PurchaseVerificationError.unverified
        }
    }

    func restore() async throws {
        // sync 可能弹出 Apple 登录提示，只能由用户点击“恢复购买”触发。
        try await AppStore.sync()
    }

    func observeUpdates(_ changed: @escaping @MainActor @Sendable () async -> Void) -> Task<Void, Never> {
        Task {
            for await result in StoreKit.Transaction.updates {
                guard !Task.isCancelled else { return }
                switch result {
                case .verified(let transaction) where transaction.productID == Self.productID:
                    await transaction.finish()
                    await changed()
                case .unverified(let transaction, _) where transaction.productID == Self.productID:
                    await changed()
                default: break
                }
            }
        }
    }

    private func accepts(_ transaction: StoreKit.Transaction) -> Bool {
        guard transaction.productID == Self.productID, transaction.productType == .nonConsumable,
              transaction.revocationDate == nil else { return false }
        #if !DEBUG
        // Xcode 本地交易不能在正式构建中解锁；Sandbox 交易留给 TestFlight/商店沙盒验证。
        if transaction.environment == .xcode { return false }
        #endif
        return true
    }
}

enum PurchaseVerificationError: Error { case unverified, productUnavailable }
