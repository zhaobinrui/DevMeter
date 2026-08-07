import SwiftUI

@main
@MainActor
struct CodexMeterApp: App {
    @StateObject private var store: UsageStore

    init() {
        let store = UsageStore(provider: CodexLocalUsageProvider())
        _store = StateObject(wrappedValue: store)
        store.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(store: store)
        } label: {
            Label(store.menuTitle, systemImage: store.symbolName)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }
}
