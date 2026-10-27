import AppKit
import SwiftUI
import XCTest
@testable import DevMeter

@MainActor
final class WindowLifecycleTests: XCTestCase {
    func testToggle_whenHistoryIsShown_hidesAndReopensSameWindow() throws {
        let controller = makeWindowController()
        defer { controller.window?.close() }
        controller.toggle { Text("History fixture") }
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(window.isVisible)

        // 打开菜单栏后历史窗口会失焦，第二次点击仍应隐藏它。
        window.resignKey()
        controller.toggle { Text("Unused replacement") }
        XCTAssertFalse(window.isVisible)

        controller.toggle { Text("Unused replacement") }
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(controller.window === window)
    }

    func testShow_whenSettingsAlreadyExists_bringsBackSameWindowAfterClose() throws {
        let controller = makeWindowController()
        defer { controller.window?.close() }
        controller.show { Text("Settings fixture") }
        let window = try XCTUnwrap(controller.window)
        controller.show { Text("Unused replacement") }
        XCTAssertTrue(controller.window === window)
        XCTAssertTrue(window.isVisible)

        window.close()
        XCTAssertFalse(window.isVisible)
        controller.show { Text("Unused replacement") }
        XCTAssertTrue(controller.window === window)
        XCTAssertTrue(window.isVisible)
    }

    func testToggle_whenWindowIsMinimized_restoresInsteadOfHiding() async throws {
        let controller = makeWindowController()
        defer { controller.window?.close() }
        controller.show { Text("History fixture") }
        let window = try XCTUnwrap(controller.window)
        // AppKit 的最小化/恢复带异步动画，等待生命周期通知后再检查最终可见性。
        let minimized = expectation(forNotification: NSWindow.didMiniaturizeNotification, object: window)
        window.miniaturize(nil)
        await fulfillment(of: [minimized], timeout: 3)
        XCTAssertTrue(window.isMiniaturized)
        let restored = expectation(forNotification: NSWindow.didDeminiaturizeNotification, object: window)
        controller.toggle { Text("Unused replacement") }
        await fulfillment(of: [restored], timeout: 3)
        XCTAssertFalse(window.isMiniaturized)
        XCTAssertTrue(window.isVisible)
    }

    func testFloatingToggle_whenPreferenceStartsEnabled_usesActualVisibilityAndPersistsChanges() {
        let domain = "WindowLifecycleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = UsageStore(provider: WindowFixtureProvider(), defaults: defaults)
        let controller = FloatingPanelController(store: store, frameAutosaveName: nil)
        defer { controller.hide() }
        XCTAssertTrue(store.showsFloatingPanel)
        XCTAssertFalse(controller.isVisible)

        controller.toggle()
        XCTAssertTrue(controller.isVisible)
        XCTAssertTrue(defaults.bool(forKey: "floatingPanel.isEnabled"))
        controller.toggle()
        XCTAssertFalse(controller.isVisible)
        XCTAssertFalse(store.showsFloatingPanel)
        XCTAssertFalse(defaults.bool(forKey: "floatingPanel.isEnabled"))
        controller.toggle()
        XCTAssertTrue(controller.isVisible)
    }

    private func makeWindowController() -> ApplicationWindowController {
        ApplicationWindowController(title: "DevMeter Window Test", size: NSSize(width: 500, height: 400),
                                    minimumSize: NSSize(width: 300, height: 200))
    }
}

private struct WindowFixtureProvider: UsageProvider {
    let sourceName = "Window fixture"
    func fetchSnapshot() async throws -> UsageSnapshot { throw UsageProviderError.unavailable }
}
