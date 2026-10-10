import AppKit
import SwiftUI

/// SwiftUI's `scrollIndicators` does not reach the legacy (always-visible) scroller the system uses when
/// "Show scroll bars: Always" is on. Reach the enclosing NSScrollView and force the thin overlay style.
struct OverlayScrollerStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let probe = NSView()
        DispatchQueue.main.async { apply(from: probe) }
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(from: nsView) }
    }

    private func apply(from view: NSView) {
        var current: NSView? = view
        while let candidate = current {
            if let scrollView = candidate as? NSScrollView {
                scrollView.scrollerStyle = .overlay
                scrollView.autohidesScrollers = true
                scrollView.hasVerticalScroller = false
                scrollView.hasHorizontalScroller = false
                return
            }
            current = candidate.superview
        }
    }
}
