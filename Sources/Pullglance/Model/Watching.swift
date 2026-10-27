import Foundation

/// What a watched pull request did since the watch began: one thing, the one worth a notification.
enum WatchMovement: Hashable, Sendable, Codable {
    case merged
    case closed
    case checksFailed
    case conflicts
    case changesRequested
    case approved
    case checksPassed
    case behindBase
    /// Moved in the base branch's merge queue, to this 1-based position.
    case queuePosition(Int)

    /// The notification's title, and the "Moved" pill's reason.
    var title: String {
        switch self {
        case .merged: String(localized: "Merged", bundle: .app)
        case .closed: String(localized: "Closed", bundle: .app)
        case .checksFailed: String(localized: "Checks failed", bundle: .app)
        case .conflicts: String(localized: "Conflicts with the base branch", bundle: .app)
        case .changesRequested: String(localized: "Changes requested", bundle: .app)
        case .approved: String(localized: "Approved", bundle: .app)
        case .checksPassed: String(localized: "Checks passed", bundle: .app)
        case .behindBase: String(localized: "Behind the base branch", bundle: .app)
        case .queuePosition(let position): String(format: String(localized: "Position %lld in the merge queue", bundle: .app), position)
        }
    }
}

/// A watched pull request, with the state it had when the watch began (or was re-based on a new commit).
/// Kept in defaults, so a watch survives a relaunch. The rule is deliberately like the snooze's: things
/// that ask for action count, a comment does not.
struct WatchMark: Equatable, Sendable, Codable {
    let repo: String
    let number: Int
    /// For the notification, which may arrive after the row has left the lists.
    let title: String
    let url: URL
    let headRefOid: String
    let reviewDecision: ReviewDecision?
    let ciState: CIState
    let hasConflicts: Bool
    let isBehindBase: Bool
    let mergeQueuePosition: Int?
    let since: Date

    init(_ pr: PullRequest, since: Date = Date()) {
        repo = pr.repo
        number = pr.number
        title = pr.title
        url = pr.url
        headRefOid = pr.headRefOid
        reviewDecision = pr.reviewDecision
        ciState = pr.ciState
        hasConflicts = pr.hasConflicts
        isBehindBase = pr.isBehindBase
        mergeQueuePosition = pr.mergeQueuePosition
        self.since = since
    }

    var id: String { "\(repo)#\(number)" }

    /// A new head commit alone: CI starts over on it and the review may be dismissed, none of it news.
    /// Entering the merge queue is the user's own doing too (the mark is usually taken just before). In
    /// both cases the caller takes a fresh mark and keeps watching.
    func needsRebase(for pr: PullRequest) -> Bool {
        pr.headRefOid != headRefOid || (mergeQueuePosition == nil && pr.mergeQueuePosition != nil)
    }

    /// The one thing to say about `pr` compared to the mark, worst news first; nil when nothing that
    /// matters changed. On a new head nothing is judged (see `needsRebase`).
    func movement(for pr: PullRequest) -> WatchMovement? {
        guard !needsRebase(for: pr) else { return nil }
        if pr.ciState == .failure, ciState != .failure { return .checksFailed }
        if pr.hasConflicts, !hasConflicts { return .conflicts }
        if pr.reviewDecision == .changesRequested, reviewDecision != .changesRequested { return .changesRequested }
        if pr.reviewDecision == .approved, reviewDecision != .approved { return .approved }
        if pr.ciState == .success, ciState != .success { return .checksPassed }
        if pr.isBehindBase, !isBehindBase { return .behindBase }
        if let position = pr.mergeQueuePosition, position != mergeQueuePosition { return .queuePosition(position) }
        return nil
    }
}
