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
    func testOfflineNotice_canBeHostedInNativeSettingsSheetContent() {
        let controller = NSHostingController(rootView: PrivacyPolicyView(includesClaude: true))
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 480, height: 580))
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(controller.view.fittingSize.width, 0)
        XCTAssertGreaterThan(controller.view.fittingSize.height, 0)
        window.close()
    }
}
