import AppKit
import SwiftUI

/// Swipe-to-reveal actions for a pull request row, Mail style, without a `List`.
///
/// The row is the leading "page" of a horizontal `ScrollView`; the action tiles follow it. AppKit routes a
/// two-finger gesture by its dominant axis, so vertical scrolling keeps going to the enclosing list while a
/// horizontal swipe slides the row with native inertia and rubber banding. `SwipeSnapBehavior` snaps the
/// row fully open or fully closed when the gesture ends. Only one row stays open: the parent owns `openRow`,
/// a row claims it while the user is dragging it, and any row whose id is not `openRow` closes itself.
struct SwipeActionsRow<Content: View, MenuContent: View>: View {
    let id: PullRequest.ID
    let actions: [PRAction]
    @Binding var openRow: PullRequest.ID?
    var isDormant = false
    var isRunning = false
    /// Reorder mode: no swiping.
    var isLocked = false
    let onAction: (PRAction) -> Void
    @ViewBuilder let menu: () -> MenuContent
    @ViewBuilder let content: () -> Content

    @State private var position = ScrollPosition(edge: .leading)
    @State private var offsetX: CGFloat = 0
    @State private var settle: Task<Void, Never>? = nil

    private var openWidth: CGFloat { CGFloat(actions.count + 1) * swipeTileWidth }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                content()
                    .containerRelativeFrame(.horizontal)
                HStack(spacing: 0) {
                    ForEach(actions, id: \.self) { action in
                        Button {
                            close()
                            onAction(action)
                        } label: {
                            SwipeTile(action: action, isDormant: isDormant)
                        }
                        .buttonStyle(.plain)
                        .disabled(isRunning && (action == .merge || action == .comment))
                    }
                    Menu {
                        menu()
                    } label: {
                        SwipeTile(action: nil)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                }
                .accessibilityHidden(offsetX <= 0)
            }
        }
        // With legacy scrollers SwiftUI would reserve the horizontal bar's height under every row;
        // PullglanceApp forces overlay scrollers app-wide (AppleShowScrollBars) so this stays the row's height.
        .scrollIndicators(.hidden)
        .scrollDisabled(isLocked)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .scrollTargetBehavior(SwipeSnapBehavior(openWidth: openWidth))
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in offsetX = x }
        .onScrollPhaseChange { _, phase in
            settle?.cancel()
            switch phase {
            case .interacting:
                // Only a drag by the user claims the row; a closing animation must not take it back.
                openRow = id
            case .idle:
                // Safety net for input that settles without consulting the target behavior (a legacy
                // wheel, for one). Debounced so a run of wheel ticks is judged once, not fought tick by tick.
                settle = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    guard !Task.isCancelled else { return }
                    let target: CGFloat = offsetX > openWidth * 0.5 ? openWidth : 0
                    if abs(offsetX - target) > 0.5 {
                        withAnimation(.snappy(duration: 0.2)) { position.scrollTo(x: target) }
                    }
                    if target == 0, openRow == id { openRow = nil }
                }
            default:
                break
            }
        }
        .onChange(of: openRow) { _, new in
            if new != id, offsetX > 0 { close() }
        }
        .onChange(of: actions) { _, _ in close() }
    }

    private func close() {
        withAnimation(.snappy(duration: 0.2)) { position.scrollTo(edge: .leading) }
        if openRow == id { openRow = nil }
    }
}

let swipeTileWidth: CGFloat = 64

/// Snap to fully open or fully closed. `target.rect` is where the scroll would come to rest after the
/// deceleration, so the midpoint rule already honors a fling without depending on the velocity's sign.
struct SwipeSnapBehavior: ScrollTargetBehavior {
    let openWidth: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        target.rect.origin.x = target.rect.origin.x > openWidth * 0.5 ? openWidth : 0
    }
}

/// One tile: symbol over a short label. `nil` is the "more" tile that opens the full menu.
/// Only the quick actions (`quickActions(for:)`) get a tile of their own. Styled like the pills
/// (soft tinted fill, tinted text) rather than solid Mail-style colors, which shouted on this popover.
struct SwipeTile: View {
    let action: PRAction?
    /// Snoozed rows show the snooze action as Wake.
    var isDormant = false

    var body: some View {
        VStack(spacing: 4) {
            // Fixed symbol box so every label sits on the same line whatever the symbol's height.
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(height: 18)
            title.font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint.mix(with: .primary, by: 0.45))
        .frame(width: swipeTileWidth)
        .frame(maxHeight: .infinity)
        .background(tint.opacity(0.16))
        .overlay(alignment: .leading) { Rectangle().fill(tint.opacity(0.25)).frame(width: 0.5) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var title: Text {
        switch action {
        case .merge: Text("Merge", bundle: .app)
        case .comment: Text("Comment", bundle: .app)
        case .open: Text("Open", bundle: .app)
        case .snooze: Text(isDormant ? "Wake" : "Snooze", bundle: .app)
        default: Text("More", bundle: .app)
        }
    }

    private var symbol: String {
        switch action {
        case .merge: "arrow.triangle.merge"
        case .comment: "text.bubble"
        case .open: "arrow.up.forward.square"
        case .snooze: isDormant ? "sun.max" : "moon.zzz"
        default: "ellipsis"
        }
    }

    private var tint: Color {
        switch action {
        case .merge: Color(red: 0.51, green: 0.31, blue: 0.87)
        case .comment: .blue
        case .open: .teal
        case .snooze: .orange
        default: .gray
        }
    }
}
