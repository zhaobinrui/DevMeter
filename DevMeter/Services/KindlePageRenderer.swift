import Foundation

enum KindlePageRenderer {
    static func render(snapshot: UsageSnapshot?, lastError: String?) -> String {
        let fetchedAt = snapshot.map { dateFormatter.string(from: $0.fetchedAt) } ?? "尚未获取"
        let rows = snapshot?.limits.map(renderLimit) ?? [emptyRow]
        let errorBlock = lastError.map {
            "<p class=\"error\">最新刷新失败：\(escape($0))</p>"
        } ?? ""
        let creditBlock = snapshot?.creditBalance.map {
            "<p class=\"credit\">Credits：\(escape($0))</p>"
        } ?? ""

        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <meta http-equiv="refresh" content="60">
          <title>DevMeter</title>
          <style>
            body{margin:0;padding:28px;background:#fff;color:#111;font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif}
            main{max-width:720px;margin:auto}h1{font-size:34px;margin:0 0 8px}.updated{color:#555;margin-bottom:28px}
            .limit{border-top:2px solid #111;padding:18px 0}.line{display:flex;justify-content:space-between;gap:20px;align-items:baseline}
            .name{font-size:22px;font-weight:600}.percent{font-size:42px;font-weight:700}.bar{height:18px;border:2px solid #111;margin:12px 0}
            .fill{height:100%;background:#111}.reset,.credit{font-size:17px}.error{border:2px solid #111;padding:12px;font-weight:600}
            footer{border-top:1px solid #777;margin-top:26px;padding-top:12px;color:#555;font-size:14px}
          </style>
        </head>
        <body><main>
          <h1>DevMeter</h1>
          <p class="updated">\(escape(snapshot?.sourceName ?? "等待当前来源")) · 更新时间：\(escape(fetchedAt))</p>
          \(rows.joined(separator: "\n"))
          \(creditBlock)
          \(errorBlock)
          <footer>页面每 60 秒自动刷新，仅提供只读额度信息。</footer>
        </main></body>
        </html>
        """
    }

    private static func renderLimit(_ limit: UsageLimit) -> String {
        let remaining = max(0, min(100, limit.remainingPercent))
        let reset = limit.resetsAt.map { dateFormatter.string(from: $0) } ?? "未知"

        return """
        <section class="limit">
          <div class="line"><span class="name">\(escape(limit.name))</span><span class="percent">\(remaining)%</span></div>
          <div class="bar"><div class="fill" style="width:\(remaining)%"></div></div>
          <div class="reset">重置时间：\(escape(reset))</div>
        </section>
        """
    }

    private static let emptyRow = """
    <section class="limit"><div class="line"><span class="name">等待首次刷新</span><span class="percent">—</span></div></section>
    """

    private static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
