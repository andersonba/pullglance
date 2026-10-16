import Foundation
import Observation

/// A newer version of the app that Sparkle found.
struct Release: Equatable, Sendable {
    let version: String
}

/// The update offer the menus render: "Update to X.Y.Z…" and nothing more. Sparkle checks on its schedule
/// and tells this object what it found; the app stays quiet until the person clicks, and the click hands
/// the session back to Sparkle, which shows its dialog with the release notes. Sparkle-free, so the state
/// can be tested; `SparkleUpdater` is the glue.
@MainActor
@Observable
final class Updater {
    /// The newer release the menus offer, if any.
    private(set) var available: Release?
    /// Keeps the Sparkle glue alive for as long as this object lives; nil in tests.
    var driver: AnyObject?
    private let present: @MainActor () -> Void

    /// `present` opens Sparkle's dialog: for the offer, or for a check asked by hand.
    init(present: @escaping @MainActor () -> Void) {
        self.present = present
    }

    /// "Update to X.Y.Z…" and "Check for updates…" both land here: Sparkle shows the update it knows about,
    /// or looks now and answers with its own "up to date" or error alert.
    func check() { present() }

    /// Sparkle found a scheduled update. When it shows the dialog itself (a check asked by hand), the menus
    /// have nothing to add; otherwise the offer is theirs.
    func scheduledUpdateFound(version: String, shownBySparkle: Bool) {
        available = shownBySparkle ? nil : Release(version: version)
    }

    /// Installed, skipped or dismissed: the offer leaves the menus. A skipped version stays quiet on the next
    /// scheduled check because Sparkle remembers it, not the app.
    func updateSessionFinished() { available = nil }
}
