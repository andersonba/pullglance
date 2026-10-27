import Foundation

enum MergeMethod: String, CaseIterable, Sendable, Equatable, Codable {
    case merge
    case squash
    case rebase

    var ghFlag: String {
        switch self {
        case .merge: "--merge"
        case .squash: "--squash"
        case .rebase: "--rebase"
        }
    }

    init?(apiValue: String) {
        switch apiValue {
        case "MERGE": self = .merge
        case "SQUASH": self = .squash
        case "REBASE": self = .rebase
        default: return nil
        }
    }

    /// GraphQL `PullRequestMergeMethod`.
    var apiValue: String { rawValue.uppercased() }
}

/// What the repository allows, and what GitHub would pick for this user.
struct MergeOptions: Equatable, Sendable {
    let allowed: Set<MergeMethod>
    let defaultMethod: MergeMethod
    let deleteBranchOnMerge: Bool

    /// The default, unless the repository forbids it; then the first allowed in merge/squash/rebase order.
    var preselected: MergeMethod {
        if allowed.contains(defaultMethod) { return defaultMethod }
        return MergeMethod.allCases.first { allowed.contains($0) } ?? defaultMethod
    }

    static let permissive = MergeOptions(allowed: Set(MergeMethod.allCases), defaultMethod: .merge, deleteBranchOnMerge: false)
}

enum PRAction: Equatable, Sendable {
    case merge
    case comment
    /// Offered by the review window only; rows never list it.
    case approve
    case snooze
    case open
    case copyLink
    /// Only offered on a row whose last action failed: clears the failure and fetches again.
    case refresh
    /// Only on a row with auto-merge on: GitHub's "Disable auto-merge".
    case disableAutoMerge
    /// Pin to the top of the tab, or unpin when already there.
    case pin
    /// Watch for movement (a notification), or stop watching.
    case watch
    /// `gh pr ready`: only on the viewer's own drafts.
    case markReady
}

/// The two buttons revealed by a swipe, per section. Merge only where merging is the point. Review rows
/// open the review window on a click, so their first tile is Pin rather than Open.
func quickActions(for section: Section, dormant: Bool = false) -> [PRAction] {
    if dormant { return [.snooze, .open] }
    switch section {
    case .drafts: return [.markReady, .comment]
    case .readyToMerge: return [.merge, .comment]
    case .needsYourReview, .needsTeamsReview: return [.pin, .comment]
    default: return [.open, .comment]
    }
}

/// The full context menu, per section. `offersMerge` is "Merge when checks pass" outside Ready to merge;
/// `autoMergeOn` replaces Merge with the way to call it off.
func allActions(for section: Section, dormant: Bool = false, offersMerge: Bool = false, autoMergeOn: Bool = false) -> [PRAction] {
    // A draft merges nowhere and takes no auto-merge: its one action is to be marked ready.
    let merge: [PRAction] = section == .drafts ? [.markReady] : autoMergeOn ? [.disableAutoMerge] : (section == .readyToMerge || offersMerge) ? [.merge] : []
    return (dormant ? [.snooze, .pin, .watch] + merge + [.comment, .open, .copyLink] : [.pin, .watch] + merge + [.comment, .snooze, .open, .copyLink]) + [.refresh]
}

/// Why a merge did not happen, in words a person can act on. Built from `gh pr merge` output.
enum MergeFailure: Equatable, Sendable {
    case draft
    case conflicts
    case checksNotPassing
    case reviewRequired
    case changedSinceShown
    case temporarilyUnavailable
    case alreadyMerged
    case alreadyQueued
    case autoMergeOn
    case closed
    case notAllowed
    case other(String)

    init(ghMessage: String) {
        let m = ghMessage.lowercased()
        if m.contains("already merged") { self = .alreadyMerged }
        else if m.contains("already queued") || m.contains("already in the merge queue") { self = .alreadyQueued }
        else if m.contains("is closed") { self = .closed }
        else if m.contains("head branch was modified") || m.contains("head commit") { self = .changedSinceShown }
        else if m.contains("conflict") || m.contains("cannot be cleanly created") { self = .conflicts }
        else if m.contains("status check") { self = .checksNotPassing }
        else if m.contains("approving review") || m.contains("review is required") { self = .reviewRequired }
        else if m.contains("try again") { self = .temporarilyUnavailable }
        else if m.contains("not accessible") || m.contains("permission") || m.contains("protected") { self = .notAllowed }
        else { self = .other(ghMessage) }
    }
}

extension MergeFailure {
    /// A few words for the row; the modal has the full sentence.
    var shortDescription: String {
        switch self {
        case .draft: String(localized: "draft", bundle: .app)
        case .conflicts: String(localized: "conflicts", bundle: .app)
        case .checksNotPassing: String(localized: "checks not passing", bundle: .app)
        case .reviewRequired: String(localized: "review required", bundle: .app)
        case .changedSinceShown: String(localized: "branch changed", bundle: .app)
        case .temporarilyUnavailable: String(localized: "try again", bundle: .app)
        case .alreadyMerged: String(localized: "already merged", bundle: .app)
        case .alreadyQueued: String(localized: "already queued", bundle: .app)
        case .autoMergeOn: String(localized: "auto-merge on", bundle: .app)
        case .closed: String(localized: "closed", bundle: .app)
        case .notAllowed: String(localized: "not allowed", bundle: .app)
        case .other(let message): message
        }
    }
}

/// What we already know would make GitHub refuse, so the modal can say so before trying.
/// Pending checks and a missing review are left to branch protection: some repositories accept them.
func mergePreflight(_ pr: PullRequest) -> MergeFailure? {
    if pr.isDraft { return .draft }
    if pr.hasConflicts { return .conflicts }
    if pr.ciState == .failure { return .checksNotPassing }
    if pr.reviewDecision == .changesRequested { return .reviewRequired }
    if pr.mergeQueuePosition != nil { return .alreadyQueued }
    if pr.autoMergeMethod != nil { return .autoMergeOn }
    return nil
}

enum ActionResult: Equatable, Sendable {
    /// `note` is something worth telling the user even though the action went through, e.g. a branch
    /// that was kept after all.
    case success(note: String? = nil)
    case failure(String)
}

extension ActionResult {
    /// One word for the log, plus the reason on failure.
    var logDescription: String {
        switch self {
        case .success: "ok"
        case .failure(let message): "failed (\(message))"
        }
    }
}

/// Number of entries in `gh pr list --json number` output; nil when it is not that.
func parseOpenPullRequestCount(_ data: Data) -> Int? {
    (try? JSONSerialization.jsonObject(with: data) as? [Any])?.count
}

/// Whether to pass `--delete-branch`. Never when the repository deletes merged branches itself: GitHub then
/// also retargets the pull requests stacked on the branch, while an explicit deletion right after the
/// merge closes them instead (cli/cli#14223).
func requestedBranchDeletion(options: MergeOptions, toggle: Bool) -> Bool {
    toggle && !options.deleteBranchOnMerge
}

/// What a row shows about an action: spinner, a brief "done", or a failure that stays until dismissed.
enum ActionState: Equatable, Sendable {
    case running(PRAction)
    case succeeded(PRAction)
    case failed(PRAction, String)
}

/// A snoozed PR, with the state it had when snoozed. It wakes up when something that asks for action changes:
/// a new commit, a review decision, or the CI state. Comments alone do not wake it. Kept deliberately simple
/// so the rule is easy to revisit.
struct DormantMark: Equatable, Sendable, Codable {
    let headRefOid: String
    let reviewDecision: ReviewDecision?
    let ciState: CIState
    /// When the snooze ends by itself; nil sleeps until activity alone.
    let until: Date?

    init(headRefOid: String, reviewDecision: ReviewDecision?, ciState: CIState, until: Date? = nil) {
        self.headRefOid = headRefOid
        self.reviewDecision = reviewDecision
        self.ciState = ciState
        self.until = until
    }

    init(_ pr: PullRequest, until: Date? = nil) {
        self.init(headRefOid: pr.headRefOid, reviewDecision: pr.reviewDecision, ciState: pr.ciState, until: until)
    }

    // Marks saved before timed snoozes have no `until`.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        headRefOid = try container.decode(String.self, forKey: .headRefOid)
        reviewDecision = try container.decodeIfPresent(ReviewDecision.self, forKey: .reviewDecision)
        ciState = try container.decode(CIState.self, forKey: .ciState)
        until = try container.decodeIfPresent(Date.self, forKey: .until)
    }

    /// Activity on the PR, or the hour come: either ends the snooze.
    func shouldWake(for pr: PullRequest, now: Date = Date()) -> Bool {
        pr.headRefOid != headRefOid || pr.reviewDecision != reviewDecision || pr.ciState != ciState || until.map { now >= $0 } == true
    }

    /// Time left on a timed snooze, never negative; nil for one that waits on activity.
    func remaining(now: Date = Date()) -> Duration? {
        until.map { .seconds(max(0, $0.timeIntervalSince(now))) }
    }

    /// The menu item that stands for this snooze: the shortest length still covering what is left, nil for
    /// one that waits on activity.
    func nearestLength(now: Date = Date()) -> SnoozeDuration? {
        guard let left = remaining(now: now) else { return nil }
        return SnoozeDuration.allCases.first { .seconds($0.interval) >= left } ?? .oneWeek
    }
}

/// Told when timed snoozes end and when a watched pull request moves, so the user can hear about it away
/// from the popover.
protocol SnoozeNotifying: Sendable {
    func snoozeEnded(count: Int)
    func pullRequestMoved(_ mark: WatchMark, _ movement: WatchMovement)
}

/// How long a timed snooze lasts, in the order the menu offers them.
enum SnoozeDuration: String, CaseIterable, Sendable {
    case thirtyMinutes, oneHour, threeHours, oneDay, oneWeek

    var interval: TimeInterval {
        switch self {
        case .thirtyMinutes: 30 * 60
        case .oneHour: 3_600
        case .threeHours: 3 * 3_600
        case .oneDay: 24 * 3_600
        case .oneWeek: 7 * 24 * 3_600
        }
    }
}
