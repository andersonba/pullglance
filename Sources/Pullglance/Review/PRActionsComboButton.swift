import AppKit
import SwiftUI

/// The pull request's actions as one `NSComboButton`: the primary for the PR's state on the button,
/// everything else in the attached menu. Merge when it is ready; else Approve, or Comment on the viewer's
/// own pull request, which GitHub lets nobody approve or request changes on (so neither is offered).
struct PRActionsComboButton: NSViewRepresentable {
    enum Primary { case approve, merge, comment }

    let session: ReviewSession
    let actions: ReviewBarActions
    let primary: Primary
    /// False on the viewer's own pull request: no Approve anywhere.
    var canReview = true

    func makeCoordinator() -> Coordinator { Coordinator(session: session, actions: actions) }

    func makeNSView(context: Context) -> NSComboButton {
        let button = NSComboButton(title: "", menu: NSMenu(), target: context.coordinator, action: #selector(Coordinator.primary))
        button.style = .split
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        return button
    }

    func updateNSView(_ button: NSComboButton, context: Context) {
        context.coordinator.primaryAction = primary
        context.coordinator.canReview = canReview
        switch primary {
        case .approve:
            button.title = String(localized: "Approve", bundle: .app)
            button.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        case .merge:
            button.title = String(localized: "Merge", bundle: .app)
            button.image = NSImage(systemSymbolName: "arrow.triangle.merge", accessibilityDescription: nil)
        case .comment:
            button.title = String(localized: "Comment", bundle: .app)
            button.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil)
        }
        button.isEnabled = session.pullRequest != nil
        button.menu = context.coordinator.menu()
    }

    @MainActor
    final class Coordinator: NSObject {
        let session: ReviewSession
        let actions: ReviewBarActions
        var primaryAction: Primary = .approve
        var canReview = true

        init(session: ReviewSession, actions: ReviewBarActions) {
            self.session = session
            self.actions = actions
        }

        @objc func primary() {
            switch primaryAction {
            case .approve: actions.approve()
            case .merge: actions.merge()
            case .comment: actions.comment()
            }
        }

        @objc func approve() { actions.approve() }
        @objc func comment() { actions.comment() }
        @objc func merge() { actions.merge() }
        @objc func snooze() { actions.snooze() }
        @objc func undo() { Task { await session.undo() } }
        @objc func unmarkAll() { Task { await session.unmarkAll() } }
        @objc func refresh() { Task { await session.refresh() } }
        @objc func openInBrowser() { actions.openInBrowser() }
        @objc func copyLink() { actions.copyLink() }
        @objc func hide() { actions.hide() }

        func menu() -> NSMenu {
            let menu = NSMenu()
            func add(_ title: String, _ selector: Selector, enabled: Bool = true) {
                let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
                item.target = self
                item.isEnabled = enabled
                menu.addItem(item)
            }
            menu.autoenablesItems = false
            // The two that are not on the button, and Approve only where GitHub would take it.
            if primaryAction != .comment { add(String(localized: "Comment…", bundle: .app), #selector(comment)) }
            if primaryAction != .merge { add(String(localized: "Merge…", bundle: .app), #selector(merge)) }
            if canReview, primaryAction != .approve { add(String(localized: "Approve…", bundle: .app), #selector(approve)) }
            let dormant = session.pullRequest.map(session.store.isDormant) == true
            add(String(localized: dormant ? "Wake" : "Snooze", bundle: .app), #selector(snooze))
            menu.addItem(.separator())
            var canUndo = false
            if case .marked(_, _, true) = session.notice { canUndo = true }
            add(String(localized: "Undo last marking", bundle: .app), #selector(undo), enabled: canUndo)
            add(String(localized: "Unmark all", bundle: .app), #selector(unmarkAll))
            menu.addItem(.separator())
            add(String(localized: "Refresh review state", bundle: .app), #selector(refresh))
            add(String(localized: "Open in Browser", bundle: .app), #selector(openInBrowser))
            add(String(localized: "Copy link", bundle: .app), #selector(copyLink))
            menu.addItem(.separator())
            add(String(localized: "Hide review bar", bundle: .app), #selector(hide))
            return menu
        }
    }
}
