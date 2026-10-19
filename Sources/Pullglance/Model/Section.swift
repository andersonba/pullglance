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
    /// Snoozed PRs of each tab. Always last, never counted, never a chip.
    case snoozedMine
    case snoozedReview
    /// PRs the user pinned, per tab. Always first, shown only when there are any, counted where they came
    /// from (pinning is a view preference, not a state change), never a chip.
    case pinnedMine
    case pinnedReview
    /// Not a bucket: the quick filter that keeps only the pull requests assigned to the user (opened by a bot,
    /// an agent, a teammate). Those rows live in the state sections above; never ordered, counted or hidden.
    case assignedMine

    var id: String { rawValue }

    var isSnoozed: Bool { self == .snoozedMine || self == .snoozedReview }
    var isPinned: Bool { self == .pinnedMine || self == .pinnedReview }
    var isAssignedFilter: Bool { self == .assignedMine }
    /// Sections that sit at a fixed edge of the tab, outside the user's section order.
    var isFixed: Bool { isSnoozed || isPinned || isAssignedFilter }

    enum Tab: Sendable { case mine, review }

    var tab: Tab {
        switch self {
        case .needsAction, .readyToMerge, .waitingForReview, .drafts, .snoozedMine, .pinnedMine, .assignedMine: .mine
        case .needsYourReview, .needsTeamsReview, .snoozedReview, .pinnedReview: .review
        }
    }

    static let reviewSections: [Section] = [.needsYourReview, .needsTeamsReview]

    static func snoozed(for tab: Tab) -> Section { tab == .mine ? .snoozedMine : .snoozedReview }
    static func pinned(for tab: Tab) -> Section { tab == .mine ? .pinnedMine : .pinnedReview }

    /// Everything that depends on you: fix it, merge it, or review it.
    static let defaultBadge: Set<Section> = [.needsAction, .readyToMerge, .needsYourReview]

    /// The sections a user can reorder in a tab: everything but Pinned (always first) and Snoozed (always last).
    static func reorderable(in tab: Tab) -> [Section] {
        allCases.filter { $0.tab == tab && !$0.isFixed }
    }

    var title: String {
        switch self {
        case .needsAction: String(localized: "Needs action", bundle: .app)
        case .readyToMerge: String(localized: "Ready to merge", bundle: .app)
        case .waitingForReview: String(localized: "Waiting for review or checks", bundle: .app)
        case .drafts: String(localized: "Drafts", bundle: .app)
        case .needsYourReview: String(localized: "Needs your review", bundle: .app)
        case .needsTeamsReview: String(localized: "Needs your teams' review", bundle: .app)
        case .snoozedMine, .snoozedReview: String(localized: "Snoozed", bundle: .app)
        case .pinnedMine, .pinnedReview: String(localized: "Pinned", bundle: .app)
        case .assignedMine: String(localized: "Assigned to you", bundle: .app)
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
        case .pinnedMine, .pinnedReview: String(localized: "Pinned by you, always on top", bundle: .app)
        case .assignedMine: String(localized: "Opened by someone else with you as assignee", bundle: .app)
        }
    }
}
