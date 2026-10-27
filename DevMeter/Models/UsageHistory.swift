import Foundation

struct UsageHistorySample: Codable, Equatable, Sendable {
    let accountKey: String
    let fetchedAt: Date
    let limits: [UsageLimit]

    init(snapshot: UsageSnapshot, accountKey: String) {
        self.accountKey = accountKey
        fetchedAt = snapshot.fetchedAt
        limits = snapshot.limits
    }
}

struct UsageForecast: Identifiable, Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case insufficientData, noRecentConsumption, resetUnknown, awaitingReset
        case stale, exhausted, sufficientUntilReset, atRisk
    }

    let id: String
    let status: Status
    var exhaustionDate: Date? = nil
    var percentagePointsPerHour: Double? = nil

    var summary: String {
        switch status {
        case .insufficientData: "积累至少 10 分钟有效样本后预测"
        case .noRecentConsumption: "近期未观察到明显消耗"
        case .resetUnknown: "重置时间未知，暂不预测"
        case .awaitingReset: "已到重置时间，等待最新额度"
        case .stale: "数据已过期，暂不预测"
        case .exhausted: "当前额度已耗尽"
        case .sufficientUntilReset: "按近期速度，预计可用至重置"
        case .atRisk: "按近期速度，可能在重置前耗尽"
        }
    }
}

enum UsageForecastEngine {
    static func forecasts(
        snapshot: UsageSnapshot, samples: [UsageHistorySample], now: Date
    ) -> [UsageForecast] {
        snapshot.limits.map { limit in
            func result(_ status: UsageForecast.Status) -> UsageForecast {
                UsageForecast(id: limit.id, status: status)
            }
            guard now.timeIntervalSince(snapshot.fetchedAt) <= 300 else { return result(.stale) }
            guard let reset = limit.resetsAt else { return result(.resetUnknown) }
            guard reset > now else { return result(.awaitingReset) }
            if limit.remainingPercent == 0 { return result(.exhausted) }
            guard let account = snapshot.accountKey else { return result(.insufficientData) }

            let points = samples.filter {
                $0.accountKey == account && $0.fetchedAt <= snapshot.fetchedAt
                    && $0.fetchedAt >= snapshot.fetchedAt.addingTimeInterval(-7_200)
            }.sorted { $0.fetchedAt < $1.fetchedAt }.compactMap { sample -> (Date, Int)? in
                guard let value = sample.limits.first(where: { $0.id == limit.id }),
                      value.resetsAt == reset,
                      value.windowDurationMinutes == limit.windowDurationMinutes else { return nil }
                return (sample.fetchedAt, value.usedPercent)
            }
            var continuous: [(Date, Int)] = []
            for point in points + [(snapshot.fetchedAt, limit.usedPercent)] {
                if let previous = continuous.last {
                    if point.0 == previous.0 { continue }
                    // 断采、额度回退（含人工重置）都切断趋势，不能跨段外推。
                    if point.0.timeIntervalSince(previous.0) > 900 || point.1 < previous.1 {
                        continuous.removeAll()
                    }
                }
                continuous.append(point)
            }
            guard continuous.count >= 3, let first = continuous.first,
                  snapshot.fetchedAt.timeIntervalSince(first.0) >= 600 else {
                return result(.insufficientData)
            }
            let delta = limit.usedPercent - first.1
            guard delta >= 1 else { return result(.noRecentConsumption) }
            let rate = Double(delta) * 3_600 / snapshot.fetchedAt.timeIntervalSince(first.0)
            let exhaustion = snapshot.fetchedAt.addingTimeInterval(Double(limit.remainingPercent) / rate * 3_600)
            return UsageForecast(
                id: limit.id, status: exhaustion < reset ? .atRisk : .sufficientUntilReset,
                exhaustionDate: exhaustion, percentagePointsPerHour: rate
            )
        }
    }
}
