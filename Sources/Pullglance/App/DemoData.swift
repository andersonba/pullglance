import Foundation

/// A `GHRunning` that answers the searches with fictional pull requests, for `--snapshot --demo`: the README
/// screenshots come out of the real UI without anyone's real data, and can be regenerated when the UI moves.
struct DemoGH: GHRunning {
    private let now = Date()

    func search(_ query: String, includeMergeState: Bool, first: Int) async -> GHOutcome {
        if query.contains("author:@me") { return .success(envelope(mine, total: mine.count)) }
        if query.contains(" user-review-requested:@me") { return .success(envelope(direct, total: direct.count)) }
        return .success(envelope(team, total: team.count + 98))
    }

    func searchRepos(query: String) async -> GHOutcome { .failure("demo") }
    func merge(url: URL, method: MergeMethod, deleteBranch: Bool, matchHeadCommit: String?) async -> GHOutcome { .failure("demo") }
    func enqueue(pullRequestID: String, expectedHeadOid: String) async -> GHOutcome { .failure("demo") }
    func enableAutoMerge(pullRequestID: String, method: MergeMethod, expectedHeadOid: String) async -> GHOutcome { .failure("demo") }
    func disableAutoMerge(pullRequestID: String) async -> GHOutcome { .failure("demo") }
    func comment(url: URL, body: String) async -> GHOutcome { .failure("demo") }
    func approve(url: URL, body: String?) async -> GHOutcome { .failure("demo") }
    func openPullRequests(repo: String, base: String) async -> GHOutcome { .success(Data("[]".utf8)) }
    func pullRequest(owner: String, name: String, number: Int, includeMergeState: Bool) async -> GHOutcome { .failure("demo") }
    func pullRequests(_ refs: [PullRequestRef], includeMergeState: Bool) async -> GHOutcome { .failure("demo") }
    func pullRequestFiles(owner: String, name: String, number: Int, after: String?) async -> GHOutcome { .failure("demo") }

    // MARK: the cast

    private struct PR {
        var repo = "acme/web"
        var number: Int
        var title: String
        var author = "octocat"
        var hoursAgo: Double
        var ageDays: Double = 1
        var ci: String? = "SUCCESS"
        var decision: String? = nil
        var draft = false
        var mergeable = "MERGEABLE"
        var state = "CLEAN"
        var threads = 0
        var files = 6
        var add = 40
        var del = 12
        var read = true
        var reviewedBefore = false
        var requested = false
        var team: String? = nil
        var queuePosition: Int? = nil
    }

    private var mine: [PR] {[
        PR(number: 388, title: "Split the billing worker from the API", hoursAgo: 5 * 24, ageDays: 6, decision: "APPROVED", files: 14, add: 210, del: 96),
        PR(number: 401, title: "Keep webpack's filesystem cache out of CI", hoursAgo: 20 * 24, ageDays: 21, ci: "FAILURE", decision: "CHANGES_REQUESTED", mergeable: "CONFLICTING", state: "DIRTY", threads: 5, files: 3, add: 31, del: 4),
        PR(repo: "acme/api", number: 1042, title: "Retry webhook deliveries with jitter", hoursAgo: 3, ageDays: 0.2, ci: "PENDING", decision: "REVIEW_REQUIRED", state: "BLOCKED", files: 4, add: 88, del: 20),
        PR(number: 405, title: "Draft: redesign the settings window", hoursAgo: 26, ageDays: 2, ci: nil, draft: true, files: 22, add: 640, del: 410),
        PR(repo: "acme/web", number: 377, title: "Bump the uploader to the new SDK", hoursAgo: 2 * 24, ageDays: 3, decision: "APPROVED", files: 2, add: 12, del: 12, queuePosition: 2),
    ]}

    private var direct: [PR] {[
        PR(number: 412, title: "Fix flaky retry in the uploader", author: "alice", hoursAgo: 2, ageDays: 2, decision: "REVIEW_REQUIRED", files: 3, add: 24, del: 44, reviewedBefore: true, requested: true),
        PR(number: 431, title: "Rename the feature flag helper", author: "bob", hoursAgo: 0.7, ageDays: 0.1, decision: "REVIEW_REQUIRED", files: 2, add: 18, del: 9, read: false, requested: true),
        PR(number: 398, title: "Migrate checkout to the new payments API", author: "carol", hoursAgo: 25, ageDays: 1.5, ci: "PENDING", decision: "REVIEW_REQUIRED", threads: 3, files: 41, add: 1234, del: 380, requested: true),
        PR(repo: "globex/api", number: 77, title: "Rate limit the webhook fan-out", author: "dave", hoursAgo: 6 * 24, ageDays: 6, decision: "REVIEW_REQUIRED", files: 7, add: 96, del: 12, requested: true),
        PR(number: 419, title: "Add dark mode to the settings page", author: "frank", hoursAgo: 1.2, ageDays: 0.3, ci: "FAILURE", decision: "REVIEW_REQUIRED", files: 9, add: 300, del: 150, requested: true),
    ]}

    private var team: [PR] {[
        PR(repo: "globex/platform", number: 205, title: "Shard the events table by tenant", author: "grace", hoursAgo: 4, ageDays: 0.5, decision: "REVIEW_REQUIRED", files: 12, add: 480, del: 200, team: "platform"),
        PR(repo: "globex/platform", number: 203, title: "Tighten the retry budget on cold starts", author: "heidi", hoursAgo: 11, ageDays: 1, decision: "REVIEW_REQUIRED", files: 5, add: 60, del: 32, team: "platform"),
        PR(repo: "acme/infra", number: 88, title: "Rotate the staging certificates", author: "ivan", hoursAgo: 2 * 24, ageDays: 2, decision: "REVIEW_REQUIRED", files: 3, add: 25, del: 25, team: "infra"),
    ]}

    // MARK: JSON

    private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    private func node(_ pr: PR) -> [String: Any] {
        var repository: [String: Any] = ["nameWithOwner": pr.repo, "mergeCommitAllowed": false, "squashMergeAllowed": true, "rebaseMergeAllowed": true, "deleteBranchOnMerge": true, "viewerDefaultMergeMethod": "SQUASH"]
        repository["isPrivate"] = false
        var n: [String: Any] = [
            "id": "PR_demo\(pr.number)",
            "number": pr.number, "title": pr.title, "url": "https://github.com/\(pr.repo)/pull/\(pr.number)",
            "isDraft": pr.draft, "mergeable": pr.mergeable, "mergeStateStatus": pr.state,
            "baseRefName": "main", "headRefName": "feature/\(pr.number)", "headRefOid": String(format: "%040x", pr.number * 7919),
            "updatedAt": iso(now.addingTimeInterval(-pr.hoursAgo * 3600)), "createdAt": iso(now.addingTimeInterval(-pr.ageDays * 86_400)),
            "isReadByViewer": pr.read, "changedFiles": pr.files, "additions": pr.add, "deletions": pr.del,
            "viewerLatestReview": pr.reviewedBefore ? ["state": "CHANGES_REQUESTED"] : NSNull(),
            "viewerLatestReviewRequest": pr.requested ? ["id": "RR_\(pr.number)"] : NSNull(),
            "isMergeQueueEnabled": pr.queuePosition != nil,
            "mergeQueueEntry": pr.queuePosition.map { ["position": $0, "state": "AWAITING_CHECKS"] as [String: Any] } ?? NSNull(),
            "mergeQueue": pr.queuePosition != nil ? ["configuration": ["mergeMethod": "SQUASH"]] : NSNull(),
            "viewerCanEnableAutoMerge": false, "autoMergeRequest": NSNull(),
            "repository": repository,
            // Generated faces (DiceBear, free), seeded by the login so they are stable between renders.
            "author": ["login": pr.author, "avatarUrl": "https://api.dicebear.com/9.x/avataaars/png?seed=\(pr.author)&size=80&backgroundColor=b6e3f4,c0aede,d1d4f9,ffd5dc,ffdfbf"],
            "reviewDecision": pr.decision ?? NSNull(),
            "reviewThreads": ["nodes": Array(repeating: ["isResolved": false], count: pr.threads)],
            "reviewRequests": ["nodes": pr.team.map { [["requestedReviewer": ["__typename": "Team", "slug": $0]]] } ?? []],
            "commits": ["nodes": [["commit": ["statusCheckRollup": pr.ci.map { ["state": $0] } ?? NSNull()]]]],
        ]
        n["state"] = "OPEN"
        return n
    }

    private func envelope(_ prs: [PR], total: Int) -> Data {
        let body: [String: Any] = ["data": [
            "viewer": ["login": "octocat", "organizations": ["nodes": [["login": "acme"], ["login": "globex"]]]],
            "search": ["issueCount": total, "nodes": prs.map(node)],
        ]]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }
}
