import AppKit
import SwiftUI

/// Pull to refresh on the trackpad. SwiftUI's scroll view on macOS gives no rubber band when the list fits,
/// so the gesture is measured directly: while the list sits at its top, dragging down accumulates a pull,
/// the list and a ring follow it (damped), the threshold arms it, and lifting the fingers refreshes.
/// Pure state here; `ScrollWheelMonitor` feeds it and `PullRing` draws it.
struct PullToRefreshState: Equatable {
    static let threshold: CGFloat = 56
    /// Points of finger travel per point of visible stretch.
    static let damping: CGFloat = 0.5
    /// Travel beyond this is ignored: the list never slides further than `maxPull * damping` points.
    static let maxPull: CGFloat = 112
    /// Mouse wheel only: notches at the top during this long are a probe ("am I at the top?"), answered
    /// with a glow, not a pull. One flick, however many notches, ends before it; keeping the wheel going
    /// past it starts the pull.
    static let wheelProbeDuration: TimeInterval = 0.4

    /// Finger travel past the top during the current gesture, in points (never negative).
    private(set) var pull: CGFloat = 0
    private(set) var armed = false
    private(set) var dragging = false

    var progress: CGFloat { min(pull / Self.threshold, 1) }
    /// How far the list is shown stretched.
    var stretch: CGFloat { pull * Self.damping }

    /// A gesture that begins with the list already at its top may become a pull; one that scrolls up to the
    /// top and keeps going is just a scroll, however far it overshoots.
    mutating func began(atTop: Bool) {
        pull = 0
        armed = false
        dragging = atTop
    }

    /// A scroll step while dragging; positive deltas pull down. Returns whether the step was taken by the
    /// pull (and must not scroll the list): only while the list is at its top and the pull is growing or open.
    mutating func drag(by delta: CGFloat, atTop: Bool) -> Bool {
        guard dragging, atTop, pull > 0 || delta > 0 else { return false }
        pull = min(max(0, pull + delta), Self.maxPull)
        armed = pull >= Self.threshold
        return true
    }

    /// Fingers lifted. True when the pull should refresh.
    mutating func ended() -> Bool {
        let fire = dragging && armed
        dragging = false
        pull = 0
        armed = false
        return fire
    }
}

/// The ring in the stretched gap: an arc that grows with the pull, a full ring slightly enlarged at the
/// threshold, the system spinner once the refresh is running.
struct PullRing: View {
    let state: PullToRefreshState
    let refreshing: Bool

    var body: some View {
        ZStack {
            if refreshing {
                ProgressView().controlSize(.small)
            } else {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: state.progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 14, height: 14)
        .scaleEffect(state.armed ? 1.15 : 1)
        .animation(.easeOut(duration: 0.15), value: state.armed)
        .accessibilityLabel(Text("Pull to refresh", bundle: .app))
    }
}

/// Trackpad scroll events of the view's own window, phase by phase. The handler returns true to swallow
/// the event (the pull took it) or false to let the list scroll.
struct ScrollWheelMonitor: NSViewRepresentable {
    let handler: @MainActor (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = MonitorView()
        view.handler = handler
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { (view as? MonitorView)?.handler = handler }

    final class MonitorView: NSView {
        var handler: (@MainActor (NSEvent) -> Bool)?
        private var monitor: Any?

        /// Installed while the view is in a window; removed when it leaves (the popover closes), which is
        /// also when the view goes away, so no deinit bookkeeping is needed.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window, let handler = self.handler else { return event }
                return MainActor.assumeIsolated { handler(event) } ? nil : event
            }
        }
    }
}

/// The answer to a wheel probe at the top: a soft glow on the list's top edge, nothing moves.
struct TopEdgeGlow: View {
    let visible: Bool

    var body: some View {
        LinearGradient(colors: [Color.accentColor.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
            .frame(height: 28)
            .opacity(visible ? 1 : 0)
            .animation(.easeOut(duration: visible ? 0.08 : 0.22), value: visible)
            .allowsHitTesting(false)
    }
}
