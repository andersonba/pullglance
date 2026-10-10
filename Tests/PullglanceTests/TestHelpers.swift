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
    requestedTeams: [String] = []
) -> PullRequest {
    PullRequest(
        repo: repo, number: number, title: title,
        url: URL(string: "https://github.com/\(repo)/pull/\(number)")!,
        isDraft: isDraft, author: author, updatedAt: updatedAt,
        reviewDecision: reviewDecision, ciState: ciState,
        unresolvedThreads: unresolvedThreads, requestedTeams: requestedTeams
    )
}

/// Builds a minimal GraphQL envelope around hand-written PR nodes.
func envelope(nodes: [String], issueCount: Int? = nil, viewer: String = "octocat") -> Data {
    let body = """
    {"data":{"viewer":{"login":"\(viewer)"},"search":{"issueCount":\(issueCount ?? nodes.count),"nodes":[\(nodes.joined(separator: ","))]}}}
    """
    return Data(body.utf8)
}

func node(number: Int, ci: String?, decision: String? = nil, draft: Bool = false) -> String {
    let rollup = ci.map { "{\"state\":\"\($0)\"}" } ?? "null"
    let dec = decision.map { "\"\($0)\"" } ?? "null"
    return """
    {"number":\(number),"title":"PR \(number)","url":"https://github.com/acme/web/pull/\(number)","isDraft":\(draft),"updatedAt":"2026-10-10T10:00:00Z","repository":{"nameWithOwner":"acme/web"},"author":{"login":"someone"},"reviewDecision":\(dec),"reviewThreads":{"nodes":[]},"reviewRequests":{"nodes":[]},"commits":{"nodes":[{"commit":{"statusCheckRollup":\(rollup)}}]}}
    """
}

/// Scripted GHRunning. Outcomes are keyed by the full query string.
actor FakeGH: GHRunning {
    private var outcomes: [String: GHOutcome] = [:]
    private var delay: Duration = .zero
    private(set) var calls: [String] = []

    func set(_ outcome: GHOutcome, for query: String) { outcomes[query] = outcome }
    func setDelay(_ value: Duration) { delay = value }
    func callCount(for query: String) -> Int { calls.filter { $0 == query }.count }

    func search(_ query: String) async -> GHOutcome {
        calls.append(query)
        if delay > .zero { try? await Task.sleep(for: delay) }
        return outcomes[query] ?? .failure("no scripted outcome for \(query)")
    }
}

func testDefaults() -> UserDefaults {
    let suite = "PullglanceTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}
