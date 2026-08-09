import SwiftUI

@main
@MainActor
struct CodexMeterApp: App {
    @StateObject private var store: UsageStore
    @StateObject private var floatingPanelController: FloatingPanelController

    init() {
        let store = UsageStore(provider: CodexLocalUsageProvider())
        let floatingPanelController = FloatingPanelController(store: store)
        _store = StateObject(wrappedValue: store)
        _floatingPanelController = StateObject(wrappedValue: floatingPanelController)
        store.start()
        floatingPanelController.start()
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
                floatingPanelController: floatingPanelController
            )
        }
    }
}
