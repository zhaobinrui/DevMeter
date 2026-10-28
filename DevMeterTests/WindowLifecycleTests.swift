import AppKit
import SwiftUI
import XCTest
@testable import DevMeter

@MainActor
final class WindowLifecycleTests: XCTestCase {
    func testFloatingDragRegion_whenHostedInSwiftUI_hasSizeAndReceivesTitleHitTesting() throws {
        let suite = "FloatingHitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(provider: WindowFixtureProvider(), defaults: defaults)
        let controller = FloatingPanelController(store: store, frameAutosaveName: nil)
        defer { controller.hide(); controller.panel?.close() }
        controller.show()
        let content = try XCTUnwrap(controller.panel?.contentView)
        content.layoutSubtreeIfNeeded()
        let region = try XCTUnwrap(findDragRegion(in: content))
        XCTAssertGreaterThan(region.bounds.width, 50)
        XCTAssertGreaterThan(region.bounds.height, 20)
        let point = region.convert(NSPoint(x: region.bounds.midX, y: region.bounds.midY), to: content.superview)
        XCTAssertTrue(content.hitTest(point) === region)
    }

    func testFloatingPosition_whenMovedAndRecreated_persistsAndRestoresBorderlessWindowAnchor() async throws {
        let suite = "FloatingPositionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let autosaveName = "DevMeter.FloatingPositionTests.\(UUID().uuidString)"
        defer {
            defaults.removePersistentDomain(forName: suite)
            NSWindow.removeFrame(usingName: autosaveName)
        }
        let store = UsageStore(provider: WindowFixtureProvider(), defaults: defaults)
        let first = FloatingPanelController(store: store, frameAutosaveName: autosaveName)
        defer { first.hide(); first.panel?.close() }
        first.show()
        let panel = try XCTUnwrap(first.panel)
        let moved = expectation(forNotification: NSWindow.didMoveNotification, object: panel)
        panel.setFrameOrigin(NSPoint(x: 240, y: 200))
        await fulfillment(of: [moved], timeout: 3)
        let anchor = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        XCTAssertNotNil(UserDefaults.standard.string(forKey: "NSWindow Frame \(autosaveName)"))

        // AppKit 不允许同一进程的两个窗口同时登记同一名称；模拟旧窗口结束后再恢复。
        first.hide()
        panel.delegate = nil
        panel.setFrameAutosaveName("")
        panel.close()
        let second = FloatingPanelController(store: store, frameAutosaveName: autosaveName)
        defer { second.hide(); second.panel?.setFrameAutosaveName(""); second.panel?.close() }
        second.show()
        let restored = try XCTUnwrap(second.panel)
        XCTAssertEqual(restored.frame.minX, anchor.x, accuracy: 1)
        XCTAssertEqual(restored.frame.maxY, anchor.y, accuracy: 1)
    }

    func testFloatingDrag_whenTitleIsDragged_movesInScreenPointsAndStopsAfterRelease() throws {
        let panel = makeDragPanel()
        defer { panel.close() }
        let region = FloatingPanelDragView(frame: NSRect(x: 0, y: 0, width: 200, height: 36))
        panel.contentView = region
        let event = try mouseEvent(.leftMouseDown, window: panel)

        XCTAssertTrue(region.acceptsFirstMouse(for: event))
        region.mouseDown(with: event)
        XCTAssertEqual(panel.frame.origin, NSPoint(x: 50, y: 50))
        region.mouseDragged(with: try mouseEvent(.leftMouseDragged, window: panel, location: NSPoint(x: 120, y: 70)))
        XCTAssertEqual(panel.frame.origin.x, 150, accuracy: 1)
        XCTAssertEqual(panel.frame.origin.y, 100, accuracy: 1)
        region.mouseUp(with: try mouseEvent(.leftMouseUp, window: panel))
        region.mouseDragged(with: try mouseEvent(.leftMouseDragged, window: panel, location: NSPoint(x: 200, y: 200)))
        XCTAssertEqual(panel.frame.origin.x, 150, accuracy: 1)
        XCTAssertEqual(panel.frame.origin.y, 100, accuracy: 1)
    }

    func testFloatingDrag_whenWindowIsImmovableOrInputIsNotLeftMouseDown_doesNotStartDrag() throws {
        let panel = makeDragPanel()
        defer { panel.close() }
        let region = FloatingPanelDragView(frame: NSRect(x: 0, y: 0, width: 200, height: 36))
        panel.contentView = region
        panel.isMovable = false
        region.mouseDown(with: try mouseEvent(.leftMouseDown, window: panel))
        region.mouseDragged(with: try mouseEvent(.leftMouseDragged, window: panel, location: NSPoint(x: 100, y: 100)))
        panel.isMovable = true
        region.mouseDown(with: try mouseEvent(.rightMouseDown, window: panel))
        region.mouseDragged(with: try mouseEvent(.leftMouseDragged, window: panel, location: NSPoint(x: 100, y: 100)))
        XCTAssertEqual(panel.frame.origin, NSPoint(x: 50, y: 50))
    }

    func testFloatingDrag_whenPrivacySheetIsAttached_doesNotMoveItsParent() throws {
        let panel = makeDragPanel()
        defer { panel.close() }
        let region = FloatingPanelDragView(frame: NSRect(x: 0, y: 0, width: 200, height: 36))
        panel.contentView = region
        panel.simulatedSheet = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        region.mouseDown(with: try mouseEvent(.leftMouseDown, window: panel))
        region.mouseDragged(with: try mouseEvent(.leftMouseDragged, window: panel, location: NSPoint(x: 100, y: 100)))
        XCTAssertEqual(panel.frame.origin, NSPoint(x: 50, y: 50))
    }

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

    private func findDragRegion(in view: NSView) -> FloatingPanelDragView? {
        if let region = view as? FloatingPanelDragView { return region }
        return view.subviews.lazy.compactMap { self.findDragRegion(in: $0) }.first
    }

    private func makeDragPanel() -> DragTrackingPanel {
        let panel = DragTrackingPanel(contentRect: NSRect(x: 50, y: 50, width: 280, height: 200),
                                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isMovable = true
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func mouseEvent(_ type: NSEvent.EventType, window: NSWindow,
                            location: NSPoint = NSPoint(x: 20, y: 20)) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                         timestamp: 1, windowNumber: window.windowNumber, context: nil,
                                         eventNumber: 1, clickCount: 1, pressure: 1))
    }
}

@MainActor
private final class DragTrackingPanel: NSPanel {
    var simulatedSheet: NSWindow?
    override var attachedSheet: NSWindow? { simulatedSheet }
}

private struct WindowFixtureProvider: UsageProvider {
    let sourceName = "Window fixture"
    func fetchSnapshot() async throws -> UsageSnapshot { throw UsageProviderError.unavailable }
}
