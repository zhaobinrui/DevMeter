import Foundation

enum UsageDisplayState: String, Codable, Equatable, Sendable {
    case idle, refreshing, ready, stale, failed, awaitingAuthorization, disabled, empty

    var title: String {
        switch self {
        case .idle: "等待首次刷新"
        case .refreshing: "正在刷新"
        case .ready: "最近一次有效数据"
        case .stale: "旧数据，等待有效刷新"
        case .failed: "无法读取额度"
        case .awaitingAuthorization: "待授权读取额度"
        case .disabled: "DevMeter 已关闭"
        case .empty: "暂无额度"
        }
    }

    var showsQuota: Bool { self == .ready || self == .stale || self == .refreshing }
}

struct SharedUsageLimit: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let remainingPercent: Int
    let resetsAt: Date?
}

struct SharedUsageSnapshot: Codable, Equatable, Sendable {
    let limits: [SharedUsageLimit]
    let creditBalance: String?
    let fetchedAt: Date
    let sourceName: String?
    // Optional 保持旧 Widget 快照可解码；错误只传通用状态，不向展示端复制原始错误。
    let displayState: UsageDisplayState?
    let staleAfterSeconds: TimeInterval?
    // 状态报告时间仅用于让“刷新中”自动失效，绝不能替代额度原始 fetchedAt。
    let stateUpdatedAt: Date?

    init(limits: [SharedUsageLimit], creditBalance: String?, fetchedAt: Date, sourceName: String? = nil,
         displayState: UsageDisplayState? = nil, staleAfterSeconds: TimeInterval? = nil, stateUpdatedAt: Date? = nil) {
        self.limits = limits
        self.creditBalance = creditBalance
        self.fetchedAt = fetchedAt
        self.sourceName = sourceName
        self.displayState = displayState
        self.staleAfterSeconds = staleAfterSeconds
        self.stateUpdatedAt = stateUpdatedAt
    }

    func state(at date: Date) -> UsageDisplayState {
        let state = displayState ?? (limits.isEmpty ? .idle : .ready)
        if state == .disabled || state == .awaitingAuthorization { return state }
        let refreshIsRecent = stateUpdatedAt.map { (-60...60).contains(date.timeIntervalSince($0)) } ?? false
        if limits.isEmpty {
            if state == .refreshing && !refreshIsRecent { return .idle }
            return state == .ready || state == .stale ? .empty : state
        }
        if state == .failed || state == .stale { return .stale }
        let age = date.timeIntervalSince(fetchedAt)
        if age < -60 || age > freshnessInterval || limits.contains(where: { $0.resetsAt.map { $0 <= date } ?? false }) {
            return .stale
        }
        return state == .refreshing && refreshIsRecent ? .refreshing : .ready
    }

    var freshnessInterval: TimeInterval {
        guard let interval = staleAfterSeconds, interval.isFinite else { return 300 }
        return max(300, min(600, interval))
    }

    func nextExpiry(after date: Date) -> Date? {
        let state = state(at: date)
        guard state.showsQuota, state != .stale else { return nil }
        let refreshExpiry = state == .refreshing ? stateUpdatedAt.map { $0.addingTimeInterval(61) } : nil
        let dataExpiry = limits.isEmpty ? [] : [fetchedAt.addingTimeInterval(freshnessInterval + 1)] + limits.compactMap(\.resetsAt)
        return (dataExpiry + [refreshExpiry].compactMap { $0 })
            .filter { $0 > date }.min()
    }

    var mostConstrainedLimit: SharedUsageLimit? {
        limits.min { $0.remainingPercent < $1.remainingPercent }
    }
}

enum SharedUsageSnapshotStorage {
    static let appGroupIdentifier = "group.com.zhaobinrui.devspace.meter"
    static let legacyAppGroupIdentifier = "group.com.zhaobinrui.CodexMeter"
    static let widgetKind = "DevMeterUsageWidget"

    private static let snapshotKey = "widget.latestUsageSnapshot"

    @discardableResult
    static func save(
        _ snapshot: SharedUsageSnapshot,
        defaults: UserDefaults? = nil
    ) -> Bool {
        guard let defaults = defaults ?? UserDefaults(suiteName: appGroupIdentifier),
              let data = try? encoder.encode(snapshot) else {
            return false
        }

        defaults.set(data, forKey: snapshotKey)
        return true
    }

    static func load(
        defaults: UserDefaults? = nil,
        legacyDefaults: UserDefaults? = nil
    ) -> SharedUsageSnapshot? {
        let primaryDefaults = defaults
            ?? UserDefaults(suiteName: appGroupIdentifier)
        if let snapshot = decode(from: primaryDefaults) {
            return snapshot
        }

        // 只有正常运行路径或显式传入旧测试域时才回读旧 App Group，避免自定义测试域
        // 意外读取开发机上的真实 Widget 数据。
        let fallbackDefaults = legacyDefaults
            ?? (defaults == nil
                ? UserDefaults(suiteName: legacyAppGroupIdentifier)
                : nil)
        guard let snapshot = decode(from: fallbackDefaults) else {
            return nil
        }

        if let primaryDefaults {
            _ = save(snapshot, defaults: primaryDefaults)
        }
        return snapshot
    }

    private static func decode(
        from defaults: UserDefaults?
    ) -> SharedUsageSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else {
            return nil
        }
        return try? decoder.decode(SharedUsageSnapshot.self, from: data)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
