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
    case snooze
    case open
    case copyLink
    /// Only offered on a row whose last action failed: clears the failure and fetches again.
    case refresh
}

/// The two buttons revealed by a swipe, per section. Merge only where merging is the point.
func quickActions(for section: Section, dormant: Bool = false) -> [PRAction] {
    if dormant { return [.snooze, .open] }
    return section == .readyToMerge ? [.merge, .comment] : [.open, .comment]
}

/// The full context menu, per section.
func allActions(for section: Section, dormant: Bool = false) -> [PRAction] {
    let merge: [PRAction] = section == .readyToMerge ? [.merge] : []
    return dormant ? [.snooze] + merge + [.comment, .open, .copyLink] : merge + [.comment, .snooze, .open, .copyLink]
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
    case closed
    case notAllowed
    case other(String)

    init(ghMessage: String) {
        let m = ghMessage.lowercased()
        if m.contains("already merged") { self = .alreadyMerged }
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

    init(headRefOid: String, reviewDecision: ReviewDecision?, ciState: CIState) {
        self.headRefOid = headRefOid
        self.reviewDecision = reviewDecision
        self.ciState = ciState
    }

    init(_ pr: PullRequest) {
        self.init(headRefOid: pr.headRefOid, reviewDecision: pr.reviewDecision, ciState: pr.ciState)
    }

    func shouldWake(for pr: PullRequest) -> Bool {
        pr.headRefOid != headRefOid || pr.reviewDecision != reviewDecision || pr.ciState != ciState
    }
}
