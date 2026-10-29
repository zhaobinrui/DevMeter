import AppKit
import SwiftUI
import XCTest
@testable import DevMeter

final class SupportInformationTests: XCTestCase {
    func testDiagnosticSummary_containsOnlyWhitelistedSupportFields() {
        let value = SupportInformation.diagnosticSummary(source: .codex, state: .failed,
                                                         version: "0.2.0 (2)", systemVersion: "14.0.0")
        XCTAssertEqual(value, "DevMeter 0.2.0 (2)\nmacOS 14.0.0\nSource: Codex\nState: failed")
        XCTAssertFalse(value.contains("@"))
        XCTAssertFalse(value.contains("token"))
        XCTAssertFalse(value.contains("/Users/"))
    }

    func testSupportState_prioritizesPauseAndFailure_withoutClaimingMissingDataIsCurrent() {
        XCTAssertEqual(SupportDataState.resolve(isEnabled: true, hasData: false, isStale: false, hasError: false, isAuthorized: false), .awaitingAuthorization)
        XCTAssertEqual(SupportDataState.resolve(isEnabled: false, hasData: true, isStale: true, hasError: true), .paused)
        XCTAssertEqual(SupportDataState.resolve(isEnabled: true, hasData: false, isStale: false, hasError: true), .failed)
        XCTAssertEqual(SupportDataState.resolve(isEnabled: true, hasData: false, isStale: false, hasError: false), .waiting)
        XCTAssertEqual(SupportDataState.resolve(isEnabled: true, hasData: true, isStale: true, hasError: false), .stale)
        XCTAssertEqual(SupportDataState.resolve(isEnabled: true, hasData: true, isStale: false, hasError: false), .current)
    }

    func testFeedbackURL_isFixedHTTPS_withoutEmbeddedUserData() {
        let url = SupportInformation.feedbackURL
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/zhaobinrui/DevMeter/issues")
        XCTAssertNil(url.query)
        XCTAssertNil(url.user)
        XCTAssertNil(url.password)
    }

    func testOfflineNotice_hasUniqueSections_andClaudeIsConditional() {
        let basic = PrivacyNotice.sections(includesClaude: false)
        XCTAssertEqual(basic.count, Set(basic.map(\.id)).count)
        XCTAssertTrue(basic.allSatisfy { !$0.title.isEmpty && !$0.body.isEmpty })
        XCTAssertFalse(basic.contains { $0.id == "claude" })
        XCTAssertEqual(PrivacyNotice.sections(includesClaude: true).filter { $0.id == "claude" }.count, 1)
    }

    @MainActor
    func testOfflineNotice_canBeHostedInNativeWindowContent() {
        let controller = NSHostingController(rootView: PrivacyPolicyView(includesClaude: true, close: {}))
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 480, height: 580))
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(controller.view.fittingSize.width, 0)
        XCTAssertGreaterThan(controller.view.fittingSize.height, 0)
        window.close()
    }

    @MainActor
    func testPrivacyWindow_closeAction_doesNotReturnWhenOriginatingWindowReopens() throws {
        let parent = ApplicationWindowController(title: "Privacy parent fixture", size: NSSize(width: 500, height: 650),
                                                minimumSize: NSSize(width: 500, height: 650))
        let privacy = PrivacyPolicyWindowController()
        defer { privacy.close(); parent.window?.close() }
        parent.show { Text("Privacy parent fixture") }
        privacy.show(includesClaude: false)
        let window = try XCTUnwrap(privacy.window)
        let content = try XCTUnwrap(window.contentViewController as? NSHostingController<PrivacyPolicyView>)
        XCTAssertTrue(window.isVisible)
        XCTAssertNil(window.sheetParent)
        XCTAssertNil(parent.window?.attachedSheet)
        // 调用与按钮/Escape 共用的关闭动作，再复用原父窗口；不依赖临时容器的 dismiss 环境。
        content.rootView.close()
        XCTAssertFalse(window.isVisible)
        parent.window?.orderOut(nil)
        parent.show { Text("Unused replacement") }
        XCTAssertFalse(window.isVisible)
        XCTAssertNil(parent.window?.attachedSheet)
        privacy.show(includesClaude: false)
        XCTAssertTrue(privacy.window === window)
        XCTAssertTrue(window.isVisible)
        privacy.close()
        XCTAssertFalse(window.isVisible)
    }

    @MainActor
    func testPrivacyWindow_standardCloseWithFloatingOrigin_staysClosedAndUpdatesScopeOnExplicitOpen() throws {
        let parent = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 340, height: 420),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        let privacy = PrivacyPolicyWindowController()
        defer { privacy.close(); parent.close() }
        parent.orderFrontRegardless()
        privacy.show(includesClaude: false)
        let window = try XCTUnwrap(privacy.window)
        XCTAssertNil(window.sheetParent)
        XCTAssertNil(parent.attachedSheet)
        XCTAssertFalse(window.isRestorable)
        window.performClose(nil)
        XCTAssertFalse(window.isVisible)
        parent.orderOut(nil)
        parent.orderFrontRegardless()
        XCTAssertFalse(window.isVisible)
        privacy.show(includesClaude: true)
        XCTAssertTrue(privacy.window === window)
        let content = try XCTUnwrap(window.contentViewController as? NSHostingController<PrivacyPolicyView>)
        XCTAssertTrue(content.rootView.includesClaude)
        XCTAssertTrue(window.isVisible)
    }
}
