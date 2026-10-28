import XCTest
@testable import DevMeter

@MainActor
final class ProviderSwitchTests: XCTestCase {
    func testSwitch_whenOldNotificationFinishesLate_doesNotChangeNewSourceErrorsOrDeduplication() async throws {
        for succeeds in [true, false] {
            let sender = ControlledSwitchNotificationSender()
            let preferences = defaults()
            preferences.set(true, forKey: "notifications.isEnabled")
            let codex = UsageSnapshot(limits: [UsageLimit(id: "codex.test", name: "窗口", windowDurationMinutes: 300,
                                                         usedPercent: 99, resetsAt: nil)],
                                      creditBalance: nil, sourceName: "Codex fixture", fetchedAt: .now,
                                      accountKey: String(repeating: "a", count: 64))
            let store = UsageStore(provider: SwitchSequenceProvider([.success(codex)]),
                                   additionalProviders: [.claudeCode: SwitchSequenceProvider([])],
                                   defaults: preferences, notificationSender: sender)
            let pending = Task { await store.refresh() }
            await sender.waitForSend()
            store.selectProvider(.claudeCode)
            sender.complete(succeeds: succeeds)
            await pending.value
            XCTAssertNil(store.notificationError)
            let data = try XCTUnwrap(preferences.data(forKey: "notifications.policy-claudeCode-v1"))
            let policy = try JSONDecoder().decode(UsageAlertPolicy.self, from: data)
            XCTAssertTrue(policy.deliveredIDs.isEmpty)
        }
    }

    func testClaudeLocalPipeline_fromFilteredFileThroughProvider_keepsLastTrustedValueOnReadFailureWithoutHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DevMeter-ClaudePipeline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = ClaudeStatusLineFile(url: directory.appendingPathComponent("claude.json"))
        let historyURL = directory.appendingPathComponent("history.json")
        let history = LocalUsageHistoryRepository(fileURL: historyURL)
        let receipt = Date.now.addingTimeInterval(-600)
        try file.write(ClaudeStatusLineCapture(data: Data(#"{"rate_limits":{"five_hour":{"used_percentage":25}}}"#.utf8), now: receipt))
        let store = UsageStore(provider: SwitchSequenceProvider([]),
                               additionalProviders: [.claudeCode: ClaudeStatusLineProvider(file: file)],
                               defaults: defaults(), historyRepository: history)
        store.selectProvider(.claudeCode)
        await store.refresh()
        XCTAssertEqual(store.snapshot?.mostConstrainedLimit?.remainingPercent, 75)
        XCTAssertEqual(store.snapshot?.fetchedAt, receipt)
        XCTAssertTrue(store.isSnapshotStale)
        XCTAssertTrue(store.forecasts.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyURL.path))
        let trusted = store.snapshot
        try Data("broken".utf8).write(to: file.url)
        await store.refresh()
        XCTAssertEqual(store.snapshot, trusted)
        XCTAssertNotNil(store.lastError)
    }

    func testSwitch_keepsSnapshotsAndFailuresSeparate_andDoesNotCombineWindows() async {
        let codex = sample(source: "Codex fixture", used: 20)
        let claude = sample(source: "Claude fixture", used: 90)
        let store = UsageStore(provider: SwitchSequenceProvider([.success(codex)]),
                               additionalProviders: [.claudeCode: SwitchSequenceProvider([.success(claude), .failure(.unavailable)])],
                               defaults: defaults())
        await store.refresh()
        store.selectProvider(.claudeCode)
        XCTAssertNil(store.snapshot)
        await store.refresh()
        await store.refresh()
        XCTAssertTrue(store.isSnapshotStale)
        store.selectProvider(.codex)
        XCTAssertEqual(store.snapshot, codex)
        XCTAssertNil(store.lastError)
        store.selectProvider(.claudeCode)
        XCTAssertEqual(store.snapshot, claude)
        XCTAssertEqual(store.snapshot?.limits.count, 1)
        XCTAssertNotNil(store.lastError)
        XCTAssertTrue(store.menuTitle.contains("Claude"))
        XCTAssertTrue(store.forecasts.isEmpty)
        XCTAssertTrue(store.currentAccountHistory.isEmpty)
    }

    func testSwitch_whenOldResponseArrivesLate_doesNotReplaceNewSourceOrClearItsRefreshingFlag() async {
        let codex = ControlledSwitchProvider()
        let claude = ControlledSwitchProvider()
        let store = UsageStore(provider: codex, additionalProviders: [.claudeCode: claude], defaults: defaults())
        let oldRefresh = Task { await store.refresh() }
        await codex.waitForRequest()
        store.selectProvider(.claudeCode)
        let newRefresh = Task { await store.refresh() }
        await claude.waitForRequest()
        await codex.complete(sample(source: "Old Codex", used: 10))
        await oldRefresh.value
        XCTAssertNil(store.snapshot)
        XCTAssertTrue(store.isRefreshing)
        let expected = sample(source: "New Claude", used: 70)
        await claude.complete(expected)
        await newRefresh.value
        XCTAssertEqual(store.snapshot, expected)
        XCTAssertFalse(store.isRefreshing)
    }

    func testSwitch_remembersSelectionAcrossRestart_andFallsBackWhenSourceIsMissing() {
        let preferences = defaults()
        let codex = SwitchSequenceProvider([])
        let claude = SwitchSequenceProvider([])
        let store = UsageStore(provider: codex, additionalProviders: [.claudeCode: claude], defaults: preferences)
        store.selectProvider(.claudeCode)
        let restarted = UsageStore(provider: codex, additionalProviders: [.claudeCode: claude], defaults: preferences)
        XCTAssertEqual(restarted.selectedProviderID, .claudeCode)
        let unavailable = UsageStore(provider: codex, defaults: preferences)
        XCTAssertEqual(unavailable.selectedProviderID, .codex)
        let pendingAppleVerification = UsageStore(provider: codex, additionalProviders: [.claudeCode: claude],
                                                  defaults: preferences, hasProAccess: false)
        XCTAssertEqual(pendingAppleVerification.selectedProviderID, .codex)
        pendingAppleVerification.setProAccess(true)
        XCTAssertEqual(pendingAppleVerification.selectedProviderID, .claudeCode)
    }

    func testSwitch_withoutPro_refusesSecondSource_andRevocationReturnsToFreeSource() {
        let store = UsageStore(provider: SwitchSequenceProvider([]), additionalProviders: [.claudeCode: SwitchSequenceProvider([])],
                               defaults: defaults(), hasProAccess: false)
        store.selectProvider(.claudeCode)
        XCTAssertEqual(store.selectedProviderID, .codex)
        store.setProAccess(true)
        store.selectProvider(.claudeCode)
        XCTAssertEqual(store.selectedProviderID, .claudeCode)
        store.setProAccess(false)
        XCTAssertEqual(store.selectedProviderID, .codex)
    }

    func testSnapshot_whenReceiptIsOldOrWindowExpired_marksOldWithoutResettingToFull() async {
        let timestamp = Date.now
        let expired = UsageSnapshot(limits: [UsageLimit(id: "claude.five-hour", name: "5 小时额度", windowDurationMinutes: 300,
                                                        usedPercent: 95, resetsAt: timestamp.addingTimeInterval(-1))],
                                    creditBalance: nil, sourceName: "Claude fixture", fetchedAt: timestamp)
        let store = UsageStore(provider: SwitchSequenceProvider([]), additionalProviders: [.claudeCode: SwitchSequenceProvider([.success(expired)])],
                               defaults: defaults(), now: { timestamp })
        store.selectProvider(.claudeCode)
        await store.refresh()
        XCTAssertTrue(store.isSnapshotStale)
        XCTAssertEqual(store.snapshot?.mostConstrainedLimit?.remainingPercent, 5)
        XCTAssertTrue(store.menuTitle.contains("旧"))
    }

    private func sample(source: String, used: Int) -> UsageSnapshot {
        UsageSnapshot(limits: [UsageLimit(id: source, name: "窗口", windowDurationMinutes: 300, usedPercent: used, resetsAt: nil)],
                      creditBalance: nil, sourceName: source, fetchedAt: .now)
    }

    private func defaults() -> UserDefaults {
        let suite = "ProviderSwitchTests.\(UUID().uuidString)"
        let result = UserDefaults(suiteName: suite)!
        // 本文件测试已授权后的既有行为；未授权路径由 ProviderAuthorizationTests 单独覆盖。
        for source in UsageSource.allCases { result.set(ProviderAuthorization.version, forKey: ProviderAuthorization.key(for: source)) }
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return result
    }
}

private actor SwitchSequenceProvider: UsageProvider {
    let sourceName = "Switch fixture"
    var values: [Result<UsageSnapshot, UsageProviderError>]
    init(_ values: [Result<UsageSnapshot, UsageProviderError>]) { self.values = values }
    func fetchSnapshot() throws -> UsageSnapshot {
        guard !values.isEmpty else { throw UsageProviderError.unavailable }
        return try values.removeFirst().get()
    }
}

private actor ControlledSwitchProvider: UsageProvider {
    let sourceName = "Delayed fixture"
    private var continuation: CheckedContinuation<UsageSnapshot, Never>?
    // 故意忽略取消，模拟系统回调迟到，验证展示层仍拒绝旧来源结果。
    func fetchSnapshot() async -> UsageSnapshot { await withCheckedContinuation { continuation = $0 } }
    func waitForRequest() async { while continuation == nil { await Task.yield() } }
    func complete(_ snapshot: UsageSnapshot) { continuation?.resume(returning: snapshot); continuation = nil }
}

@MainActor
private final class ControlledSwitchNotificationSender: UsageNotificationSending {
    private var continuation: CheckedContinuation<Void, Error>?
    func permission() async -> UsageNotificationPermission { .authorized }
    func requestPermission() async throws -> Bool { true }
    func send(_ alert: UsageAlert) async throws { try await withCheckedThrowingContinuation { continuation = $0 } }
    func waitForSend() async { while continuation == nil { await Task.yield() } }
    func complete(succeeds: Bool) {
        if succeeds { continuation?.resume() }
        else { continuation?.resume(throwing: UsageProviderError.unavailable) }
        continuation = nil
    }
}
