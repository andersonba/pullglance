import Foundation
import Testing
@testable import Pullglance

/// The trackpad pull: drag down from the top past the threshold, hold it a beat, lift, refresh once.
@Suite struct PullToRefreshTests {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func dragsAccumulateOnlyAtTheTopAndArmAtTheThreshold() {
        var pull = PullToRefreshState()
        let took1 = pull.drag(by: 10, atTop: true, at: t0)
        #expect(!took1)          // no gesture began
        pull.began(atTop: true)
        let took2 = pull.drag(by: 10, atTop: false, at: t0)
        #expect(!took2)         // the list is scrolled: let it scroll
        let took3 = pull.drag(by: 55, atTop: true, at: t0)
        #expect(took3)
        #expect(abs(pull.progress - 0.5) < 0.01)
        #expect(!pull.armed)
        let took4 = pull.drag(by: 60, atTop: true, at: t0)
        #expect(took4)
        #expect(pull.armed)
        let took5 = pull.drag(by: -100, atTop: true, at: t0)
        #expect(took5)          // easing back shrinks the pull and still belongs to it
        #expect(!pull.armed)
        #expect(pull.pull == 15)
    }

    /// A finger's centimetre is a lot of pixels: the threshold is far enough that a nudge never reaches it.
    @Test func theThresholdTakesARealPull() {
        #expect(PullToRefreshState.threshold >= 100)
    }

    /// The list follows the finger like a rubber band: quickly at first, then less and less, never past the cap.
    @Test func theStretchIsARubberBand() {
        var pull = PullToRefreshState()
        pull.began(atTop: true)
        var last: CGFloat = 0
        for _ in 0..<16 {                            // 16 × 25 = the ceiling, exactly
            _ = pull.drag(by: 25, atTop: true, at: t0)
            #expect(pull.stretch > last)
            #expect(pull.stretch < PullToRefreshState.maxStretch)
            last = pull.stretch
        }
        #expect(pull.pull == PullToRefreshState.maxPull)
        var atThreshold = PullToRefreshState()
        atThreshold.began(atTop: true)
        _ = atThreshold.drag(by: PullToRefreshState.threshold, atTop: true, at: t0)
        #expect(atThreshold.stretch > 28 && atThreshold.stretch < 40, "room for the ring, not a chasm: \(atThreshold.stretch)")
    }

    @Test func liftingWhileArmedLongEnoughFiresOnceAndResets() {
        var pull = PullToRefreshState()
        pull.began(atTop: true)
        _ = pull.drag(by: 120, atTop: true, at: t0)
        let fired = pull.ended(at: t0.addingTimeInterval(PullToRefreshState.armDwell + 0.05))
        #expect(fired)
        #expect(pull.pull == 0 && !pull.armed && !pull.dragging)
        let again = pull.ended(at: t0.addingTimeInterval(1))
        #expect(!again)
    }

    /// A flick crosses the threshold and lets go within a few frames: that is not a pull.
    @Test func aFlickThatLetsGoRightAwayDoesNotFire() {
        var pull = PullToRefreshState()
        pull.began(atTop: true)
        _ = pull.drag(by: 200, atTop: true, at: t0)
        #expect(pull.armed)
        let fired = pull.ended(at: t0.addingTimeInterval(0.03))
        #expect(!fired)
    }

    /// The dwell counts from the moment it armed, not from the start of the gesture; easing back resets it.
    @Test func theDwellStartsWhenItArmsAndResetsWhenItDisarms() {
        var pull = PullToRefreshState()
        pull.began(atTop: true)
        _ = pull.drag(by: 50, atTop: true, at: t0)
        _ = pull.drag(by: 70, atTop: true, at: t0.addingTimeInterval(0.5))        // armed at +0.5
        _ = pull.drag(by: -30, atTop: true, at: t0.addingTimeInterval(0.55))      // below: disarmed
        _ = pull.drag(by: 30, atTop: true, at: t0.addingTimeInterval(0.6))        // armed again at +0.6
        let tooSoon = pull.ended(at: t0.addingTimeInterval(0.65))
        #expect(!tooSoon)
        pull.began(atTop: true)
        _ = pull.drag(by: 120, atTop: true, at: t0.addingTimeInterval(1))
        let held = pull.ended(at: t0.addingTimeInterval(1 + PullToRefreshState.armDwell + 0.01))
        #expect(held)
    }

    /// A swipe on a row moves sideways first. Once a gesture is sideways it stays sideways: the pull never
    /// sees it, however far the fingers wander down afterwards.
    @Test func aGestureThatStartsSidewaysIsNeverAPull() {
        var pull = PullToRefreshState()
        pull.began(atTop: true)
        let took1 = pull.drag(by: 2, horizontal: 12, atTop: true, at: t0)
        #expect(!took1)
        let took2 = pull.drag(by: 150, horizontal: 0, atTop: true, at: t0)
        #expect(!took2)
        #expect(pull.pull == 0)
        let fired = pull.ended(at: t0.addingTimeInterval(1))
        #expect(!fired)
    }

    /// And a gesture that starts downward owns the pull: later sideways drift does not hand it to the row.
    @Test func aGestureThatStartsDownwardStaysAPull() {
        var pull = PullToRefreshState()
        pull.began(atTop: true)
        _ = pull.drag(by: 3, horizontal: 1, atTop: true, at: t0)        // too little to decide yet
        #expect(pull.axis == .undecided)
        let took = pull.drag(by: 10, horizontal: 2, atTop: true, at: t0)
        #expect(took)
        #expect(pull.axis == .vertical)
        let drift = pull.drag(by: 5, horizontal: 40, atTop: true, at: t0)
        #expect(drift, "swallowed: the row must not swipe under the pull")
        #expect(pull.pull == 15, "the points spent deciding the axis went to the view, not the pull")
    }

    @Test func liftingShortOfTheThresholdDoesNothing() {
        var pull = PullToRefreshState()
        pull.began(atTop: true)
        _ = pull.drag(by: 80, atTop: true, at: t0)
        let fired = pull.ended(at: t0.addingTimeInterval(1))
        #expect(!fired)
    }

    @Test func aGestureThatStartsBelowTheTopNeverBecomesAPull() {
        var pull = PullToRefreshState()
        pull.began(atTop: false)                     // a fling that reaches the top mid-gesture
        let took = pull.drag(by: 150, atTop: true, at: t0)
        #expect(!took)
        let fired = pull.ended(at: t0.addingTimeInterval(1))
        #expect(!fired)
    }

    @Test func scrollingUpAtTheTopIsNotAPull() {
        var pull = PullToRefreshState()
        pull.began(atTop: true)
        let took6 = pull.drag(by: -10, atTop: true, at: t0)
        #expect(!took6)
        #expect(pull.pull == 0)
    }
}
