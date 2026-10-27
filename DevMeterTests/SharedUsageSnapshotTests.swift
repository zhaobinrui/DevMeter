import XCTest
@testable import DevMeter

final class SharedUsageSnapshotTests: XCTestCase {
    func testSaveAndLoad_roundTripsSnapshot() {
        let suiteName = "SharedUsageSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let snapshot = SharedUsageSnapshot(
            limits: [
                SharedUsageLimit(
                    id: "codex.primary",
                    name: "5 小时额度",
                    remainingPercent: 62,
                    resetsAt: Date(timeIntervalSince1970: 2_000_000_000)
                )
            ],
            creditBalance: "12.5",
            fetchedAt: Date(timeIntervalSince1970: 1_900_000_000)
        )

        XCTAssertTrue(SharedUsageSnapshotStorage.save(snapshot, defaults: defaults))
        XCTAssertEqual(SharedUsageSnapshotStorage.load(defaults: defaults), snapshot)
    }

    func testMostConstrainedLimit_returnsLowestRemainingPercentage() {
        let snapshot = SharedUsageSnapshot(
            limits: [
                SharedUsageLimit(id: "one", name: "One", remainingPercent: 80, resetsAt: nil),
                SharedUsageLimit(id: "two", name: "Two", remainingPercent: 15, resetsAt: nil)
            ],
            creditBalance: nil,
            fetchedAt: .now
        )

        XCTAssertEqual(snapshot.mostConstrainedLimit?.id, "two")
    }

    func testLoad_whenPrimaryIsEmpty_migratesLegacySnapshot() {
        let primarySuite = "SharedUsageSnapshotTests.Primary.\(UUID().uuidString)"
        let legacySuite = "SharedUsageSnapshotTests.Legacy.\(UUID().uuidString)"
        let primaryDefaults = UserDefaults(suiteName: primarySuite)!
        let legacyDefaults = UserDefaults(suiteName: legacySuite)!
        defer {
            primaryDefaults.removePersistentDomain(forName: primarySuite)
            legacyDefaults.removePersistentDomain(forName: legacySuite)
        }
        let snapshot = SharedUsageSnapshot(
            limits: [
                SharedUsageLimit(
                    id: "codex.primary",
                    name: "5 小时额度",
                    remainingPercent: 38,
                    resetsAt: nil
                )
            ],
            creditBalance: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_900_000_000)
        )
        XCTAssertTrue(
            SharedUsageSnapshotStorage.save(
                snapshot,
                defaults: legacyDefaults
            )
        )

        let loaded = SharedUsageSnapshotStorage.load(
            defaults: primaryDefaults,
            legacyDefaults: legacyDefaults
        )

        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(
            SharedUsageSnapshotStorage.load(defaults: primaryDefaults),
            snapshot
        )
    }
}
