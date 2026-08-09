import SwiftUI

@main
@MainActor
struct CodexMeterApp: App {
    @StateObject private var store: UsageStore
    @StateObject private var floatingPanelController: FloatingPanelController
    @StateObject private var kindleServerController: KindleServerController
    @StateObject private var loginItemController: LoginItemController
    @StateObject private var updateController: UpdateController

    init() {
        let widgetPublisher = WidgetSnapshotPublisher()
        let store = UsageStore(
            provider: CodexLocalUsageProvider(),
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
        store.start()
        floatingPanelController.start()
        kindleServerController.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                store: store,
                floatingPanelController: floatingPanelController
            )
        } label: {
            Label(store.menuTitle, systemImage: store.symbolName)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                store: store,
                floatingPanelController: floatingPanelController,
                kindleServerController: kindleServerController,
                loginItemController: loginItemController,
                updateController: updateController
            )
        }
    }
}
