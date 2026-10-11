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

    var id: String { "\(repo)#\(number)" }
    var checksURL: URL { url.appendingPathComponent("checks") }
    var repoName: String { repo.split(separator: "/").last.map(String.init) ?? repo }
    var ownerLogin: String { repo.split(separator: "/").first.map(String.init) ?? repo }
}
