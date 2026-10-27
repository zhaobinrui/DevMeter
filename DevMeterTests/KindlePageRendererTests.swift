import XCTest
@testable import DevMeter

final class KindlePageRendererTests: XCTestCase {
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
