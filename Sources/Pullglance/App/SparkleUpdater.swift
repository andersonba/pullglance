import AppKit
import Sparkle

/// The glue between Sparkle and `Updater`. Sparkle checks the appcast on its schedule (Info.plist:
/// `SUFeedURL`, `SUScheduledCheckInterval`); in its gentle-reminder mode it tells this object what it found
/// instead of showing a dialog, the menus offer it, and the click hands the session back to Sparkle, which
/// shows the dialog with the release notes, downloads, installs and relaunches. Its callbacks arrive on the
/// main thread without saying so, hence the hops.
@MainActor
final class SparkleUpdater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    /// Nil without a feed: the debug build and the tests have no `SUFeedURL`, and Sparkle must not start there.
    static func makeIfConfigured() -> Updater? { SparkleUpdater(bundle: .main)?.updater }

    private var controller: SPUStandardUpdaterController!
    private(set) var updater: Updater!

    private init?(bundle: Bundle) {
        guard let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String, !feed.isEmpty else { return nil }
        super.init()
        // The controller takes this object as both delegates, so it is built after super.init and started by hand.
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        let updater = Updater(present: { controller.checkForUpdates(nil) })
        updater.driver = self
        self.updater = updater
        controller.startUpdater()
    }

    // MARK: SPUStandardUserDriverDelegate: gentle reminders. Nothing pops up by itself, launch included.

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool { false }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        let version = update.displayVersionString
        MainActor.assumeIsolated { updater.scheduledUpdateFound(version: version, shownBySparkle: handleShowingUpdate) }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { updater.updateSessionFinished() }
    }

    // MARK: SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        AppLog.shared.info("update: \(error.localizedDescription)")
    }
}
