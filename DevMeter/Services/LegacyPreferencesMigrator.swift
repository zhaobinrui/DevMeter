import Foundation

enum LegacyPreferencesMigrator {
    static let legacyBundleIdentifier = "com.zhaobinrui.CodexMeter"
    static let migrationMarkerKey = "migration.codex-meter-preferences.v1"

    private static let unchangedKeys = [
        "meter.isEnabled",
        "kindle.isEnabled",
        "kindle.pairingToken",
        "floatingPanel.isEnabled",
        "floatingPanel.opacity",
        "meter.refreshIntervalSeconds",
    ]

    static func migrateIfNeeded(
        currentDefaults: UserDefaults = .standard,
        legacyDefaults: UserDefaults? = nil
    ) {
        guard !currentDefaults.bool(forKey: migrationMarkerKey) else {
            return
        }

        let legacyValues = legacyDefaults?.dictionaryRepresentation()
            ?? currentDefaults.persistentDomain(
                forName: legacyBundleIdentifier
            )
            ?? [:]

        for key in unchangedKeys where currentDefaults.object(forKey: key) == nil {
            if let value = legacyValues[key] {
                currentDefaults.set(value, forKey: key)
            }
        }

        migrateValue(
            from: "NSWindow Frame CodexMeter.FloatingPanel",
            to: "NSWindow Frame DevMeter.FloatingPanel",
            legacyValues: legacyValues,
            currentDefaults: currentDefaults
        )

        // Bundle ID 改名只执行一次迁移；新安装即使没有旧域也写入标记，避免每次启动扫描旧偏好。
        currentDefaults.set(true, forKey: migrationMarkerKey)
    }

    private static func migrateValue(
        from legacyKey: String,
        to currentKey: String,
        legacyValues: [String: Any],
        currentDefaults: UserDefaults
    ) {
        guard currentDefaults.object(forKey: currentKey) == nil,
              let value = legacyValues[legacyKey] else {
            return
        }
        currentDefaults.set(value, forKey: currentKey)
    }
}
