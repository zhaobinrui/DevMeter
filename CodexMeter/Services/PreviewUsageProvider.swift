import Foundation

struct PreviewUsageProvider: UsageProvider {
    let sourceName = "预览数据"

    func fetchSnapshot() async throws -> UsageSnapshot {
        try await Task.sleep(for: .milliseconds(250))

        let now = Date()
        return UsageSnapshot(
            limits: [
                UsageLimit(
                    id: "codex-five-hour",
                    name: "5 小时额度",
                    windowDurationMinutes: 300,
                    usedPercent: 32,
                    resetsAt: now.addingTimeInterval(2.5 * 60 * 60)
                ),
                UsageLimit(
                    id: "codex-weekly",
                    name: "周额度",
                    windowDurationMinutes: 7 * 24 * 60,
                    usedPercent: 58,
                    resetsAt: now.addingTimeInterval(3 * 24 * 60 * 60)
                )
            ],
            creditBalance: "120",
            sourceName: sourceName,
            fetchedAt: now
        )
    }
}
