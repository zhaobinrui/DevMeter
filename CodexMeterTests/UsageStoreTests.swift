import XCTest
@testable import CodexMeter

@MainActor
final class UsageStoreTests: XCTestCase {
    func testShowsFloatingPanel_whenNoPreferenceExists_shouldDefaultToTrue() {
        let defaults = makeDefaults()
        let store = UsageStore(provider: StubUsageProvider(), defaults: defaults)

        XCTAssertTrue(store.showsFloatingPanel)
    }

    func testShowsFloatingPanel_whenChanged_shouldPersistPreference() {
        let defaults = makeDefaults()
        let store = UsageStore(provider: StubUsageProvider(), defaults: defaults)

        store.showsFloatingPanel = false

        XCTAssertEqual(defaults.object(forKey: "floatingPanel.isEnabled") as? Bool, false)
    }

    func testFloatingPanelOpacity_whenChanged_shouldPersistPreference() {
        let defaults = makeDefaults()
        let store = UsageStore(provider: StubUsageProvider(), defaults: defaults)

        store.floatingPanelOpacity = 0.55

        XCTAssertEqual(defaults.object(forKey: "floatingPanel.opacity") as? Double, 0.55)
    }

    func testFloatingPanelOpacity_whenStoredValueIsOutsideRange_shouldClamp() {
        let defaults = makeDefaults()
        defaults.set(0.1, forKey: "floatingPanel.opacity")

        let store = UsageStore(provider: StubUsageProvider(), defaults: defaults)

        XCTAssertEqual(store.floatingPanelOpacity, 0.3)
    }

    func testRefresh_whenFetchSucceeds_publishesUpdatedSnapshot() async {
        let expectedSnapshot = UsageSnapshot(
            limits: [
                UsageLimit(
                    id: "codex.primary",
                    name: "5 小时额度",
                    windowDurationMinutes: 300,
                    usedPercent: 20,
                    resetsAt: nil
                )
            ],
            creditBalance: nil,
            sourceName: "Stub",
            fetchedAt: .now
        )
        var publishedSnapshot: UsageSnapshot?
        let store = UsageStore(
            provider: SuccessfulUsageProvider(snapshot: expectedSnapshot),
            defaults: makeDefaults(),
            didUpdateSnapshot: { publishedSnapshot = $0 }
        )

        await store.refresh()

        XCTAssertEqual(publishedSnapshot, expectedSnapshot)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "UsageStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private struct StubUsageProvider: UsageProvider {
    let sourceName = "Stub"

    func fetchSnapshot() async throws -> UsageSnapshot {
        throw UsageProviderError.unavailable
    }
}

private struct SuccessfulUsageProvider: UsageProvider {
    let sourceName = "Stub"
    let snapshot: UsageSnapshot

    func fetchSnapshot() async throws -> UsageSnapshot {
        snapshot
    }
}
