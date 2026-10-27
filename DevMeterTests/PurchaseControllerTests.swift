import XCTest
@testable import DevMeter

@MainActor
final class PurchaseControllerTests: XCTestCase {
    func testPurchase_whenVerified_unlocksAndRestoresWithoutPreferenceFlags() async {
        let backend = PurchaseFixture()
        let controller = PurchaseController(provider: backend, channel: .appStore)
        await controller.refreshEntitlement()
        XCTAssertFalse(controller.hasProAccess)
        await controller.loadProduct()
        XCTAssertEqual(controller.product?.displayPrice, "¥58.00")
        await controller.purchase()
        XCTAssertTrue(controller.hasProAccess)
        XCTAssertEqual(controller.state, .purchased)
        let restarted = PurchaseController(provider: backend, channel: .appStore)
        XCTAssertFalse(restarted.hasProAccess)
        await restarted.refreshEntitlement()
        XCTAssertTrue(restarted.hasProAccess)
        XCTAssertEqual(backend.restoreCalls, 0)
        await restarted.restore()
        XCTAssertEqual(backend.restoreCalls, 1)
    }

    func testPurchase_whenPendingOrCancelled_doesNotUnlock() async {
        for outcome in [PurchaseOutcome.pending, .cancelled] {
            let backend = PurchaseFixture()
            backend.outcome = outcome
            let controller = PurchaseController(provider: backend, channel: .appStore)
            await controller.purchase()
            XCTAssertFalse(controller.hasProAccess)
            XCTAssertTrue([PurchaseState.pending, .cancelled].contains(controller.state))
        }
    }

    func testEntitlement_afterRefund_revokesProWithoutDeletingHistory() async {
        let backend = PurchaseFixture()
        backend.entitled = true
        let controller = PurchaseController(provider: backend, channel: .appStore)
        var changes: [Bool] = []
        controller.accessChanged = { changes.append($0) }
        await controller.refreshEntitlement()
        backend.entitled = false
        await controller.refreshEntitlement()
        XCTAssertEqual(changes, [true, false])
        XCTAssertFalse(controller.hasProAccess)
        XCTAssertEqual(controller.state, .free)
    }

    func testEntitlement_whenUnverified_neverGrantsAccess_andPreservesOnlyPreviouslyTrustedAccess() async {
        let backend = PurchaseFixture()
        backend.failsVerification = true
        let controller = PurchaseController(provider: backend, channel: .appStore)
        await controller.refreshEntitlement()
        XCTAssertFalse(controller.hasProAccess)
        XCTAssertNotNil(controller.lastError)
        backend.failsVerification = false
        backend.entitled = true
        await controller.refreshEntitlement()
        backend.failsVerification = true
        await controller.refreshEntitlement()
        XCTAssertTrue(controller.hasProAccess)
        XCTAssertEqual(controller.state, .failed)
    }

    func testPreview_neverCallsApplePurchaseOrRestore() async {
        let backend = PurchaseFixture()
        let controller = PurchaseController(provider: backend, channel: .preview)
        await controller.purchase()
        await controller.restore()
        XCTAssertTrue(controller.hasProAccess)
        XCTAssertEqual(controller.state, .preview)
        XCTAssertEqual(backend.purchaseCalls, 0)
        XCTAssertEqual(backend.restoreCalls, 0)
    }

    func testRestore_whenVerificationFails_keepsFailureVisibleAndDoesNotUnlock() async {
        let backend = PurchaseFixture()
        backend.failsVerification = true
        let controller = PurchaseController(provider: backend, channel: .appStore)
        await controller.restore()
        XCTAssertFalse(controller.hasProAccess)
        XCTAssertEqual(controller.state, .failed)
        XCTAssertNotNil(controller.lastError)
    }

    func testPurchase_whilePending_doesNotIssueAnotherPurchase() async {
        let backend = PurchaseFixture()
        backend.outcome = .pending
        let controller = PurchaseController(provider: backend, channel: .appStore)
        await controller.purchase()
        await controller.purchase()
        XCTAssertEqual(backend.purchaseCalls, 1)
    }
}

@MainActor
private final class PurchaseFixture: PurchaseProviding {
    var entitled = false
    var failsVerification = false
    var outcome = PurchaseOutcome.purchased
    var purchaseCalls = 0
    var restoreCalls = 0
    func loadProduct() -> ProProduct? { ProProduct(id: StoreKitPurchaseProvider.productID, displayName: "Pro", displayPrice: "¥58.00") }
    func hasVerifiedEntitlement() throws -> Bool {
        if failsVerification { throw PurchaseVerificationError.unverified }
        return entitled
    }
    func purchase() -> PurchaseOutcome {
        purchaseCalls += 1
        if case .purchased = outcome { entitled = true }
        return outcome
    }
    func restore() { restoreCalls += 1 }
    func observeUpdates(_ changed: @escaping @MainActor @Sendable () async -> Void) -> Task<Void, Never> { Task {} }
}
