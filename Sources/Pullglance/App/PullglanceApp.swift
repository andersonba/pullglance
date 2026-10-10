import SwiftUI

@main
struct PullglanceApp: App {
    @State private var store: PRStore

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        // Tooltips are the way to read truncated titles here, so show them faster than the 1 s system default.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 250])
        let store = PRStore(client: GHClient())
        store.start()
        _store = State(initialValue: store)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            MenuBarLabel(badgeCount: store.badgeCount, isError: store.lastError != nil)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }
}
