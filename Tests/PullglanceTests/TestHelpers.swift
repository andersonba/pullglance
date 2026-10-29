import Foundation
import Testing
@testable import Pullglance

func fixture(_ name: String) throws -> Data {
    /// `name` is the full file name, e.g. "search-mine.json".
    let base = try #require(Bundle.module.resourceURL)
    return try Data(contentsOf: base.appendingPathComponent("Fixtures/\(name)"))
}

func makePR(
    repo: String = "acme/web",
    number: Int = 1,
    title: String = "A pull request",
    isDraft: Bool = false,
    author: String = "octocat",
    updatedAt: Date = Date(timeIntervalSince1970: 1_790_000_000),
    reviewDecision: ReviewDecision? = nil,
    ciState: CIState = .none,
    unresolvedThreads: Int = 0,
    unresolvedThreadPaths: [String] = [],
    requestedTeams: [String] = [],
    hasConflicts: Bool = false,
    isBehindBase: Bool = false,
    authorAvatarURL: URL? = nil,
    headRefOid: String = "abc1234",
    mergeOptions: MergeOptions = MergeOptions(allowed: [.squash, .merge], defaultMethod: .squash, deleteBranchOnMerge: true),
    nodeID: String = "PR_1",
    hasMergeState: Bool = true,
    usesMergeQueue: Bool = false,
    mergeQueuePosition: Int? = nil,
    queueMergeMethod: MergeMethod? = nil,
    isBlocked: Bool = false,
    canEnableAutoMerge: Bool = false,
    autoMergeMethod: MergeMethod? = nil,
    createdAt: Date? = nil,
    isReadByViewer: Bool = true,
    changedFiles: Int? = 10,
    linesChanged: Int? = 200,
    additions: Int? = nil,
    deletions: Int? = nil,
    viewerReviewedBefore: Bool = false,
    viewerRequested: Bool = true
) -> PullRequest {
    PullRequest(
        repo: repo, number: number, title: title,
        url: URL(string: "https://github.com/\(repo)/pull/\(number)")!,
        isDraft: isDraft, author: author, updatedAt: updatedAt,
        reviewDecision: reviewDecision, ciState: ciState,
        unresolvedThreads: unresolvedThreads, unresolvedThreadPaths: unresolvedThreadPaths, requestedTeams: requestedTeams,
        hasConflicts: hasConflicts, isBehindBase: isBehindBase,
        authorAvatarURL: authorAvatarURL,
        baseRefName: "main", headRefName: "feature", headRefOid: headRefOid,
        mergeOptions: mergeOptions,
        nodeID: nodeID, hasMergeState: hasMergeState, usesMergeQueue: usesMergeQueue,
        mergeQueuePosition: mergeQueuePosition, queueMergeMethod: queueMergeMethod,
        isBlocked: isBlocked, canEnableAutoMerge: canEnableAutoMerge, autoMergeMethod: autoMergeMethod,
        createdAt: createdAt ?? updatedAt, isReadByViewer: isReadByViewer, changedFiles: changedFiles,
        additions: additions ?? linesChanged, deletions: additions == nil ? (linesChanged == nil ? nil : 0) : deletions,
        viewerReviewedBefore: viewerReviewedBefore, viewerRequested: viewerRequested
    )
}

/// Builds a minimal GraphQL envelope around hand-written PR nodes.
/// `envelope` for nodes that are already JSON objects (a fixture's node reused next to a built one).
func envelopeFrom(nodes: [Any], issueCount: Int) -> Data {
    let strings = nodes.map { String(data: try! JSONSerialization.data(withJSONObject: $0), encoding: .utf8)! }
    return envelope(nodes: strings, issueCount: issueCount)
}

func envelope(nodes: [String], issueCount: Int? = nil, viewer: String = "octocat") -> Data {
    let body = """
    {"data":{"viewer":{"login":"\(viewer)"},"search":{"issueCount":\(issueCount ?? nodes.count),"nodes":[\(nodes.joined(separator: ","))]}}}
    """
    return Data(body.utf8)
}

/// One `pull-request.graphql` response around a node from `node(...)`, or a null pull request.
func pullRequestEnvelope(_ node: String?, state: String = "OPEN") -> Data {
    let body = node.map { "{\"state\":\"" + state + "\"," + $0.dropFirst() } ?? "null"
    return Data(("{\"data\":{\"repository\":{\"pullRequest\":" + body + "}}}").utf8)
}

/// `mergeable: nil` writes a null, as a list fetched without merge fields decodes.
func node(number: Int, ci: String?, decision: String? = nil, draft: Bool = false, mergeable: String? = "MERGEABLE", mergeState: String = "CLEAN", updatedAt: String = "2026-10-10T10:00:00Z", author: String = "someone", headRefOid: String = "abc1234", repo: String = "acme/web", repoExtra: String = "\"mergeCommitAllowed\":false,\"squashMergeAllowed\":true,\"rebaseMergeAllowed\":false,\"deleteBranchOnMerge\":true,\"viewerDefaultMergeMethod\":\"SQUASH\"", prExtra: String = "") -> String {
    let rollup = ci.map { "{\"state\":\"\($0)\"}" } ?? "null"
    let dec = decision.map { "\"\($0)\"" } ?? "null"
    let extra = prExtra.isEmpty ? "" : prExtra + ","
    let mergeableJSON = mergeable.map { "\"\($0)\"" } ?? "null"
    return """
    {\(extra)"number":\(number),"title":"PR \(number)","url":"https://github.com/\(repo)/pull/\(number)","isDraft":\(draft),"mergeable":\(mergeableJSON),"mergeStateStatus":"\(mergeState)","baseRefName":"main","headRefName":"feature-\(number)","headRefOid":"\(headRefOid)","updatedAt":"\(updatedAt)","repository":{"nameWithOwner":"\(repo)",\(repoExtra)},"author":{"login":"\(author)","avatarUrl":"https://example.com/\(author).png"},"reviewDecision":\(dec),"reviewThreads":{"nodes":[]},"reviewRequests":{"nodes":[]},"commits":{"nodes":[{"commit":{"statusCheckRollup":\(rollup)}}]}}
    """
}

/// The `stackEntry` object as GitHub returns it, for `node(..., prExtra:)`. `members`: (position, number, title,
/// state, isDraft). No trailing comma; `node` adds it.
func stackEntryJSON(number: Int = 7, size: Int, position: Int, base: String = "main", members: [(Int, Int, String, String, Bool)]) -> String {
    let nodes = members.map { "{\"position\":\($0.0),\"pullRequest\":{\"number\":\($0.1),\"title\":\"\($0.2)\",\"state\":\"\($0.3)\",\"isDraft\":\($0.4)}}" }.joined(separator: ",")
    return "\"stackEntry\":{\"position\":\(position),\"stack\":{\"number\":\(number),\"size\":\(size),\"baseRefName\":\"\(base)\",\"entries\":{\"nodes\":[\(nodes)]}}}"
}

/// Scripted GHRunning. Outcomes are keyed by the full query string.
actor FakeGH: GHRunning {
    private var outcomes: [String: GHOutcome] = [:]
    private var delay: Duration = .zero
    private(set) var calls: [String] = []
    private(set) var mergeFlags: [String: Bool] = [:]
    private(set) var pageSizes: [String: Int] = [:]
    private var repoSearches: [String: GHOutcome] = [:]
    private var mergeOutcome: GHOutcome = .success(Data())
    private var commentOutcome: GHOutcome = .success(Data())
    private(set) var merges: [(url: URL, method: MergeMethod, deleteBranch: Bool, matchHeadCommit: String?)] = []
    private(set) var comments: [(url: URL, body: String)] = []
    private var approveOutcome: GHOutcome = .success(Data())
    private(set) var approvals: [(url: URL, body: String?)] = []
    private var autoMergeOutcome: GHOutcome = .success(Data("{\"data\":{\"enablePullRequestAutoMerge\":{\"clientMutationId\":null}}}".utf8))
    private(set) var autoMergeEnables: [(id: String, method: MergeMethod, oid: String)] = []
    private(set) var autoMergeDisables: [String] = []
    func setAutoMergeOutcome(_ outcome: GHOutcome) { autoMergeOutcome = outcome }
    func enableAutoMerge(pullRequestID: String, method: MergeMethod, expectedHeadOid: String) async -> GHOutcome {
        autoMergeEnables.append((pullRequestID, method, expectedHeadOid))
        return autoMergeOutcome
    }
    func disableAutoMerge(pullRequestID: String) async -> GHOutcome {
        autoMergeDisables.append(pullRequestID)
        return .success(Data("{\"data\":{\"disablePullRequestAutoMerge\":{\"clientMutationId\":null}}}".utf8))
    }
    private var enqueueOutcome: GHOutcome = .success(Data("{\"data\":{\"enqueuePullRequest\":{\"mergeQueueEntry\":null}}}".utf8))
    private(set) var enqueues: [(id: String, oid: String)] = []
    func setEnqueueOutcome(_ outcome: GHOutcome) { enqueueOutcome = outcome }
    func enqueue(pullRequestID: String, expectedHeadOid: String) async -> GHOutcome {
        enqueues.append((pullRequestID, expectedHeadOid))
        if delay > .zero { try? await Task.sleep(for: delay) }
        return enqueueOutcome
    }
    private var pullRequestOutcomes: [Int: GHOutcome] = [:]
    private(set) var lookups: [(owner: String, name: String, number: Int, includeMergeState: Bool)] = []
    func setPullRequest(_ outcome: GHOutcome, number: Int) { pullRequestOutcomes[number] = outcome }
    func pullRequest(owner: String, name: String, number: Int, includeMergeState: Bool) async -> GHOutcome {
        lookups.append((owner, name, number, includeMergeState))
        if delay > .zero { try? await Task.sleep(for: delay) }
        return pullRequestOutcomes[number] ?? .failure("no scripted pull request \(number)")
    }

    private var pullRequestsOutcome: GHOutcome = .failure("no scripted batch lookup")
    private(set) var batchLookups: [[PullRequestRef]] = []
    func setPullRequests(_ outcome: GHOutcome) { pullRequestsOutcome = outcome }
    func pullRequests(_ refs: [PullRequestRef], includeMergeState: Bool) async -> GHOutcome {
        batchLookups.append(refs)
        if delay > .zero { try? await Task.sleep(for: delay) }
        return pullRequestsOutcome
    }

    private var fileOutcomes: [GHOutcome] = []
    private(set) var fileLookups: [(number: Int, after: String?)] = []
    func setPullRequestFiles(_ outcomes: [GHOutcome]) { fileOutcomes = outcomes }
    /// When set, file lookups suspend (already recorded) until `releaseFileLookups()`.
    private var holdingFiles = false
    private var heldFiles: [CheckedContinuation<Void, Never>] = []
    func holdFileLookups() { holdingFiles = true }
    func releaseFileLookups() { holdingFiles = false; let waiting = heldFiles; heldFiles = []; waiting.forEach { $0.resume() } }
    func pullRequestFiles(owner: String, name: String, number: Int, after: String?) async -> GHOutcome {
        fileLookups.append((number, after))
        if holdingFiles { await withCheckedContinuation { heldFiles.append($0) } }
        return fileOutcomes.isEmpty ? .failure("no scripted files page") : fileOutcomes.removeFirst()
    }

    private var openPullRequestsOutcome: GHOutcome = .success(Data("[]".utf8))
    private(set) var dependentQueries: [(repo: String, base: String)] = []

    func setOpenPullRequests(_ outcome: GHOutcome) { openPullRequestsOutcome = outcome }
    func openPullRequests(repo: String, base: String) async -> GHOutcome {
        dependentQueries.append((repo, base))
        return openPullRequestsOutcome
    }

    func setRepoSearch(_ outcome: GHOutcome, for query: String) { repoSearches[query] = outcome }
    func setMergeOutcome(_ outcome: GHOutcome) { mergeOutcome = outcome }
    func setCommentOutcome(_ outcome: GHOutcome) { commentOutcome = outcome }
    func setApproveOutcome(_ outcome: GHOutcome) { approveOutcome = outcome }

    private(set) var readied: [URL] = []
    private var readyOutcome: GHOutcome = .success(Data())
    func setReadyOutcome(_ outcome: GHOutcome) { readyOutcome = outcome }
    func markReady(url: URL) async -> GHOutcome {
        readied.append(url)
        return readyOutcome
    }

    func merge(url: URL, method: MergeMethod, deleteBranch: Bool, matchHeadCommit: String?) async -> GHOutcome {
        merges.append((url, method, deleteBranch, matchHeadCommit))
        if delay > .zero { try? await Task.sleep(for: delay) }
        return mergeOutcome
    }

    func comment(url: URL, body: String) async -> GHOutcome {
        comments.append((url, body))
        if delay > .zero { try? await Task.sleep(for: delay) }
        return commentOutcome
    }

    func approve(url: URL, body: String?) async -> GHOutcome {
        approvals.append((url, body))
        return approveOutcome
    }

    func searchRepos(query: String) async -> GHOutcome {
        repoSearches[query] ?? .failure("no scripted repo search for \(query)")
    }

    func set(_ outcome: GHOutcome, for query: String) { outcomes[query] = outcome }
    func setDelay(_ value: Duration) { delay = value }
    func callCount(for query: String) -> Int { calls.filter { $0 == query }.count }

    func search(_ query: String, includeMergeState: Bool, first: Int) async -> GHOutcome {
        calls.append(query)
        mergeFlags[query] = includeMergeState
        pageSizes[query] = first
        if delay > .zero { try? await Task.sleep(for: delay) }
        return outcomes[query] ?? .failure("no scripted outcome for \(query)")
    }
}

/// Polls `condition` until it holds or `timeout` passes; returns whether it held. For work the store starts
/// on its own (a refresh after a setting changed, a lazy load, a timer): a fixed sleep is either too long or,
/// under a loaded machine, too short.
@MainActor
func waitUntil(timeout: Duration = .seconds(3), _ condition: @MainActor () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}

func testDefaults() -> UserDefaults {
    let suite = "PullglanceTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

/// A clock the tests move by hand, for stores built with `now:`.
final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(start: Date = Date(timeIntervalSince1970: 1_000_000)) { date = start }
    var now: Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }
}

final class FakeSnoozeNotifier: SnoozeNotifying, @unchecked Sendable {
    private(set) var counts: [Int] = []
    private(set) var moves: [(mark: WatchMark, movement: WatchMovement)] = []
    func snoozeEnded(count: Int) { counts.append(count) }
    func pullRequestMoved(_ mark: WatchMark, _ movement: WatchMovement) { moves.append((mark, movement)) }
}
