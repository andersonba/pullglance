import Testing
@testable import Pullglance

/// The trackpad pull: drag down from the top past the threshold, lift, refresh once.
@Suite struct PullToRefreshTests {
    @Test func dragsAccumulateOnlyAtTheTopAndArmAtTheThreshold() {
        var pull = PullToRefreshState()
        let took1 = pull.drag(by: 10, atTop: true)
        #expect(!took1)          // no gesture began
        pull.began(atTop: true)
        let took2 = pull.drag(by: 10, atTop: false)
        #expect(!took2)         // the list is scrolled: let it scroll
        let took3 = pull.drag(by: 28, atTop: true)
        #expect(took3)
        #expect(abs(pull.progress - 0.5) < 0.01)
        #expect(pull.stretch == 14)
        #expect(!pull.armed)
        let took4 = pull.drag(by: 40, atTop: true)
        #expect(took4)
        #expect(pull.armed)
        let took5 = pull.drag(by: -60, atTop: true)
        #expect(took5)          // easing back shrinks the pull and still belongs to it
        #expect(!pull.armed)
        #expect(pull.pull == 8)
    }

    @Test func liftingWhileArmedFiresOnceAndResets() {
        var pull = PullToRefreshState()
        pull.began(atTop: true)
        _ = pull.drag(by: 70, atTop: true)
        let fired = pull.ended()
        #expect(fired)
        #expect(pull.pull == 0 && !pull.armed && !pull.dragging)
        let again = pull.ended()
        #expect(!again)
    }

    @Test func liftingShortOfTheThresholdDoesNothing() {
        var pull = PullToRefreshState()
        pull.began(atTop: true)
        _ = pull.drag(by: 40, atTop: true)
        let fired = pull.ended()
        #expect(!fired)
    }

    @Test func thePullHasACeiling() {
        var pull = PullToRefreshState()
        pull.began(atTop: true)
        _ = pull.drag(by: 500, atTop: true)
        #expect(pull.pull == PullToRefreshState.maxPull)
        #expect(pull.stretch == PullToRefreshState.maxPull * PullToRefreshState.damping)
    }

    @Test func aGestureThatStartsBelowTheTopNeverBecomesAPull() {
        var pull = PullToRefreshState()
        pull.began(atTop: false)                     // a fling that reaches the top mid-gesture
        let took = pull.drag(by: 90, atTop: true)
        #expect(!took)
        let fired = pull.ended()
        #expect(!fired)
    }

    @Test func scrollingUpAtTheTopIsNotAPull() {
        var pull = PullToRefreshState()
        pull.began(atTop: true)
        let took6 = pull.drag(by: -10, atTop: true)
        #expect(!took6)
        #expect(pull.pull == 0)
    }
}
