import Foundation
import Testing
@testable import Pullglance

@MainActor
struct PopoverPresenterTests {
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
        for _ in 0..<6 {
            presenter.isPresented = true
            presenter.isPresented = false
        }
        presenter.isPresented = true
        #expect(!presenter.isPresented, "the tenth opening within the window is refused")
    }
}
