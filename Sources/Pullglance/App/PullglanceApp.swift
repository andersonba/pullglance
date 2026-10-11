import SwiftUI

@main
struct PullglanceApp: App {
    @State private var store: PRStore

    init() {
        // Thin overlay scrollers app-wide, whatever "Show scroll bars" says and even with a mouse plugged in.
        // With legacy scrollers SwiftUI reserves the bar's height under every swipeable row (its horizontal
        // ScrollView), which would stretch the list. AppKit reads this key from the app's own defaults
        // domain, which precedes the global one.
        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
        NSApplication.shared.setActivationPolicy(.accessory)
        // Tooltips are the way to read truncated titles here, so show them faster than the 1 s system default.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 250])
        let store = PRStore(client: GHClient())
        store.start()
        _store = State(initialValue: store)
        Task { await AvatarCache.shared.pruneDisk() }
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
