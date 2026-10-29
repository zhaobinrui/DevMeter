import XCTest
@testable import DevMeter

final class KindlePageRendererTests: XCTestCase {
    func testRender_atResetTime_marksOldAndKeepsOriginalQuotaAndDate() {
        let date = Date(timeIntervalSince1970: 1_900_000_000)
        let display = SharedUsageSnapshot(limits: [SharedUsageLimit(id: "one", name: "Quota", remainingPercent: 37,
                                                                   resetsAt: date.addingTimeInterval(30))],
                                          creditBalance: nil, fetchedAt: date, sourceName: "Claude Code", displayState: .ready)
        let fresh = KindlePageRenderer.render(display: display, now: date)
        let old = KindlePageRenderer.render(display: display, now: date.addingTimeInterval(30))
        XCTAssertFalse(fresh.contains("旧数据"))
        XCTAssertTrue(old.contains("旧数据"))
        XCTAssertTrue(old.contains("37%"))
        XCTAssertFalse(old.contains("class=\"percent\">100%"))
        XCTAssertTrue(old.contains("Claude Code"))
    }

    func testRender_whenAuthorizationRevokedOrDisabled_hidesAllCachedQuotaAndCredits() {
        for state in [UsageDisplayState.awaitingAuthorization, .disabled] {
            let display = SharedUsageSnapshot(limits: [SharedUsageLimit(id: "one", name: "OLD_QUOTA", remainingPercent: 37, resetsAt: nil)],
                                              creditBalance: "OLD_CREDITS", fetchedAt: .now, sourceName: "Codex", displayState: state)
            let html = KindlePageRenderer.render(display: display)
            XCTAssertTrue(html.contains(state.title))
            XCTAssertFalse(html.contains("OLD_QUOTA"))
            XCTAssertFalse(html.contains("OLD_CREDITS"))
            XCTAssertFalse(html.contains("37%"))
        }
    }

    func testRender_includesQuotaAndEscapesUntrustedText() {
        let snapshot = UsageSnapshot(
            limits: [
                UsageLimit(
                    id: "codex.primary",
                    name: "<script>alert(1)</script>",
                    windowDurationMinutes: 300,
                    usedPercent: 35,
                    resetsAt: nil
                )
            ],
            creditBalance: "10 & more",
            sourceName: "Test",
            fetchedAt: Date(timeIntervalSince1970: 1_900_000_000)
        )

        let html = KindlePageRenderer.render(snapshot: snapshot, lastError: "bad <response>")

        XCTAssertTrue(html.contains("65%"))
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        XCTAssertTrue(html.contains("10 &amp; more"))
        XCTAssertTrue(html.contains("bad &lt;response&gt;"))
        XCTAssertFalse(html.contains("<script>alert(1)</script>"))
    }

    func testRender_withoutSnapshot_showsWaitingState() {
        let html = KindlePageRenderer.render(snapshot: nil, lastError: nil)

        XCTAssertTrue(html.contains("等待首次刷新"))
        XCTAssertTrue(html.contains("尚未获取"))
    }
}
