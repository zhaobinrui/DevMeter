import SwiftUI
import AppKit

@main
@MainActor
struct DevMeterApp: App {
    @StateObject private var store: UsageStore
    @StateObject private var floatingPanelController: FloatingPanelController
    @StateObject private var kindleServerController: KindleServerController
    @StateObject private var loginItemController: LoginItemController
    @StateObject private var updateController: UpdateController
    @StateObject private var historyWindowController = ApplicationWindowController(
        title: "Codex 历史与预测", size: NSSize(width: 740, height: 680),
        minimumSize: NSSize(width: 640, height: 500)
    )
    @StateObject private var settingsWindowController = ApplicationWindowController(
        title: "DevMeter 设置", size: NSSize(width: 500, height: 650),
        minimumSize: NSSize(width: 500, height: 650)
    )

    init() {
        LegacyPreferencesMigrator.migrateIfNeeded()
        let widgetPublisher = WidgetSnapshotPublisher()
        let store = UsageStore(
            provider: CodexLocalUsageProvider(identitySalt: Self.identitySalt()),
            historyRepository: LocalUsageHistoryRepository.applicationRepository(),
            notificationSender: SystemUsageNotificationSender(),
            didUpdateSnapshot: widgetPublisher.publish
        )
        let floatingPanelController = FloatingPanelController(store: store)
        let kindleServerController = KindleServerController(store: store)
        let loginItemController = LoginItemController()
        let updateController = UpdateController()
        _store = StateObject(wrappedValue: store)
        _floatingPanelController = StateObject(wrappedValue: floatingPanelController)
        _kindleServerController = StateObject(wrappedValue: kindleServerController)
        _loginItemController = StateObject(wrappedValue: loginItemController)
        _updateController = StateObject(wrappedValue: updateController)
        // XCTest 的宿主不启动真实数据采集、局域网服务或修改用户历史。
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            store.start()
            floatingPanelController.start()
            kindleServerController.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                store: store,
                floatingPanelController: floatingPanelController,
                toggleHistory: toggleHistory,
                showSettings: showSettings
            )
        } label: {
            // TimelineView 在 macOS 27 的状态项标签中会触发持续布局；刷新状态本身负责驱动标签更新。
            Label(store.menuTitle, systemImage: store.symbolName)
        }
        .menuBarExtraStyle(.window)

        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…", action: showSettings)
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .appSettings) {
                Button("历史与预测", action: toggleHistory)
                    .keyboardShortcut("h", modifiers: [.command, .shift])
            }
        }
    }

    private func toggleHistory() {
        historyWindowController.toggle { UsageHistoryView(store: store) }
    }

    private func showSettings() {
        settingsWindowController.show {
            SettingsView(store: store, floatingPanelController: floatingPanelController,
                         kindleServerController: kindleServerController, loginItemController: loginItemController,
                         updateController: updateController)
        }
    }

    private static func identitySalt() -> String {
        let defaults = UserDefaults.standard
        if let salt = defaults.string(forKey: "history.identitySalt") { return salt }
        let salt = UUID().uuidString
        defaults.set(salt, forKey: "history.identitySalt")
        return salt
    }
}
