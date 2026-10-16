import Foundation
import Testing
@testable import Pullglance

@MainActor
@Suite struct UpdaterTests {
    @Test func aScheduledUpdateIsOfferedInTheMenusOnly() {
        var presented = 0
        let updater = Updater(present: { presented += 1 })
        updater.scheduledUpdateFound(version: "0.2.0", shownBySparkle: false)
        #expect(updater.available == Release(version: "0.2.0"))
        #expect(presented == 0)
    }

    @Test func anUpdateSparkleShowsItselfIsNotOfferedTwice() {
        let updater = Updater(present: {})
        updater.scheduledUpdateFound(version: "0.2.0", shownBySparkle: true)
        #expect(updater.available == nil)
    }

    @Test func checkOpensSparkleWithOrWithoutAnOffer() {
        var presented = 0
        let updater = Updater(present: { presented += 1 })
        updater.check()
        updater.scheduledUpdateFound(version: "0.2.0", shownBySparkle: false)
        updater.check()
        #expect(presented == 2)
    }

    @Test func theOfferClearsWhenTheSessionEnds() {
        let updater = Updater(present: {})
        updater.scheduledUpdateFound(version: "0.2.0", shownBySparkle: false)
        updater.updateSessionFinished()
        #expect(updater.available == nil)
    }

    @Test func withoutAFeedThereIsNoUpdater() {
        // The test bundle, like the debug build, has no SUFeedURL: Sparkle must not start.
        #expect(SparkleUpdater.makeIfConfigured() == nil)
    }
}
