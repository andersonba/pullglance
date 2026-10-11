import SwiftUI

@main
struct PullglanceApp: App {
    @State private var store: PRStore
    private let snapshot: SnapshotOptions?

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
        _store = State(initialValue: store)
        snapshot = SnapshotOptions.parse(CommandLine.arguments)
        if let snapshot {
            // Debug run: render to files and leave; no menu bar item, no timer.
            Task { @MainActor in
                _ = await SnapshotRunner.run(snapshot, store: store)
                exit(0)
            }
        } else {
            store.start()
        }
        Task { await AvatarCache.shared.pruneDisk() }
    }

    var body: some Scene {
        // A snapshot run keeps the item out of the menu bar; SceneBuilder has no `if`.
        MenuBarExtra(isInserted: .constant(snapshot == nil)) {
            PopoverView(store: store)
        } label: {
            MenuBarLabel(text: store.badgeText, hasData: store.badgeCount != nil, isError: store.lastError != nil)
                .help(Text(verbatim: store.badgeDescription ?? ""))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }
}
