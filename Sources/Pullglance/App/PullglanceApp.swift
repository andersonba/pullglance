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
            Divider()
            // Shortcuts live in the window's key monitor (page focus only). ⇧⌘V and the arrows have no key
            // equivalent here so the always-enabled menu cannot take Paste and Match Style or ⌘↓/⌘↑ from a text field.
            Button { ReviewWindowController.shared?.markTests() } label: { Text("Mark Tests as Viewed", bundle: .app) }
            Button { ReviewWindowController.shared?.undoMarking() } label: { Text("Undo Last Marking", bundle: .app) }
            Button { ReviewWindowController.shared?.markViewedAndNext() } label: { Text("Mark Viewed and Go to Next", bundle: .app) }
            Button { ReviewWindowController.shared?.nextFile() } label: { Text("Next File", bundle: .app) }
            Button { ReviewWindowController.shared?.previousFile() } label: { Text("Previous File", bundle: .app) }
            Button { ReviewWindowController.shared?.nextUnviewed() } label: { Text("Next Unviewed File", bundle: .app) }
            Button { ReviewWindowController.shared?.previousUnviewed() } label: { Text("Previous Unviewed File", bundle: .app) }
            Divider()
            Button { ReviewWindowController.shared?.approvePR() } label: { Text("Approve…", bundle: .app) }.keyboardShortcut("a", modifiers: [.command, .shift])
            Button { ReviewWindowController.shared?.commentPR() } label: { Text("Comment…", bundle: .app) }.keyboardShortcut("c", modifiers: [.command, .shift])
            Button { ReviewWindowController.shared?.mergePR() } label: { Text("Merge…", bundle: .app) }.keyboardShortcut("m", modifiers: [.command, .shift])
            Button { ReviewWindowController.shared?.refreshReview() } label: { Text("Refresh Review State", bundle: .app) }.keyboardShortcut("r", modifiers: [.command, .shift])
            Button { ReviewWindowController.shared?.toggleReviewBar() } label: { Text("Toggle Review Bar", bundle: .app) }.keyboardShortcut("b", modifiers: [.command, .option])
        }
    }
}
