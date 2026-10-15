import Foundation

enum ReviewDecision: String, Sendable, Equatable, Codable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
}

enum CIState: String, Sendable, Equatable, Codable {
    case success
    case failure
    case pending
    case none
}

struct PullRequest: Sendable, Equatable, Identifiable {
    let repo: String
    let number: Int
    let title: String
    let url: URL
    let isDraft: Bool
    let author: String
    let updatedAt: Date
    let reviewDecision: ReviewDecision?
    let ciState: CIState
    let unresolvedThreads: Int
    /// The files the unresolved threads sit on, each once, in the order GitHub lists the threads.
    let unresolvedThreadPaths: [String]
    let requestedTeams: [String]
    /// `mergeable == CONFLICTING`
    let hasConflicts: Bool
    /// `mergeStateStatus == BEHIND`
    let isBehindBase: Bool
    /// GitHub avatar of the author; nil for deleted users or when the field is missing.
    let authorAvatarURL: URL?
    let baseRefName: String
    let headRefName: String
    /// Last commit on the PR branch. Passed to `gh pr merge --match-head-commit`, and the first thing that
    /// wakes a snoozed PR.
    let headRefOid: String
    let mergeOptions: MergeOptions
    /// GraphQL node id, needed by mutations that do not take a URL (`enqueuePullRequest`). Empty when the
    /// list was fetched without merge fields.
    let nodeID: String
    /// Whether the merge fields were fetched at all. Review requests are listed without them, so for those
    /// `usesMergeQueue` and friends are "unknown", not "no".
    let hasMergeState: Bool
    /// The base branch requires a merge queue: a strategy is refused and the queue merges when it decides.
    let usesMergeQueue: Bool
    /// 1-based place in that queue once added; nil until then.
    let mergeQueuePosition: Int?
    /// The strategy the queue is configured with, when there is one.
    let queueMergeMethod: MergeMethod?
    /// `mergeStateStatus == BLOCKED`: requirements (checks, reviews) still unmet, so no merge right now.
    let isBlocked: Bool
    /// GitHub's `viewerCanEnableAutoMerge`: the repository allows it and this user may ask for it.
    let canEnableAutoMerge: Bool
    /// Auto-merge is already on, with this strategy; nil otherwise.
    let autoMergeMethod: MergeMethod?
    /// The review signals (see `reviewSignal(for:now:)`). `createdAt` falls back to `updatedAt` when absent.
    let createdAt: Date
    /// GitHub's `isReadByViewer`: false means activity you have not looked at yet. True when unknown.
    let isReadByViewer: Bool
    /// Size of the diff; nil when the list did not carry it (unknown is not small).
    let changedFiles: Int?
    let additions: Int?
    let deletions: Int?
    var linesChanged: Int? { additions.map { $0 + (deletions ?? 0) } }
    /// You reviewed this pull request before (`viewerLatestReview` exists).
    let viewerReviewedBefore: Bool
    /// You are asked right now (`viewerLatestReviewRequest` exists); with the above, a re-review.
    let viewerRequested: Bool

    /// Where GitHub itself shows "Enable auto-merge": the viewer may, nothing is scheduled yet, and the PR
    /// cannot merge right now. A queue base takes the queue path instead; unknown merge state is not a yes.
    var offersAutoMerge: Bool {
        hasMergeState && !usesMergeQueue && canEnableAutoMerge && isBlocked && autoMergeMethod == nil
    }

    var id: String { "\(repo)#\(number)" }
    var checksURL: URL { url.appendingPathComponent("checks") }
    var repoName: String { repo.split(separator: "/").last.map(String.init) ?? repo }
    var ownerLogin: String { repo.split(separator: "/").first.map(String.init) ?? repo }
}
