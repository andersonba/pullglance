import Foundation
import Testing
@testable import Pullglance

/// What the host does with the page when nobody is looking at it: the window closing lets the page go,
/// and a crash answers to whether the page is on screen.
@MainActor
struct ReviewWebHostLifecycleTests {
    @Test func parkingLetsThePageGoUntilTheNextLoad() {
        let host = ReviewWebHost()
        #expect(!host.isParked)
        host.park()
        #expect(host.isParked)
        host.load(URL(string: "https://github.com/acme/web/pull/7")!)
        #expect(!host.isParked)
    }

    @Test func aCrashOnScreenReloadsOnceThenGivesUp() {
        let host = ReviewWebHost()
        let t0 = Date(timeIntervalSince1970: 1_000)
        #expect(host.contentProcessTerminated(now: t0, onScreen: true) == .reload)
        #expect(host.contentProcessTerminated(now: t0.addingTimeInterval(5), onScreen: true) == .loop)
        #expect(host.contentProcessTerminated(now: t0.addingTimeInterval(30), onScreen: true) == .reload, "a crash long after the last one is a fresh one")
    }

    /// A page nobody sees is not worth a web process: the crash leaves it gone, and the next open loads
    /// again instead of trusting a URL that points at nothing.
    @Test func aCrashOffScreenIsNotReloaded() {
        let host = ReviewWebHost()
        #expect(host.contentProcessTerminated(now: Date(), onScreen: false) == .pageGone)
        #expect(host.isParked)
        host.park()
        #expect(host.contentProcessTerminated(now: Date(), onScreen: true) == .pageGone, "a parked page has nothing to bring back")
    }
}
