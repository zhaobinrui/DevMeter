import Foundation

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
