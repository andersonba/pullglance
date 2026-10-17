import AppKit

/// What a click or ↩ on a row does with its pull request: the Review Desk when it is on, else the browser,
/// landing where Settings › Review Desk says. One place, so the two gestures and the two destinations agree.
@MainActor
enum PullRequestOpener {
    static func open(_ pr: PullRequest, from tab: Section.Tab) {
        let settings = ReviewSettingsStore.shared.settings
        let landing = settings.landing.landing(for: tab)
        if settings.windowEnabled, let review = ReviewWindowController.shared {
            // On the diff, straight to the first file that still needs eyes.
            review.open(pr, landing: landing, firstUnviewed: landing == .files)
        } else {
            PopoverDismissal.open(ReviewAddress.url(for: pr, landing: landing))
        }
    }
}
