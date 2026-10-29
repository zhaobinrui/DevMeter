import XCTest
@testable import DevMeter

@MainActor
final class UsageStorePhase1Tests: XCTestCase {
    func testLoadHistory_afterRestart_withoutAuthorizationOrPro_restoresLocalRecordsWithoutFetching() async {
        let preferences = defaults()
        for source in UsageSource.allCases { ProviderAuthorization.setGranted(false, for: source, defaults: preferences) }
        preferences.set(false, forKey: "meter.isEnabled")
        let sample = UsageTestFixtures.sample(used: 20)
        let repository = MemoryUsageHistory(samples: [sample])
        let provider = SequenceUsageProvider([])
        var published = 0
        let store = UsageStore(provider: provider, defaults: preferences, historyRepository: repository,
                               hasProAccess: false, now: { sample.fetchedAt }, didUpdateSnapshot: { _ in published += 1 })

        await store.loadHistory()

        XCTAssertFalse(store.isProviderAuthorized)
        XCTAssertFalse(store.isEnabled)
        XCTAssertFalse(store.hasProAccess)
        XCTAssertNil(store.snapshot)
        XCTAssertNil(store.lastError)
        XCTAssertNil(store.historyError)
        XCTAssertEqual(store.historyDisplay()?.samples, [sample])
        XCTAssertEqual(store.historyDisplay()?.isCurrentSnapshot, false)
        XCTAssertTrue(store.forecasts.isEmpty)
        XCTAssertEqual(published, 0)
        let requests = await provider.requests
        let records = await repository.recordCount
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(records, 0)
    }

    func testLoadHistory_whenProviderFailsAtStartup_showsSavedHistoryWithoutInventingLiveQuota() async {
        let sample = UsageTestFixtures.sample(used: 20)
        let store = UsageStore(provider: SequenceUsageProvider([.failure(.timedOut)]), defaults: defaults(),
                               historyRepository: MemoryUsageHistory(samples: [sample]), now: { sample.fetchedAt })
        await store.refresh()
        await store.loadHistory()
        XCTAssertNotNil(store.lastError)
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(store.historyDisplay()?.limits.first?.remainingPercent, 80)
        XCTAssertEqual(store.historyDisplay()?.isCurrentSnapshot, false)
        XCTAssertTrue(store.forecasts.isEmpty)
    }

    func testHistory_afterProviderRevocation_remainsViewableWithoutRestoringCurrentData() async {
        let sample = UsageTestFixtures.snapshot(used: 30, offset: 600)
        let store = UsageStore(provider: SequenceUsageProvider([.success(sample)]), defaults: defaults(),
                               historyRepository: MemoryUsageHistory(), now: { sample.fetchedAt })
        await store.refresh()
        store.revokeProviderAccess(.codex)
        await store.loadHistory()
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.isProviderAuthorized)
        XCTAssertEqual(store.historyDisplay()?.accountKey, sample.accountKey)
        XCTAssertEqual(store.historyDisplay()?.isCurrentSnapshot, false)
        XCTAssertEqual(store.historyDisplay()?.samples.count, 1)
        XCTAssertTrue(store.currentAccountHistory.isEmpty)
        XCTAssertTrue(store.forecasts.isEmpty)
    }

    func testHistorySelection_keepsSavedAccountsSeparateFromCurrentAccountAndForecast() async {
        let current = UsageTestFixtures.snapshot(used: 30, offset: 600)
        let other = UsageTestFixtures.sample(used: 90, offset: 300, account: UsageTestFixtures.accountB)
        let repository = MemoryUsageHistory(samples: [UsageTestFixtures.sample(used: 10),
                                                     UsageTestFixtures.sample(used: 20, offset: 300), other])
        let store = UsageStore(provider: SequenceUsageProvider([.success(current)]), defaults: defaults(),
                               historyRepository: repository, now: { current.fetchedAt })
        await store.refresh()
        XCTAssertEqual(store.savedHistoryGroups.count, 2)
        XCTAssertEqual(store.historyDisplay()?.isCurrentSnapshot, true)
        XCTAssertEqual(store.historyDisplay()?.samples.count, 3)
        let archived = store.historyDisplay(accountKey: UsageTestFixtures.accountB)
        XCTAssertEqual(archived?.samples, [other])
        XCTAssertEqual(archived?.limits.first?.remainingPercent, 10)
        XCTAssertEqual(archived?.isCurrentSnapshot, false)
        XCTAssertEqual(store.snapshot, current)
        XCTAssertEqual(store.forecasts.first?.status, .atRisk)
    }

    func testHistorySelection_whenCurrentIdentityUnknown_doesNotAttachSavedHistoryToIt() async {
        let current = UsageTestFixtures.snapshot(used: 30, account: nil)
        let archived = UsageTestFixtures.sample(used: 90)
        let store = UsageStore(provider: SequenceUsageProvider([.success(current)]), defaults: defaults(),
                               historyRepository: MemoryUsageHistory(samples: [archived]), now: { current.fetchedAt })
        await store.refresh()
        XCTAssertNil(store.historyDisplay()?.accountKey)
        XCTAssertEqual(store.historyDisplay()?.isCurrentSnapshot, true)
        XCTAssertTrue(store.historyDisplay()?.samples.isEmpty == true)
        XCTAssertEqual(store.historyDisplay(accountKey: archived.accountKey)?.samples, [archived])
        XCTAssertEqual(store.historyDisplay(accountKey: archived.accountKey)?.isCurrentSnapshot, false)
    }

    func testLoadHistory_withClaudeSelected_exposesCodexArchiveWithoutClaimingClaudeHistory() async {
        let preferences = defaults()
        preferences.set(UsageSource.claudeCode.rawValue, forKey: "meter.selectedProvider")
        let provider = SequenceUsageProvider([])
        let sample = UsageTestFixtures.sample(used: 20)
        let store = UsageStore(provider: provider, additionalProviders: [.claudeCode: provider], defaults: preferences,
                               historyRepository: MemoryUsageHistory(samples: [sample]), now: { sample.fetchedAt })
        await store.loadHistory()
        XCTAssertEqual(store.selectedProviderID, .claudeCode)
        XCTAssertTrue(store.currentAccountHistory.isEmpty)
        XCTAssertEqual(store.historyDisplay()?.samples, [sample])
        XCTAssertEqual(store.historyDisplay()?.isCurrentSnapshot, false)
        XCTAssertTrue(store.forecasts.isEmpty)
    }

    func testLoadHistory_whenClearedDuringRead_doesNotRestoreDeletedRecords() async {
        let repository = DelayedHistoryRead(samples: [UsageTestFixtures.sample(used: 20)])
        let store = UsageStore(provider: SequenceUsageProvider([]), defaults: defaults(), historyRepository: repository)
        let pending = Task { await store.loadHistory() }
        await repository.waitUntilReading()
        await store.clearHistory()
        await repository.finishRead()
        await pending.value
        XCTAssertTrue(store.historySamples.isEmpty)
        XCTAssertNil(store.historyDisplay())
        XCTAssertNil(store.historyError)
        XCTAssertFalse(store.isLoadingHistory)
    }

    func testLoadHistory_whenCancelled_discardsLateRecordsWithoutReportingFailure() async {
        let repository = DelayedHistoryRead(samples: [UsageTestFixtures.sample(used: 20)])
        let store = UsageStore(provider: SequenceUsageProvider([]), defaults: defaults(), historyRepository: repository)
        let pending = Task { await store.loadHistory() }
        await repository.waitUntilReading()
        pending.cancel()
        await repository.finishRead()
        await pending.value
        XCTAssertTrue(store.historySamples.isEmpty)
        XCTAssertNil(store.historyError)
        XCTAssertFalse(store.isLoadingHistory)
    }

    func testLoadHistory_whenReadFails_keepsLastRecordsAndAllowsRetry() async {
        let repository = MemoryUsageHistory(samples: [UsageTestFixtures.sample(used: 20)])
        let store = UsageStore(provider: SequenceUsageProvider([]), defaults: defaults(), historyRepository: repository)
        await store.loadHistory()
        await repository.setReadFailure(true)
        await store.loadHistory()
        XCTAssertEqual(store.historySamples.count, 1)
        XCTAssertNotNil(store.historyError)
        XCTAssertNil(store.lastError)
        await repository.setReadFailure(false)
        await store.loadHistory()
        XCTAssertEqual(store.historySamples.count, 1)
        XCTAssertNil(store.historyError)
    }

    func testRefresh_whenHistoryRestored_exposesForecastAndCurrentAccountOnly() async {
        let repository = MemoryUsageHistory(samples: [UsageTestFixtures.sample(used: 10), UsageTestFixtures.sample(used: 20, offset: 300), UsageTestFixtures.sample(used: 99, offset: 300, account: UsageTestFixtures.accountB)])
        let latest = UsageTestFixtures.snapshot(used: 30, offset: 600)
        let store = UsageStore(provider: SequenceUsageProvider([.success(latest)]), defaults: defaults(), historyRepository: repository, now: { latest.fetchedAt })
        await store.refresh()
        XCTAssertEqual(store.currentAccountHistory.count, 3)
        XCTAssertEqual(store.forecasts.first?.status, .atRisk)
        XCTAssertEqual(store.snapshot, latest)
    }

    func testRefresh_whenHistoryDisabledOrIdentityUnknown_doesNotRecord() async {
        for disabled in [true, false] {
            let preferences = defaults()
            preferences.set(!disabled, forKey: "history.isEnabled")
            let repository = MemoryUsageHistory()
            let sample = UsageTestFixtures.snapshot(used: 20, account: disabled ? UsageTestFixtures.accountA : nil)
            let store = UsageStore(provider: SequenceUsageProvider([.success(sample)]), defaults: preferences, historyRepository: repository, now: { sample.fetchedAt })
            await store.refresh()
            let count = await repository.recordCount
            XCTAssertEqual(count, 0)
            XCTAssertTrue(store.currentAccountHistory.isEmpty)
            if !disabled { XCTAssertNotNil(store.historyScopeMessage) }
        }
    }

    func testRefresh_whenProviderFails_keepsTrustedSnapshotAndMarksMenuAsOld() async {
        let sample = UsageTestFixtures.snapshot(used: 20)
        let store = UsageStore(provider: SequenceUsageProvider([.success(sample), .failure(.timedOut)]), defaults: defaults(), now: { sample.fetchedAt })
        await store.refresh()
        await store.refresh()
        XCTAssertEqual(store.snapshot, sample)
        XCTAssertNotNil(store.lastError)
        XCTAssertTrue(store.isSnapshotStale)
        XCTAssertTrue(store.menuTitle.contains("旧"))
    }

    func testRefresh_whenHistorySaveFails_preservesLiveQuotaAndReportsSeparateError() async {
        let sample = UsageTestFixtures.snapshot(used: 20)
        let store = UsageStore(provider: SequenceUsageProvider([.success(sample)]), defaults: defaults(), historyRepository: FailingUsageHistory(), now: { sample.fetchedAt })
        await store.refresh()
        XCTAssertEqual(store.snapshot, sample)
        XCTAssertNil(store.lastError)
        XCTAssertNotNil(store.historyError)
    }

    func testClearHistory_whenRecordsExist_clearsHistoryAndForecastBaseline() async throws {
        let sample = UsageTestFixtures.snapshot(used: 20)
        let repository = MemoryUsageHistory()
        let store = UsageStore(provider: SequenceUsageProvider([.success(sample)]), defaults: defaults(), historyRepository: repository, now: { sample.fetchedAt })
        await store.refresh()
        await store.clearHistory()
        XCTAssertTrue(store.historySamples.isEmpty)
        XCTAssertEqual(store.snapshot, sample)
        XCTAssertEqual(store.forecasts.first?.status, .insufficientData)
        let stored = try await repository.load(retentionDays: 30, now: sample.fetchedAt)
        XCTAssertEqual(stored, [])
    }

    func testRefresh_whenRecordingPausedAfterRestart_loadsExistingHistoryWithoutAppending() async {
        let preferences = defaults()
        preferences.set(false, forKey: "history.isEnabled")
        let repository = MemoryUsageHistory(samples: [UsageTestFixtures.sample(used: 20)])
        let sample = UsageTestFixtures.snapshot(used: 30)
        let store = UsageStore(provider: SequenceUsageProvider([.success(sample)]), defaults: preferences, historyRepository: repository, now: { sample.fetchedAt })
        await store.refresh()
        XCTAssertEqual(store.currentAccountHistory.count, 1)
        XCTAssertTrue(store.forecasts.isEmpty)
        let count = await repository.recordCount
        XCTAssertEqual(count, 0)
    }

    func testProRevocation_stopsNewSamplingAndForecasts_butKeepsExistingHistoryClearable() async {
        let sample = UsageTestFixtures.snapshot(used: 30, offset: 600)
        let repository = MemoryUsageHistory(samples: [UsageTestFixtures.sample(used: 10), UsageTestFixtures.sample(used: 20, offset: 300)])
        let store = UsageStore(provider: SequenceUsageProvider([.success(sample), .success(sample)]), defaults: defaults(),
                               historyRepository: repository, now: { sample.fetchedAt })
        await store.refresh()
        XCTAssertFalse(store.forecasts.isEmpty)
        store.setProAccess(false)
        await store.refresh()
        let recorded = await repository.recordCount
        XCTAssertEqual(recorded, 1)
        XCTAssertEqual(store.currentAccountHistory.count, 3)
        XCTAssertTrue(store.forecasts.isEmpty)
        await store.clearHistory()
        XCTAssertTrue(store.historySamples.isEmpty)
    }

    func testNotifications_byDefault_neverRequestPermissionOrSend() async {
        let sample = UsageTestFixtures.snapshot(used: 99)
        let sender = TestUsageNotificationSender()
        let store = UsageStore(provider: SequenceUsageProvider([.success(sample)]), defaults: defaults(), notificationSender: sender, now: { sample.fetchedAt })
        await store.refresh()
        XCTAssertFalse(store.notificationsEnabled)
        XCTAssertEqual(sender.requests, 0)
        XCTAssertTrue(sender.sent.isEmpty)
    }

    func testNotifications_afterExplicitEnable_deduplicateAcrossAppRestart() async {
        let preferences = defaults()
        let sender = TestUsageNotificationSender()
        let sample = UsageTestFixtures.snapshot(used: 99)
        let first = UsageStore(provider: SequenceUsageProvider([.success(sample), .success(sample)]), defaults: preferences, notificationSender: sender, now: { sample.fetchedAt })
        await first.setNotificationsEnabled(true)
        await first.refresh()
        await first.refresh()
        let restarted = UsageStore(provider: SequenceUsageProvider([.success(sample)]), defaults: preferences, notificationSender: sender, now: { sample.fetchedAt })
        await restarted.refresh()
        XCTAssertEqual(sender.requests, 1)
        XCTAssertEqual(sender.sent.count, 1)
    }

    func testNotifications_whenDenied_orSendFails_doNotPretendDeliverySucceeded() async {
        let sender = TestUsageNotificationSender()
        sender.currentPermission = .denied
        let sample = UsageTestFixtures.snapshot(used: 99)
        let store = UsageStore(provider: SequenceUsageProvider([.success(sample), .success(sample)]), defaults: defaults(), notificationSender: sender, now: { sample.fetchedAt })
        await store.setNotificationsEnabled(true)
        XCTAssertFalse(store.notificationsEnabled)
        XCTAssertEqual(sender.requests, 0)
        sender.currentPermission = .authorized
        await store.setNotificationsEnabled(true)
        sender.shouldFail = true
        await store.refresh()
        XCTAssertNotNil(store.notificationError)
        sender.shouldFail = false
        await store.refresh()
        XCTAssertEqual(sender.sent.count, 1)
        XCTAssertNil(store.notificationError)
    }

    func testRefresh_whenDisabledDuringRead_discardsLateResultAndDoesNotWriteHistory() async {
        let provider = DelayedUsageProvider()
        let repository = MemoryUsageHistory()
        let store = UsageStore(provider: provider, defaults: defaults(), historyRepository: repository)
        let refresh = Task { await store.refresh() }
        await provider.waitUntilRequested()
        store.isEnabled = false
        await provider.finish(UsageTestFixtures.snapshot(used: 20))
        await refresh.value
        XCTAssertNil(store.snapshot)
        let count = await repository.recordCount
        XCTAssertEqual(count, 0)
    }

    private func defaults() -> UserDefaults {
        let name = "UsageStorePhase1Tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        // 本文件测试已授权后的既有行为；未授权路径由 ProviderAuthorizationTests 单独覆盖。
        for source in UsageSource.allCases { preferences.set(ProviderAuthorization.version, forKey: ProviderAuthorization.key(for: source)) }
        addTeardownBlock { preferences.removePersistentDomain(forName: name) }
        return preferences
    }
}

private actor SequenceUsageProvider: UsageProvider {
    nonisolated let sourceName = "Fixture"
    private var values: [Result<UsageSnapshot, UsageProviderError>]
    private(set) var requests = 0
    init(_ values: [Result<UsageSnapshot, UsageProviderError>]) { self.values = values }
    func fetchSnapshot() throws -> UsageSnapshot {
        requests += 1
        guard !values.isEmpty else { throw UsageProviderError.unavailable }
        return try values.removeFirst().get()
    }
}

private actor MemoryUsageHistory: UsageHistoryPersisting {
    private var samples: [UsageHistorySample]
    private(set) var recordCount = 0
    private var failsRead = false
    init(samples: [UsageHistorySample] = []) { self.samples = samples }
    func load(retentionDays: Int, now: Date) throws -> [UsageHistorySample] {
        if failsRead { throw UsageHistoryError.invalidFile }
        return samples
    }
    func setReadFailure(_ failed: Bool) { failsRead = failed }
    func record(_ sample: UsageHistorySample, retentionDays: Int, now: Date) -> [UsageHistorySample] {
        recordCount += 1
        samples.append(sample)
        return samples
    }
    func clear() { samples = [] }
}

private actor DelayedHistoryRead: UsageHistoryPersisting {
    private var samples: [UsageHistorySample]
    private var delaysNextRead = true
    private var continuation: CheckedContinuation<Void, Never>?
    init(samples: [UsageHistorySample]) { self.samples = samples }
    func load(retentionDays: Int, now: Date) async -> [UsageHistorySample] {
        if delaysNextRead {
            delaysNextRead = false
            let original = samples
            await withCheckedContinuation { continuation = $0 }
            return original
        }
        return samples
    }
    func record(_ sample: UsageHistorySample, retentionDays: Int, now: Date) -> [UsageHistorySample] {
        samples.append(sample)
        return samples
    }
    func clear() { samples = [] }
    func waitUntilReading() async { while continuation == nil { await Task.yield() } }
    func finishRead() { continuation?.resume(); continuation = nil }
}

private actor FailingUsageHistory: UsageHistoryPersisting {
    func load(retentionDays: Int, now: Date) throws -> [UsageHistorySample] { throw UsageHistoryError.invalidFile }
    func record(_ sample: UsageHistorySample, retentionDays: Int, now: Date) throws -> [UsageHistorySample] { throw UsageHistoryError.invalidFile }
    func clear() throws { throw UsageHistoryError.invalidFile }
}

@MainActor
private final class TestUsageNotificationSender: UsageNotificationSending {
    var currentPermission = UsageNotificationPermission.notDetermined
    var requests = 0
    var sent: [UsageAlert] = []
    var shouldFail = false
    func permission() -> UsageNotificationPermission { currentPermission }
    func requestPermission() -> Bool {
        requests += 1
        currentPermission = .authorized
        return true
    }
    func send(_ alert: UsageAlert) throws {
        if shouldFail { throw UsageProviderError.unavailable }
        sent.append(alert)
    }
}

private actor DelayedUsageProvider: UsageProvider {
    nonisolated let sourceName = "Delayed fixture"
    private var continuation: CheckedContinuation<UsageSnapshot, Error>?
    func fetchSnapshot() async throws -> UsageSnapshot {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func waitUntilRequested() async {
        while continuation == nil { await Task.yield() }
    }
    func finish(_ snapshot: UsageSnapshot) {
        continuation?.resume(returning: snapshot)
        continuation = nil
    }
}
