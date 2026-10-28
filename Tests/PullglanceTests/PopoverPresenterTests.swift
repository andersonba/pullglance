import Foundation
import Testing
@testable import Pullglance

@MainActor
struct PopoverPresenterTests {
    /// Opens and closes `count` times, as a presentation feeding on itself would.
    private func burst(_ presenter: PopoverPresenter, _ count: Int) {
        for _ in 0..<count {
            presenter.isPresented = true
            presenter.isPresented = false
        }
    }

    /// A presentation that keeps coming back on its own (the library re-presenting a window that loses
    /// the key the moment it appears) is cut off: after a burst of openings the presenter refuses and
    /// settles closed, instead of pinning the main thread.
    @Test func burstOfPresentationsTripsTheBreaker() {
        let presenter = PopoverPresenter()
        for _ in 0..<3 {
            presenter.isPresented = true
            #expect(presenter.isPresented, "a few openings in a row are ordinary")
            presenter.isPresented = false
        }
        burst(presenter, 6)
        presenter.isPresented = true
        #expect(!presenter.isPresented, "the tenth opening within the window is refused")
    }

    /// Refusing one opening is not enough: the loop that tripped the breaker is still there, and with the
    /// history cleared the next opening would go through and feed it again. Once tripped, the breaker
    /// stays open for the whole window, then lets the popover open as usual.
    @Test func aTrippedBreakerStaysOpenForTheWindow() {
        var now = Date(timeIntervalSince1970: 1_000)
        let presenter = PopoverPresenter(now: { now })
        burst(presenter, 9)
        presenter.isPresented = true
        #expect(!presenter.isPresented, "tripped")
        presenter.isPresented = true
        #expect(!presenter.isPresented, "still refused right after the trip")
        now = now.addingTimeInterval(1)
        presenter.isPresented = true
        #expect(!presenter.isPresented, "the cooldown is the burst window, not a single refusal")
        now = now.addingTimeInterval(1.5)
        presenter.isPresented = true
        #expect(presenter.isPresented, "after the window, the popover opens again")
    }
}
