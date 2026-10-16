import AppKit

/// The right-click menu of the menu bar item: refresh, the GitHub shortcuts, Settings, Quit. MenuBarExtra
/// has no such thing, so a local monitor catches the right click (or ⌃-click) in the status bar window and
/// pops a native menu on the button; the left click keeps opening the popover.
@MainActor
final class StatusItemMenu: NSObject {
    private let store: PRStore
    private let updates: Updater?
    private var monitor: Any?

    init(store: PRStore, updates: Updater? = nil) {
        self.store = store
        self.updates = updates
        super.init()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self, self.isSecondaryClick(event), let button = self.statusButton(in: event.window) else { return event }
            PopoverDismissal.dismiss()
            self.menu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
            return nil
        }
    }

    private func isSecondaryClick(_ event: NSEvent) -> Bool {
        event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
    }

    private func statusButton(in window: NSWindow?) -> NSStatusBarButton? {
        guard let window, window.className.contains("NSStatusBarWindow"), let content = window.contentView else { return nil }
        return descendant(of: content)
    }

    private func descendant(of view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews { if let found = descendant(of: subview) { return found } }
        return nil
    }

    private func menu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, key: String = "") {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        if let release = updates?.available {
            add(String(format: String(localized: "Update to %@…", bundle: .app), release.version), #selector(checkForUpdates))
            menu.addItem(.separator())
        }
        add(String(localized: "Refresh now", bundle: .app), #selector(refresh), key: "r")
        menu.addItem(.separator())
        // Short titles: the longest item sets the menu's width.
        add(String(localized: "My PRs on GitHub", bundle: .app), #selector(openMine))
        add(String(localized: "Review requests on GitHub", bundle: .app), #selector(openReviews))
        menu.addItem(.separator())
        add(String(localized: "Welcome…", bundle: .app), #selector(welcome))
        add(String(localized: "Settings…", bundle: .app), #selector(openSettings), key: ",")
        menu.addItem(.separator())
        let version = NSMenuItem(title: String(format: String(localized: "Version %@", bundle: .app), AppInfo.version), action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        if updates != nil {
            add(String(localized: "Check for updates…", bundle: .app), #selector(checkForUpdates))
        }
        add(String(localized: "Quit", bundle: .app), #selector(quit), key: "q")
        return menu
    }

    @objc private func refresh() { Task { await store.refresh() } }
    /// The offer and the check by hand both hand the session to Sparkle: it shows the update it knows about
    /// with its notes, or looks now and answers with its own "up to date" or error alert.
    @objc private func checkForUpdates() { updates?.check() }
    @objc private func openMine() { NSWorkspace.shared.open(URL(string: "https://github.com/pulls")!) }
    @objc private func openReviews() { NSWorkspace.shared.open(URL(string: "https://github.com/pulls/review-requested")!) }
    /// Settings is a SwiftUI scene, opened by the `openSettings` environment action; the menu bar label,
    /// the one view of ours that is always alive, listens for this and calls it.
    @objc private func openSettings() {
        SettingsSelection.shared.tab = .general
        SettingsOpener.activate()
        NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
    }
    @objc private func welcome() { OnboardingWindowController.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}

extension Notification.Name {
    static let openSettingsRequested = Notification.Name("pullglance.openSettingsRequested")
}
