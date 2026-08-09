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
    static let appGroupIdentifier = "group.com.zhaobinrui.CodexMeter"
    static let widgetKind = "CodexMeterUsageWidget"

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

    static func load(defaults: UserDefaults? = nil) -> SharedUsageSnapshot? {
        guard let defaults = defaults ?? UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: snapshotKey) else {
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
