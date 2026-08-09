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
