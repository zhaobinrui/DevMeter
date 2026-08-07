import Foundation

struct UsageLimit: Identifiable, Equatable, Sendable {
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

    var mostConstrainedLimit: UsageLimit? {
        limits.min { $0.remainingPercent < $1.remainingPercent }
    }
}

