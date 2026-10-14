import AppKit
import SwiftUI

/// Pull to refresh on the trackpad. SwiftUI's scroll view on macOS gives no rubber band when the list fits,
/// so the gesture is measured directly: while the list sits at its top, dragging down accumulates a pull,
/// the list and a ring follow it (a rubber band), the threshold arms it, and lifting the fingers after a
/// beat refreshes. Pure state here; `ScrollWheelMonitor` feeds it and `PullRing` draws it.
struct PullToRefreshState: Equatable {
    /// Finger travel that arms the pull. A finger's centimetre is a lot of points: a nudge never gets here.
    static let threshold: CGFloat = 110
    /// The list never slides further than this.
    static let maxStretch: CGFloat = 72
    /// How quickly the band gives at first (the classic 0.55).
    static let rubber: CGFloat = 0.55
    /// Travel beyond this is ignored; the band is nearly flat there anyway.
    static let maxPull: CGFloat = 400
    /// Armed for at least this long before the lift, or it was a flick, not a pull.
    static let armDwell: TimeInterval = 0.15
    /// Finger travel on one axis that decides which axis the gesture belongs to.
    static let axisLock: CGFloat = 8

    /// A gesture is either a row swipe or a pull, decided by its first points and kept until the lift, as
    /// AppKit does between horizontal and vertical scrolling. Sideways never becomes a pull, and a pull
    /// swallows the sideways drift that would otherwise swipe the row under it.
    enum Axis: Equatable { case undecided, vertical, horizontal }
    /// Mouse wheel only: notches at the top during this long are a probe ("am I at the top?"), answered
    /// with a glow, not a pull. One flick, however many notches, ends before it; keeping the wheel going
    /// past it starts the pull.
    static let wheelProbeDuration: TimeInterval = 0.4

    /// Finger travel past the top during the current gesture, in points (never negative).
    private(set) var pull: CGFloat = 0
    private(set) var armed = false
    private(set) var dragging = false
    /// When it last crossed the threshold; nil while below it.
    private(set) var armedAt: Date?
    private(set) var axis: Axis = .undecided
    private var travelX: CGFloat = 0
    private var travelY: CGFloat = 0

    var progress: CGFloat { min(pull / Self.threshold, 1) }
    /// How far the list is shown stretched: the rubber band, quick at first, flattening towards `maxStretch`.
    var stretch: CGFloat {
        (1 - 1 / (pull * Self.rubber / Self.maxStretch + 1)) * Self.maxStretch
    }

    /// A gesture that begins with the list already at its top may become a pull; one that scrolls up to the
    /// top and keeps going is just a scroll, however far it overshoots.
    mutating func began(atTop: Bool) {
        pull = 0
        armed = false
        armedAt = nil
        axis = .undecided
        travelX = 0
        travelY = 0
        dragging = atTop
    }

    /// A scroll step while dragging; positive deltas pull down. Returns whether the step was taken by the
    /// pull (and must not reach the views): only while the list is at its top and the pull is growing or open.
    /// Until the axis is decided the step passes through; a sideways decision ends the pull's interest.
    mutating func drag(by delta: CGFloat, horizontal: CGFloat = 0, atTop: Bool, at now: Date = Date()) -> Bool {
        guard dragging else { return false }
        if axis == .undecided {
            travelX += abs(horizontal)
            travelY += abs(delta)
            guard max(travelX, travelY) >= Self.axisLock else { return false }
            if travelX > travelY { axis = .horizontal; dragging = false; return false }
            axis = .vertical
        }
        guard atTop, pull > 0 || delta > 0 else { return false }
        pull = min(max(0, pull + delta), Self.maxPull)
        let wasArmed = armed
        armed = pull >= Self.threshold
        if armed, !wasArmed { armedAt = now }
        if !armed { armedAt = nil }
        return true
    }

    /// Fingers lifted. True when the pull should refresh: armed, and armed long enough that it was held,
    /// not flicked through.
    mutating func ended(at now: Date = Date()) -> Bool {
        let fire = dragging && armed && armedAt.map { now.timeIntervalSince($0) >= Self.armDwell } == true
        dragging = false
        pull = 0
        armed = false
        armedAt = nil
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

/// Trackpad scroll events (and key presses) of the view's own window. Each handler returns true to swallow
/// the event (the pull took it, the triage took it) or false to let it through. One AppKit view for both,
/// kept inside the list's background: an AppKit view at the popover's root costs the panel its glass.
struct ScrollWheelMonitor: NSViewRepresentable {
    let handler: @MainActor (NSEvent) -> Bool
    var keyHandler: (@MainActor (NSEvent) -> Bool)? = nil

    func makeNSView(context: Context) -> NSView {
        let view = MonitorView()
        view.handler = handler
        view.keyHandler = keyHandler
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? MonitorView)?.handler = handler
        (view as? MonitorView)?.keyHandler = keyHandler
    }

    final class MonitorView: NSView {
        var handler: (@MainActor (NSEvent) -> Bool)?
        var keyHandler: (@MainActor (NSEvent) -> Bool)?
        private var monitor: Any?

        /// Installed while the view is in a window; removed when it leaves (the popover closes), which is
        /// also when the view goes away, so no deinit bookkeeping is needed.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown]) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let handler = event.type == .keyDown ? self.keyHandler : self.handler
                guard let handler else { return event }
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
