import AppKit
import SwiftUI
import XCTest
@testable import DevMeter

@MainActor
final class ProviderAuthorizationTests: XCTestCase {
    func testFreshInstallAndOldPreferences_neverFetchUntilExplicitAuthorization() async {
        let preferences = defaults()
        preferences.set(true, forKey: "meter.isEnabled")
        preferences.set(true, forKey: "history.isEnabled")
        let provider = AuthorizationCountingProvider()
        let store = UsageStore(provider: provider, defaults: preferences)
        defer { store.stop() }
        store.start()
        await store.refresh()
        let count = await provider.requests
        XCTAssertEqual(count, 0)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertNil(store.lastError)
        XCTAssertTrue(store.menuTitle.contains("待授权"))

        store.grantProviderAccess(.codex)
        await provider.waitForRequest()
        XCTAssertTrue(store.isProviderAuthorized)
        XCTAssertTrue(ProviderAuthorization.isGranted(.codex, defaults: preferences))
    }

    func testAuthorization_persistsPerProvider_andOlderScopeVersionRequiresConsentAgain() {
        let preferences = defaults()
        ProviderAuthorization.setGranted(true, for: .codex, defaults: preferences)
        preferences.set(-1, forKey: ProviderAuthorization.key(for: .claudeCode))
        let provider = AuthorizationCountingProvider()
        let store = UsageStore(provider: provider, additionalProviders: [.claudeCode: provider], defaults: preferences)
        XCTAssertTrue(store.isProviderAuthorized)
        store.selectProvider(.claudeCode)
        XCTAssertFalse(store.isProviderAuthorized)
        store.grantProviderAccess(.claudeCode)
        let restarted = UsageStore(provider: provider, additionalProviders: [.claudeCode: provider], defaults: preferences)
        XCTAssertTrue(restarted.isProviderAuthorized)
        restarted.revokeProviderAccess(.claudeCode)
        XCTAssertFalse(ProviderAuthorization.isGranted(.claudeCode, defaults: preferences))
        XCTAssertTrue(ProviderAuthorization.isGranted(.codex, defaults: preferences))
    }

    func testSwitchToUnauthorizedSource_pausesPolling_andGrantResumesSelectedSourceOnly() async {
        let preferences = defaults()
        ProviderAuthorization.setGranted(true, for: .codex, defaults: preferences)
        let codex = AuthorizationCountingProvider()
        let claude = AuthorizationCountingProvider()
        let store = UsageStore(provider: codex, additionalProviders: [.claudeCode: claude], defaults: preferences)
        defer { store.stop() }
        store.start()
        await codex.waitForRequest()
        store.selectProvider(.claudeCode)
        await store.refresh()
        let blockedCount = await claude.requests
        XCTAssertEqual(blockedCount, 0)
        XCTAssertNil(store.snapshot)
        store.grantProviderAccess(.claudeCode)
        await claude.waitForRequest()
        XCTAssertTrue(store.isProviderAuthorized)
    }

    func testRevocation_clearsPublishedData_cancelsAndRejectsLateResult_withoutDeletingHistory() async {
        let preferences = defaults()
        ProviderAuthorization.setGranted(true, for: .codex, defaults: preferences)
        let provider = AuthorizationDelayedProvider()
        let history = AuthorizationHistory()
        var resetCount = 0
        let store = UsageStore(provider: provider, defaults: preferences, historyRepository: history,
                               didSelectProvider: { _ in resetCount += 1 })
        let pending = Task { await store.refresh() }
        await provider.waitForRequest()
        store.revokeProviderAccess(.codex)
        await provider.complete()
        await pending.value
        await store.refresh()
        XCTAssertNil(store.snapshot)
        XCTAssertNil(store.lastError)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(resetCount, 1)
        let count = await provider.requests
        XCTAssertEqual(count, 1)
        let preserved = await history.samples
        let recorded = await history.recordCount
        XCTAssertEqual(preserved.count, 1)
        XCTAssertEqual(recorded, 0)
    }

    func testRevocation_afterSuccess_removesCurrentAndCachedValues_withoutImplicitlyReauthorizing() async {
        let preferences = defaults()
        ProviderAuthorization.setGranted(true, for: .codex, defaults: preferences)
        let provider = AuthorizationCountingProvider()
        let store = UsageStore(provider: provider, additionalProviders: [.claudeCode: provider], defaults: preferences)
        await store.refresh()
        XCTAssertNotNil(store.snapshot)
        store.revokeProviderAccess(.codex)
        XCTAssertNil(store.snapshot)
        store.selectProvider(.claudeCode)
        store.selectProvider(.codex)
        await store.refresh()
        XCTAssertFalse(store.isProviderAuthorized)
        XCTAssertNil(store.snapshot)
        store.grantProviderAccess(.codex)
        XCTAssertNil(store.snapshot)
        await store.refresh()
        XCTAssertNotNil(store.snapshot)
    }

    func testReceiver_withoutConsent_returnsTwoBeforeReadingInput_orWritingCapture() throws {
        let preferences = defaults()
        let file = temporaryFile()
        let input = Pipe() // 写端保持打开；若误读输入，此测试会超时。
        let status = ClaudeStatusLineCommand.run(arguments: ["--claude-statusline"], defaults: preferences,
                                                file: file, input: input.fileHandleForReading,
                                                output: .nullDevice, errorOutput: .nullDevice)
        XCTAssertEqual(status, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
    }

    func testReceiver_withConsent_writesFilteredCapture_andRevocationStopsFurtherWrites() throws {
        let preferences = defaults()
        let file = temporaryFile()
        ProviderAuthorization.setGranted(true, for: .claudeCode, defaults: preferences)
        let pipe = Pipe()
        let output = Pipe()
        try pipe.fileHandleForWriting.write(contentsOf: Data(#"{"session_id":"private-canary","rate_limits":{"five_hour":{"used_percentage":20}}}"#.utf8))
        try pipe.fileHandleForWriting.close()
        XCTAssertEqual(ClaudeStatusLineCommand.run(arguments: ["--claude-statusline"], defaults: preferences,
                                                   file: file, input: pipe.fileHandleForReading,
                                                   output: output.fileHandleForWriting, errorOutput: .nullDevice), 0)
        try output.fileHandleForWriting.close()
        let summary = String(decoding: try XCTUnwrap(output.fileHandleForReading.readToEnd()), as: UTF8.self)
        XCTAssertTrue(summary.contains("Claude"))
        XCTAssertFalse(summary.contains("canary"))
        let previous = try Data(contentsOf: file.url)
        XCTAssertFalse(String(decoding: previous, as: UTF8.self).contains("canary"))
        ProviderAuthorization.setGranted(false, for: .claudeCode, defaults: preferences)
        XCTAssertEqual(ClaudeStatusLineCommand.run(arguments: ["--claude-statusline"], defaults: preferences,
                                                   file: file, input: .nullDevice,
                                                   output: .nullDevice, errorOutput: .nullDevice), 2)
        XCTAssertEqual(try Data(contentsOf: file.url), previous)
    }

    func testValidateOnly_withoutConsent_checksSyntheticInput_withoutWritingOrGranting() throws {
        let preferences = defaults()
        let file = temporaryFile()
        let input = Pipe()
        let output = Pipe()
        try input.fileHandleForWriting.write(contentsOf: Data("{}".utf8))
        try input.fileHandleForWriting.close()
        XCTAssertEqual(ClaudeStatusLineCommand.run(arguments: ["--claude-statusline", "--validate-only"], defaults: preferences,
                                                   file: file, input: input.fileHandleForReading,
                                                   output: output.fileHandleForWriting, errorOutput: .nullDevice), 0)
        try output.fileHandleForWriting.close()
        let filtered = try XCTUnwrap(output.fileHandleForReading.readToEnd())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: filtered) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["version", "capturedAt", "limits"])
        XCTAssertFalse(ProviderAuthorization.isGranted(.claudeCode, defaults: preferences))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
    }

    func testConsentPrompt_canBeHostedInNativeWindow() {
        let controller = NSHostingController(rootView: ProviderAuthorizationView(source: .codex, authorize: {}))
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 300, height: 400))
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(controller.view.fittingSize.height, 0)
        window.close()
    }

    private func defaults() -> UserDefaults {
        let name = "ProviderAuthorizationTests.\(UUID().uuidString)"
        let result = UserDefaults(suiteName: name)!
        addTeardownBlock { result.removePersistentDomain(forName: name) }
        return result
    }

    private func temporaryFile() -> ClaudeStatusLineFile {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DevMeter-Authorization-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return ClaudeStatusLineFile(url: directory.appendingPathComponent("claude.json"))
    }
}

private actor AuthorizationCountingProvider: UsageProvider {
    let sourceName = "Authorization fixture"
    private(set) var requests = 0
    func fetchSnapshot() -> UsageSnapshot { requests += 1; return UsageTestFixtures.snapshot(used: 20) }
    func waitForRequest() async { while requests == 0 { await Task.yield() } }
}

private actor AuthorizationDelayedProvider: UsageProvider {
    let sourceName = "Authorization delayed fixture"
    private(set) var requests = 0
    private var continuation: CheckedContinuation<UsageSnapshot, Never>?
    // 故意忽略取消，确保撤销权限后的迟到系统回调也无法恢复展示或写历史。
    func fetchSnapshot() async -> UsageSnapshot {
        requests += 1
        return await withCheckedContinuation { continuation = $0 }
    }
    func waitForRequest() async { while continuation == nil { await Task.yield() } }
    func complete() { continuation?.resume(returning: UsageTestFixtures.snapshot(used: 20)); continuation = nil }
}

private actor AuthorizationHistory: UsageHistoryPersisting {
    private(set) var samples = [UsageTestFixtures.sample(used: 10)]
    private(set) var recordCount = 0
    func load(retentionDays: Int, now: Date) -> [UsageHistorySample] { samples }
    func record(_ sample: UsageHistorySample, retentionDays: Int, now: Date) -> [UsageHistorySample] {
        recordCount += 1
        samples.append(sample)
        return samples
    }
    func clear() { samples = [] }
}
