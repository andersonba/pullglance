import Foundation

enum GHOutcome: Sendable, Equatable {
    case success(Data)
    case ghNotFound
    case notAuthenticated
    case failure(String)
}

protocol GHRunning: Sendable {
    /// `includeMergeState` asks for `mergeable`/`mergeStateStatus`, which GitHub computes on demand and
    /// refuses for large pages ("Resource limits for this query exceeded"). Only your own PRs need it.
    func search(_ query: String, includeMergeState: Bool) async -> GHOutcome
    /// Repository search with a full search string (`repo-search.graphql`).
    func searchRepos(query: String) async -> GHOutcome
    /// `gh pr merge`. `matchHeadCommit` makes GitHub refuse if the branch moved since the PR was shown.
    func merge(url: URL, method: MergeMethod, deleteBranch: Bool, matchHeadCommit: String?) async -> GHOutcome
    /// `gh pr comment`.
    func comment(url: URL, body: String) async -> GHOutcome
}
