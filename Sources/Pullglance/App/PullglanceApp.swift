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
            ReviewWindowController.configure(store: store)
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

        .commands { ReviewCommands() }

        Settings {
            SettingsView(store: store)
        }
    }
}

/// Menu items for the review window. The window also handles these keys itself while it is key (a focused
/// web view would swallow them otherwise); the menu makes them discoverable.
struct ReviewCommands: Commands {
    var body: some Commands {
        CommandMenu(Text("Review", bundle: .app)) {
            Button { ReviewWindowController.shared?.goBack() } label: { Text("Back", bundle: .app) }.keyboardShortcut("[")
            Button { ReviewWindowController.shared?.goForward() } label: { Text("Forward", bundle: .app) }.keyboardShortcut("]")
            Button { ReviewWindowController.shared?.reload() } label: { Text("Reload Page", bundle: .app) }.keyboardShortcut("r")
            Button { ReviewWindowController.shared?.stop() } label: { Text("Stop", bundle: .app) }.keyboardShortcut(".")
            Divider()
            Button { ReviewWindowController.shared?.focusAddress() } label: { Text("Open Location", bundle: .app) }.keyboardShortcut("l")
            Button { ReviewWindowController.shared?.openInBrowser() } label: { Text("Open Page in Browser", bundle: .app) }.keyboardShortcut("o", modifiers: [.command, .shift])
            Button { ReviewWindowController.shared?.showFind() } label: { Text("Find…", bundle: .app) }.keyboardShortcut("f")
            Divider()
            Button { ReviewWindowController.shared?.zoomIn() } label: { Text("Zoom In", bundle: .app) }.keyboardShortcut("+")
            Button { ReviewWindowController.shared?.zoomOut() } label: { Text("Zoom Out", bundle: .app) }.keyboardShortcut("-")
            Button { ReviewWindowController.shared?.zoomReset() } label: { Text("Actual Size", bundle: .app) }.keyboardShortcut("0")
        }
    }
}
