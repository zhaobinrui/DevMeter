import Foundation

struct UsageLimit: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let windowDurationMinutes: Int?
    let usedPercent: Int
    let resetsAt: Date?

    var remainingPercent: Int {
        max(0, min(100, 100 - usedPercent))
    }
}

struct UsageSnapshot: Equatable, Sendable {
    let limits: [UsageLimit]
    let creditBalance: String?
    let sourceName: String
    let fetchedAt: Date
    // 身份只在适配层读取；领域与磁盘仅接收本机加盐后的个人账户分组。
    let accountKey: String?

    init(limits: [UsageLimit], creditBalance: String?, sourceName: String, fetchedAt: Date,
         accountKey: String? = nil) {
        self.limits = limits
        self.creditBalance = creditBalance
        self.sourceName = sourceName
        self.fetchedAt = fetchedAt
        self.accountKey = accountKey
    }

    var mostConstrainedLimit: UsageLimit? {
        limits.min { $0.remainingPercent < $1.remainingPercent }
    }
}
