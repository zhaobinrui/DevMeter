import XCTest
@testable import DevMeter

final class UsageHistoryTests: XCTestCase {
    func testRecord_whenRestarted_restoresOnlyQuotaMetadata() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = LocalUsageHistoryRepository(fileURL: url)
        _ = try await repository.record(UsageTestFixtures.sample(used: 20), retentionDays: 30, now: UsageTestFixtures.time)
        let restored = try await LocalUsageHistoryRepository(fileURL: url).load(retentionDays: 30, now: UsageTestFixtures.time)
        XCTAssertEqual(restored, [UsageTestFixtures.sample(used: 20)])
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(contents.contains("SECRET"))
        XCTAssertFalse(contents.contains("creditBalance"))
        XCTAssertFalse(contents.contains("sourceName"))
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testRecord_withinFiveMinutes_coalescesPerAccountWithoutMixingAccounts() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = LocalUsageHistoryRepository(fileURL: url)
        _ = try await repository.record(UsageTestFixtures.sample(used: 20), retentionDays: 30, now: UsageTestFixtures.time)
        _ = try await repository.record(UsageTestFixtures.sample(used: 25, offset: 60), retentionDays: 30, now: UsageTestFixtures.time.addingTimeInterval(60))
        let samples = try await repository.record(UsageTestFixtures.sample(used: 90, offset: 60, account: UsageTestFixtures.accountB), retentionDays: 30, now: UsageTestFixtures.time.addingTimeInterval(60))
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples.first(where: { $0.accountKey == UsageTestFixtures.accountA })?.limits.first?.usedPercent, 25)
        XCTAssertEqual(samples.first(where: { $0.accountKey == UsageTestFixtures.accountB })?.limits.first?.usedPercent, 90)
    }

    func testLoad_withExpiredRecords_prunesAndPersistsRetention() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = LocalUsageHistoryRepository(fileURL: url)
        _ = try await repository.record(UsageTestFixtures.sample(used: 10), retentionDays: 30, now: UsageTestFixtures.time)
        let now = UsageTestFixtures.time.addingTimeInterval(8 * 86_400)
        let samples = try await repository.load(retentionDays: 7, now: now)
        XCTAssertTrue(samples.isEmpty)
        let restarted = try await LocalUsageHistoryRepository(fileURL: url).load(retentionDays: 30, now: now)
        XCTAssertTrue(restarted.isEmpty)
    }

    func testRecord_withCorruptOrUnknownVersion_preservesOriginalUntilExplicitClear() async throws {
        for invalid in ["not-json", "{\"version\":99,\"samples\":[]}"] {
            let url = temporaryFile()
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(invalid.utf8).write(to: url)
            let repository = LocalUsageHistoryRepository(fileURL: url)
            do {
                _ = try await repository.record(UsageTestFixtures.sample(used: 20), retentionDays: 30, now: UsageTestFixtures.time)
                XCTFail("Corrupt history must not be overwritten")
            } catch { XCTAssertTrue(error is UsageHistoryError) }
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), invalid)
            try await repository.clear()
            let reset = try await repository.load(retentionDays: 30, now: UsageTestFixtures.time)
            XCTAssertTrue(reset.isEmpty)
        }
    }

    func testRecord_whenDirectoryIsAFile_reportsFailureAndDoesNotReplaceIt() async throws {
        let url = temporaryFile()
        let directory = url.deletingLastPathComponent()
        try Data("protected".utf8).write(to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try await LocalUsageHistoryRepository(fileURL: url).record(UsageTestFixtures.sample(used: 20), retentionDays: 30, now: UsageTestFixtures.time)
            XCTFail("Expected storage failure")
        } catch {}
        XCTAssertEqual(try String(contentsOf: directory, encoding: .utf8), "protected")
    }

    func testClear_whenHistoryExists_removesDiskAndMemory() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = LocalUsageHistoryRepository(fileURL: url)
        _ = try await repository.record(UsageTestFixtures.sample(used: 20), retentionDays: 30, now: UsageTestFixtures.time)
        try await repository.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let loaded = try await repository.load(retentionDays: 30, now: UsageTestFixtures.time)
        XCTAssertTrue(loaded.isEmpty)
    }

    func testForecast_withContinuousConsumption_distinguishesRiskFromSufficientAllowance() {
        let samples = [UsageTestFixtures.sample(used: 10), UsageTestFixtures.sample(used: 20, offset: 300)]
        let latest = UsageTestFixtures.snapshot(used: 30, offset: 600)
        let risk = UsageForecastEngine.forecasts(snapshot: latest, samples: samples, now: latest.fetchedAt).first
        XCTAssertEqual(risk?.status, .atRisk)
        XCTAssertEqual(risk?.percentagePointsPerHour, 120)
        let closeReset = UsageTestFixtures.snapshot(used: 30, offset: 600, reset: 1_200)
        let closeSamples = [UsageTestFixtures.sample(used: 10, reset: 1_200), UsageTestFixtures.sample(used: 20, offset: 300, reset: 1_200)]
        XCTAssertEqual(UsageForecastEngine.forecasts(snapshot: closeReset, samples: closeSamples, now: closeReset.fetchedAt).first?.status, .sufficientUntilReset)
    }

    func testForecast_acrossAccountResetRollbackAndGap_requiresNewSamples() {
        let initial = [UsageTestFixtures.sample(used: 40), UsageTestFixtures.sample(used: 50, offset: 300)]
        let cases = [
            UsageTestFixtures.snapshot(used: 60, offset: 600, account: UsageTestFixtures.accountB),
            UsageTestFixtures.snapshot(used: 60, offset: 600, reset: 9_000),
            UsageTestFixtures.snapshot(used: 10, offset: 600),
            UsageTestFixtures.snapshot(used: 60, offset: 1_800)
        ]
        for snapshot in cases {
            XCTAssertEqual(UsageForecastEngine.forecasts(snapshot: snapshot, samples: initial, now: snapshot.fetchedAt).first?.status, .insufficientData)
        }
    }

    func testForecast_withFlatConsumptionUnknownResetAndStaleData_doesNotInventPrediction() {
        let samples = [UsageTestFixtures.sample(used: 10), UsageTestFixtures.sample(used: 10, offset: 300)]
        let current = UsageTestFixtures.snapshot(used: 10, offset: 600)
        XCTAssertEqual(UsageForecastEngine.forecasts(snapshot: current, samples: samples, now: current.fetchedAt).first?.status, .noRecentConsumption)
        XCTAssertEqual(UsageForecastEngine.forecasts(snapshot: current, samples: samples, now: current.fetchedAt.addingTimeInterval(301)).first?.status, .stale)
        let unknown = UsageTestFixtures.snapshot(used: 10, offset: 600, reset: nil)
        XCTAssertEqual(UsageForecastEngine.forecasts(snapshot: unknown, samples: samples, now: unknown.fetchedAt).first?.status, .resetUnknown)
        let past = UsageTestFixtures.snapshot(used: 10, offset: 600, reset: 500)
        XCTAssertEqual(UsageForecastEngine.forecasts(snapshot: past, samples: samples, now: past.fetchedAt).first?.status, .awaitingReset)
    }

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DevMeterHistoryTests-\(UUID().uuidString)", isDirectory: true).appendingPathComponent("history.json")
    }
}

enum UsageTestFixtures {
    static let accountA = String(repeating: "a", count: 64)
    static let accountB = String(repeating: "b", count: 64)
    static let time = Date(timeIntervalSince1970: 1_800_000_000)

    static func snapshot(used: Int, offset: TimeInterval = 0, account: String? = accountA,
                         reset: TimeInterval? = 7_200) -> UsageSnapshot {
        UsageSnapshot(limits: [UsageLimit(id: "codex.primary", name: "5 小时额度", windowDurationMinutes: 300,
                                         usedPercent: used, resetsAt: reset.map { time.addingTimeInterval($0) })],
                      creditBalance: "SECRET_CREDIT", sourceName: "SECRET_SOURCE", fetchedAt: time.addingTimeInterval(offset), accountKey: account)
    }

    static func sample(used: Int, offset: TimeInterval = 0, account: String = accountA,
                       reset: TimeInterval? = 7_200) -> UsageHistorySample {
        UsageHistorySample(snapshot: snapshot(used: used, offset: offset, account: account, reset: reset), accountKey: account)
    }
}
