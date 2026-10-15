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
    /// `enqueue.graphql`: adds the pull request to its base branch's merge queue. The queue merges with the
    /// strategy it is configured with; `expectedHeadOid` plays the part of `--match-head-commit`.
    func enqueue(pullRequestID: String, expectedHeadOid: String) async -> GHOutcome
    /// `enable-auto-merge.graphql`: GitHub merges with `method` once the requirements pass, by itself.
    func enableAutoMerge(pullRequestID: String, method: MergeMethod, expectedHeadOid: String) async -> GHOutcome
    /// `disable-auto-merge.graphql`.
    func disableAutoMerge(pullRequestID: String) async -> GHOutcome
    /// `gh pr comment`.
    func comment(url: URL, body: String) async -> GHOutcome
    /// `gh pr ready`: a draft becomes ready for review.
    func markReady(url: URL) async -> GHOutcome
    /// `gh pr review --approve`, with an optional comment.
    func approve(url: URL, body: String?) async -> GHOutcome
    /// `gh pr list --base`: the open pull requests stacked on a branch. JSON array of `{number}`.
    func openPullRequests(repo: String, base: String) async -> GHOutcome
    /// `pull-request.graphql`: one pull request by repository and number.
    func pullRequest(owner: String, name: String, number: Int, includeMergeState: Bool) async -> GHOutcome
    /// Several pull requests in one request, aliased `p0`, `p1`, … in the order given. The search index
    /// GitHub serves lists from lags the repository by minutes; this is the authoritative read.
    func pullRequests(_ refs: [PullRequestRef], includeMergeState: Bool) async -> GHOutcome
    /// `pull-request-files.graphql`: one page (100) of changed files with the viewer's viewed state.
    func pullRequestFiles(owner: String, name: String, number: Int, after: String?) async -> GHOutcome
    /// `gh --version`, for the diagnostics summary.
    func version() async -> GHOutcome
    /// `gh auth status`; success means logged in. Output is never stored.
    func authStatus() async -> GHOutcome
}

extension GHRunning {
    func version() async -> GHOutcome { .failure("unavailable") }
    func authStatus() async -> GHOutcome { .failure("unavailable") }
}

/// Repository and number of a pull request, as the batch lookup needs them. Names are restricted to the
/// characters GitHub allows so they can be written straight into a query document.
struct PullRequestRef: Hashable, Sendable {
    let owner: String
    let name: String
    let number: Int

    init(owner: String, name: String, number: Int) {
        self.owner = owner
        self.name = name
        self.number = number
    }

    /// From `owner/name`; nil when the name is not a plain GitHub name.
    init?(repo: String, number: Int) {
        let parts = repo.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, parts.allSatisfy(Self.isPlainName) else { return nil }
        self.init(owner: parts[0], name: parts[1], number: number)
    }

    private static func isPlainName(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0) }
    }
}
