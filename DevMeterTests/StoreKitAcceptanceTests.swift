import StoreKitTest
import StoreKit
import AppKit
import XCTest
@testable import DevMeter

@MainActor
final class StoreKitAcceptanceTests: XCTestCase {
    func testLocalStoreKit_with58YuanNonConsumable_purchasesRestoresAndRevokesRefund() async throws {
        guard ProcessInfo.processInfo.environment["DEVMETER_STOREKIT_TESTING"] == "1" else {
            throw XCTSkip("原生交易验收使用 DevMeterPayments scheme，不能以普通单元测试替代。")
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "DevMeter · StoreKit 本地模拟测试"
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { window.close() }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "DevMeter", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.storefront = "CHN"
        session.locale = Locale(identifier: "zh_CN")
        session.clearTransactions()
        defer { session.clearTransactions() }
        let backend = StoreKitPurchaseProvider()
        let updates = backend.observeUpdates {}
        defer { updates.cancel() }
        let loaded = try await backend.loadProduct()
        let product = try XCTUnwrap(loaded)
        XCTAssertEqual(product.id, StoreKitPurchaseProvider.productID)
        XCTAssertTrue(product.displayPrice.contains("58"))
        let initiallyOwned = try await backend.hasVerifiedEntitlement()
        XCTAssertFalse(initiallyOwned)
        let result = try await backend.purchase()
        guard case .purchased = result else { return XCTFail("Expected local non-consumable purchase") }
        let ownedAfterPurchase = try await backend.hasVerifiedEntitlement()
        XCTAssertTrue(ownedAfterPurchase)
        let originalPurchase = try XCTUnwrap(session.allTransactions().first(where: {
            $0.productIdentifier == StoreKitPurchaseProvider.productID && $0.state == .purchased
        }))
        let restarted = StoreKitPurchaseProvider()
        let ownedAfterRestart = try await restarted.hasVerifiedEntitlement()
        XCTAssertTrue(ownedAfterRestart)
        try await restarted.restore()
        let ownedAfterRestore = try await restarted.hasVerifiedEntitlement()
        XCTAssertTrue(ownedAfterRestore)
        // 恢复可能新增 restored 记录；退款必须指向实际购买，不能依赖测试交易的返回顺序。
        try session.refundTransaction(identifier: originalPurchase.identifier)
        // StoreKit 在异步通知后撤销本地权益，不使用真实 Apple ID 或真实扣款。
        for _ in 0..<200 {
            if !(try await backend.hasVerifiedEntitlement()) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let ownedAfterRefund = try await backend.hasVerifiedEntitlement()
        var entitlementDiagnostics: [String] = []
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                entitlementDiagnostics.append("id=\(transaction.id), original=\(transaction.originalID), revoked=\(String(describing: transaction.revocationDate))")
            }
        }
        let testDiagnostics = session.allTransactions().map {
            "id=\($0.identifier), original=\($0.originalTransactionIdentifier), state=\($0.state.rawValue), cancelled=\(String(describing: $0.cancelDate))"
        }
        // 保留两侧的模拟元数据帮助诊断；不能通过删断言或清空交易来冒充退款验收通过。
        XCTAssertFalse(ownedAfterRefund, "Local transactions: \(testDiagnostics); current entitlements: \(entitlementDiagnostics)")
    }
}
