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
    /// `first` is the page size: 100 for the lists, fewer for the team sample, where it is most of the cost.
    func search(_ query: String, includeMergeState: Bool, first: Int) async -> GHOutcome
    /// Repository search with a full search string (`repo-search.graphql`).
    func searchRepos(query: String) async -> GHOutcome
    /// `gh pr merge`. `matchHeadCommit` makes GitHub refuse if the branch moved since the PR was shown.
    func merge(url: URL, method: MergeMethod, deleteBranch: Bool, matchHeadCommit: String?) async -> GHOutcome
    /// `gh pr comment`.
    func comment(url: URL, body: String) async -> GHOutcome
    /// `gh pr list --base`: the open pull requests stacked on a branch. JSON array of `{number}`.
    func openPullRequests(repo: String, base: String) async -> GHOutcome
    /// `pull-request.graphql`: one pull request by repository and number.
    func pullRequest(owner: String, name: String, number: Int, includeMergeState: Bool) async -> GHOutcome
    /// `gh --version`, for the diagnostics summary.
    func version() async -> GHOutcome
    /// `gh auth status`; success means logged in. Output is never stored.
    func authStatus() async -> GHOutcome
}

extension GHRunning {
    func version() async -> GHOutcome { .failure("unavailable") }
    func authStatus() async -> GHOutcome { .failure("unavailable") }
}
