import XCTest
@testable import CodexMeter

final class UsageSnapshotTests: XCTestCase {
    func testRemainingPercent_whenUsageIsOutsideBounds_shouldClamp() {
        XCTAssertEqual(makeLimit(usedPercent: -5).remainingPercent, 100)
        XCTAssertEqual(makeLimit(usedPercent: 25).remainingPercent, 75)
        XCTAssertEqual(makeLimit(usedPercent: 140).remainingPercent, 0)
    }

    func testMostConstrainedLimit_whenMultipleLimitsExist_shouldUseLowestRemainingValue() {
        let snapshot = UsageSnapshot(
            limits: [makeLimit(id: "five-hour", usedPercent: 30), makeLimit(id: "weekly", usedPercent: 70)],
            creditBalance: nil,
            sourceName: "Test",
            fetchedAt: .now
        )

        XCTAssertEqual(snapshot.mostConstrainedLimit?.id, "weekly")
    }

    private func makeLimit(id: String = "limit", usedPercent: Int) -> UsageLimit {
        UsageLimit(
            id: id,
            name: id,
            windowDurationMinutes: nil,
            usedPercent: usedPercent,
            resetsAt: nil
        )
    }
}
