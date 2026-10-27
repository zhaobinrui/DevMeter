import XCTest
@testable import DevMeter

final class UsageAlertTests: XCTestCase {
    func testLowQuota_whenRepeatedAndRestarted_notifiesOnceUntilRecoveryOrReset() throws {
        var policy = UsageAlertPolicy()
        let low = UsageTestFixtures.snapshot(used: 95)
        let first = alerts(&policy, snapshot: low)
        XCTAssertEqual(first.count, 1)
        policy.markDelivered(try XCTUnwrap(first.first))
        policy = try JSONDecoder().decode(UsageAlertPolicy.self, from: JSONEncoder().encode(policy))
        XCTAssertTrue(alerts(&policy, snapshot: low).isEmpty)
        _ = alerts(&policy, snapshot: UsageTestFixtures.snapshot(used: 80))
        XCTAssertEqual(alerts(&policy, snapshot: low).count, 1)
        XCTAssertEqual(alerts(&policy, snapshot: UsageTestFixtures.snapshot(used: 95, reset: 9_000)).count, 1)
    }

    func testLowQuota_withUnknownIdentityExpiredWindowOrDisabledRule_doesNotNotify() {
        var policy = UsageAlertPolicy()
        XCTAssertTrue(alerts(&policy, snapshot: UsageTestFixtures.snapshot(used: 99, account: nil)).isEmpty)
        XCTAssertTrue(alerts(&policy, snapshot: UsageTestFixtures.snapshot(used: 99, reset: -1)).isEmpty)
        XCTAssertTrue(policy.success(snapshot: UsageTestFixtures.snapshot(used: 99), forecasts: [], threshold: 10, lowEnabled: false, predictionEnabled: false).isEmpty)
    }

    func testLowQuota_afterSwitchingAccount_usesSeparateDeduplicationScope() throws {
        var policy = UsageAlertPolicy()
        let first = try XCTUnwrap(alerts(&policy, snapshot: UsageTestFixtures.snapshot(used: 95)).first)
        policy.markDelivered(first)
        let second = alerts(&policy, snapshot: UsageTestFixtures.snapshot(used: 95, account: UsageTestFixtures.accountB))
        XCTAssertEqual(second.count, 1)
        XCTAssertNotEqual(first.id, second.first?.id)
        XCTAssertFalse(first.body.contains(UsageTestFixtures.accountA))
    }

    func testFailure_requiresThreeAttemptsAndTwoMinutes_andRearmsAfterRecovery() throws {
        var policy = UsageAlertPolicy()
        let now = UsageTestFixtures.time
        XCTAssertNil(policy.failure(now: now))
        XCTAssertNil(policy.failure(now: now.addingTimeInterval(60)))
        let event = try XCTUnwrap(policy.failure(now: now.addingTimeInterval(120)))
        policy.markDelivered(event)
        XCTAssertNil(policy.failure(now: now.addingTimeInterval(180)))
        _ = alerts(&policy, snapshot: UsageTestFixtures.snapshot(used: 20))
        XCTAssertNil(policy.failure(now: now.addingTimeInterval(240)))
        XCTAssertNil(policy.failure(now: now.addingTimeInterval(300)))
        XCTAssertNotNil(policy.failure(now: now.addingTimeInterval(360)))
    }

    func testFailure_afterSleep_doesNotCountSeparatedFailuresAsContinuous() {
        var policy = UsageAlertPolicy()
        XCTAssertNil(policy.failure(now: UsageTestFixtures.time))
        XCTAssertNil(policy.failure(now: UsageTestFixtures.time.addingTimeInterval(60)))
        XCTAssertNil(policy.failure(now: UsageTestFixtures.time.addingTimeInterval(3_600)))
    }

    func testForecastAlert_whenLowQuotaAlreadyApplies_avoidsTwoAlertsForOneWindow() throws {
        var policy = UsageAlertPolicy()
        let snapshot = UsageTestFixtures.snapshot(used: 95)
        let events = policy.success(snapshot: snapshot, forecasts: [UsageForecast(id: "codex.primary", status: .atRisk)], threshold: 10, lowEnabled: true, predictionEnabled: true)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .lowQuota)
        policy.markDelivered(try XCTUnwrap(events.first))
        XCTAssertTrue(policy.success(snapshot: snapshot, forecasts: [UsageForecast(id: "codex.primary", status: .atRisk)], threshold: 10, lowEnabled: true, predictionEnabled: true).isEmpty)
    }

    private func alerts(_ policy: inout UsageAlertPolicy, snapshot: UsageSnapshot) -> [UsageAlert] {
        policy.success(snapshot: snapshot, forecasts: [], threshold: 10, lowEnabled: true, predictionEnabled: false)
    }
}
