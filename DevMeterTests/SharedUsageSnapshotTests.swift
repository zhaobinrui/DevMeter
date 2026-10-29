import XCTest
@testable import DevMeter

final class SharedUsageSnapshotTests: XCTestCase {
    func testFreshness_whenTimeOrResetExpires_marksOldWithoutChangingQuotaOrTimestamp() {
        let date = Date(timeIntervalSince1970: 1_900_000_000)
        let snapshot = SharedUsageSnapshot(limits: [SharedUsageLimit(id: "one", name: "Window", remainingPercent: 37,
                                                                    resetsAt: date.addingTimeInterval(120))],
                                           creditBalance: nil, fetchedAt: date, displayState: .ready)
        XCTAssertEqual(snapshot.state(at: date), .ready)
        XCTAssertEqual(snapshot.nextExpiry(after: date), date.addingTimeInterval(120))
        XCTAssertEqual(snapshot.state(at: date.addingTimeInterval(120)), .stale)
        XCTAssertEqual(snapshot.limits.first?.remainingPercent, 37)
        XCTAssertEqual(snapshot.fetchedAt, date)
        let noReset = SharedUsageSnapshot(limits: [SharedUsageLimit(id: "one", name: "Window", remainingPercent: 37, resetsAt: nil)],
                                         creditBalance: nil, fetchedAt: date)
        XCTAssertEqual(noReset.state(at: date.addingTimeInterval(301)), .stale)
        XCTAssertEqual(noReset.nextExpiry(after: date), date.addingTimeInterval(301))
    }

    func testDisplayState_distinguishesFirstFailureCachedFailureAuthorizationAndDisabled() {
        let date = Date.now
        let limits = [SharedUsageLimit(id: "one", name: "Window", remainingPercent: 37, resetsAt: nil)]
        for state in [UsageDisplayState.idle, .refreshing, .failed, .awaitingAuthorization, .disabled] {
            let empty = SharedUsageSnapshot(limits: [], creditBalance: nil, fetchedAt: .distantPast,
                                            displayState: state, stateUpdatedAt: date)
            XCTAssertEqual(empty.state(at: date), state)
        }
        let failed = SharedUsageSnapshot(limits: limits, creditBalance: nil, fetchedAt: date, displayState: .failed)
        XCTAssertEqual(failed.state(at: date), .stale)
        for state in [UsageDisplayState.awaitingAuthorization, .disabled] {
            let protected = SharedUsageSnapshot(limits: limits, creditBalance: nil, fetchedAt: date, displayState: state)
            XCTAssertFalse(protected.state(at: date).showsQuota)
        }
        let empty = SharedUsageSnapshot(limits: [], creditBalance: nil, fetchedAt: date, displayState: .ready)
        XCTAssertEqual(empty.state(at: date), .empty)
    }

    func testRefreshingMarker_whenMainAppStops_expiresBeforeQuotaAndDoesNotRemainLoadingForever() {
        let date = Date.now
        let loading = SharedUsageSnapshot(limits: [], creditBalance: nil, fetchedAt: .distantPast,
                                          displayState: .refreshing, stateUpdatedAt: date)
        XCTAssertEqual(loading.state(at: date), .refreshing)
        XCTAssertEqual(loading.nextExpiry(after: date), date.addingTimeInterval(61))
        XCTAssertEqual(loading.state(at: date.addingTimeInterval(61)), .idle)
        let refreshing = SharedUsageSnapshot(limits: [SharedUsageLimit(id: "one", name: "Quota", remainingPercent: 37, resetsAt: nil)],
                                             creditBalance: nil, fetchedAt: date, displayState: .refreshing, stateUpdatedAt: date)
        let firstExpiry = refreshing.nextExpiry(after: date)!
        XCTAssertEqual(refreshing.state(at: firstExpiry), .ready)
        let quotaExpiry = refreshing.nextExpiry(after: firstExpiry)!
        XCTAssertEqual(quotaExpiry, date.addingTimeInterval(301))
        XCTAssertEqual(refreshing.state(at: quotaExpiry), .stale)
    }

    func testAuthorizationMarker_inPrimaryStorage_preventsLegacyQuotaFromReturning() {
        let primaryName = "SharedState.Primary.\(UUID().uuidString)"
        let legacyName = "SharedState.Legacy.\(UUID().uuidString)"
        let primary = UserDefaults(suiteName: primaryName)!
        let legacy = UserDefaults(suiteName: legacyName)!
        defer { primary.removePersistentDomain(forName: primaryName); legacy.removePersistentDomain(forName: legacyName) }
        let old = SharedUsageSnapshot(limits: [SharedUsageLimit(id: "old", name: "Old", remainingPercent: 89, resetsAt: nil)],
                                      creditBalance: nil, fetchedAt: .now)
        let revoked = SharedUsageSnapshot(limits: [], creditBalance: nil, fetchedAt: .distantPast,
                                          sourceName: "Codex", displayState: .awaitingAuthorization)
        XCTAssertTrue(SharedUsageSnapshotStorage.save(old, defaults: legacy))
        XCTAssertTrue(SharedUsageSnapshotStorage.save(revoked, defaults: primary))
        let restored = SharedUsageSnapshotStorage.load(defaults: primary, legacyDefaults: legacy)
        XCTAssertEqual(restored, revoked)
        XCTAssertTrue(restored?.limits.isEmpty == true)
    }

    func testSourceIdentity_survivesNewEncoding_andOldSnapshotsStillDecode() throws {
        let legacy = Data(#"{"limits":[],"fetchedAt":1900000000000}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        XCTAssertNil(try decoder.decode(SharedUsageSnapshot.self, from: legacy).sourceName)
        let snapshot = SharedUsageSnapshot(limits: [], creditBalance: nil, fetchedAt: Date(timeIntervalSince1970: 1_900_000_000),
                                           sourceName: "Claude Code · 本地状态行")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        XCTAssertEqual(try decoder.decode(SharedUsageSnapshot.self, from: encoder.encode(snapshot)), snapshot)
    }

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
