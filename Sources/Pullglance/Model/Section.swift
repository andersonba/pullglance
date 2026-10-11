import Foundation

/// The buckets a pull request can land in. Mirrors GitHub's own "Customize sections" list,
/// minus the merge queue. Raw values are persisted in UserDefaults; do not rename them.
enum Section: String, CaseIterable, Sendable, Identifiable {
    case needsAction
    case readyToMerge
    case waitingForReview
    case drafts
    case needsYourReview
    case needsTeamsReview
    /// Snoozed PRs of each tab. Pinned last, never counted, never a chip.
    case snoozedMine
    case snoozedReview

    var id: String { rawValue }

    var isSnoozed: Bool { self == .snoozedMine || self == .snoozedReview }

    enum Tab: Sendable { case mine, review }

    var tab: Tab {
        switch self {
        case .needsAction, .readyToMerge, .waitingForReview, .drafts, .snoozedMine: .mine
        case .needsYourReview, .needsTeamsReview, .snoozedReview: .review
        }
    }

    static let reviewSections: [Section] = [.needsYourReview, .needsTeamsReview]

    static func snoozed(for tab: Tab) -> Section { tab == .mine ? .snoozedMine : .snoozedReview }

    /// Everything that depends on you: fix it, merge it, or review it.
    static let defaultBadge: Set<Section> = [.needsAction, .readyToMerge, .needsYourReview]

    var title: String {
        switch self {
        case .needsAction: String(localized: "Needs action", bundle: .app)
        case .readyToMerge: String(localized: "Ready to merge", bundle: .app)
        case .waitingForReview: String(localized: "Waiting for review or checks", bundle: .app)
        case .drafts: String(localized: "Drafts", bundle: .app)
        case .needsYourReview: String(localized: "Needs your review", bundle: .app)
        case .needsTeamsReview: String(localized: "Needs your teams' review", bundle: .app)
        case .snoozedMine, .snoozedReview: String(localized: "Snoozed", bundle: .app)
        }
    }

    var detail: String {
        switch self {
        case .needsAction: String(localized: "Failing checks, requested changes, merge conflicts or branch behind base", bundle: .app)
        case .readyToMerge: String(localized: "Approved, checks green, no conflicts", bundle: .app)
        case .waitingForReview: String(localized: "Awaiting a review or with checks still running", bundle: .app)
        case .drafts: String(localized: "Started but not submitted for review", bundle: .app)
        case .needsYourReview: String(localized: "Requested from you directly", bundle: .app)
        case .needsTeamsReview: String(localized: "Requested from a team you belong to", bundle: .app)
        case .snoozedMine, .snoozedReview: String(localized: "Snoozed here until a new commit, review decision or CI result", bundle: .app)
        }
    }
}
