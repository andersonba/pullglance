import Foundation
import os

struct GHClient: GHRunning {
    static let candidatePaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
    static let timeout: Duration = .seconds(30)

    /// Called on every search, so a `gh` installed after launch is picked up without restarting.
    private let locator: @Sendable () -> URL?
    private let logger = Logger(subsystem: AppInfo.bundleID, category: "gh")

    init(locator: @escaping @Sendable () -> URL? = { GHClient.locate() }) {
        self.locator = locator
    }

    /// Fixed executable, mainly for tests.
    init(executable: URL?) {
        self.init(locator: { executable })
    }

    /// Homebrew paths first: an app launched from Finder or at login does not inherit the shell's PATH.
    static func locate(
        environmentPath: String? = ProcessInfo.processInfo.environment["PATH"],
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> URL? {
        let fromPath = (environmentPath ?? "").split(separator: ":").map { "\($0)/gh" }
        return (candidatePaths + fromPath).first(where: fileExists).map { URL(fileURLWithPath: $0) }
    }

    /// Pure mapping from process output to an outcome. Exit 4 or an auth hint means "not logged in";
    /// JSON on stdout with a non-zero exit is GraphQL `errors` next to `data`, which the decoder handles.
    static func interpret(exitCode: Int32, stdout: Data, stderr: String) -> GHOutcome {
        if exitCode == 0 { return .success(stdout) }
        if exitCode == 4 || stderr.contains("gh auth login") { return .notAuthenticated }
        if stdout.first == UInt8(ascii: "{") { return .success(stdout) }
        return .failure(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static let searchQuery = document("search")
    static let repoSearchQuery = document("repo-search")
    static let pullRequestQuery = document("pull-request")
    static let enqueueMutation = document("enqueue")
    static let enableAutoMergeMutation = document("enable-auto-merge")
    static let disableAutoMergeMutation = document("disable-auto-merge")

    private static func document(_ name: String) -> String {
        guard let url = Bundle.app.url(forResource: name, withExtension: "graphql"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("\(name).graphql is missing from the resource bundle")
        }
        return text
    }

    /// `-F` sends a typed value, so `withMerge` reaches GraphQL as a Boolean.
    static func arguments(for query: String, includeMergeState: Bool, first: Int) -> [String] {
        ["api", "graphql", "-f", "query=\(searchQuery)", "-f", "q=\(query)", "-F", "withMerge=\(includeMergeState)", "-F", "first=\(first)"]
    }

    func search(_ query: String, includeMergeState: Bool, first: Int) async -> GHOutcome {
        await run(Self.arguments(for: query, includeMergeState: includeMergeState, first: first))
    }

    static func pullRequestArguments(owner: String, name: String, number: Int, includeMergeState: Bool) -> [String] {
        ["api", "graphql", "-f", "query=\(pullRequestQuery)", "-f", "owner=\(owner)", "-f", "name=\(name)", "-F", "number=\(number)", "-F", "withMerge=\(includeMergeState)"]
    }

    func pullRequest(owner: String, name: String, number: Int, includeMergeState: Bool) async -> GHOutcome {
        await run(Self.pullRequestArguments(owner: owner, name: name, number: number, includeMergeState: includeMergeState))
    }

    /// The fragment shared with `pull-request.graphql`, so both lookups decode the same way.
    static let pullRequestFragment: String = {
        guard let range = pullRequestQuery.range(of: "fragment PullRequestFields") else { fatalError("pull-request.graphql lost its fragment") }
        return String(pullRequestQuery[range.lowerBound...])
    }()

    /// One document with one aliased field per pull request. Names were validated by `PullRequestRef`.
    static func pullRequestsQuery(_ refs: [PullRequestRef]) -> String {
        let fields = refs.enumerated().map { index, ref in
            "  p\(index): repository(owner: \"\(ref.owner)\", name: \"\(ref.name)\") { pullRequest(number: \(ref.number)) { ...PullRequestFields } }"
        }
        return "query($withMerge: Boolean!) {\n" + fields.joined(separator: "\n") + "\n}\n\n" + pullRequestFragment
    }

    func pullRequests(_ refs: [PullRequestRef], includeMergeState: Bool) async -> GHOutcome {
        await run(["api", "graphql", "-f", "query=\(Self.pullRequestsQuery(refs))", "-F", "withMerge=\(includeMergeState)"])
    }

    static let pullRequestFilesQuery = document("pull-request-files")

    static func pullRequestFilesArguments(owner: String, name: String, number: Int, after: String?) -> [String] {
        var args = ["api", "graphql", "-f", "query=\(pullRequestFilesQuery)", "-f", "owner=\(owner)", "-f", "name=\(name)", "-F", "number=\(number)"]
        if let after { args += ["-f", "after=\(after)"] }
        return args
    }

    func pullRequestFiles(owner: String, name: String, number: Int, after: String?) async -> GHOutcome {
        await run(Self.pullRequestFilesArguments(owner: owner, name: name, number: number, after: after))
    }

    func searchRepos(query: String) async -> GHOutcome {
        await run(["api", "graphql", "-f", "query=\(Self.repoSearchQuery)", "-f", "q=\(query)"])
    }

    static func mergeArguments(url: URL, method: MergeMethod, deleteBranch: Bool, matchHeadCommit: String?) -> [String] {
        var args = ["pr", "merge", url.absoluteString, method.ghFlag]
        if deleteBranch { args.append("--delete-branch") }
        if let matchHeadCommit, !matchHeadCommit.isEmpty { args += ["--match-head-commit", matchHeadCommit] }
        return args
    }

    static func enqueueArguments(pullRequestID: String, expectedHeadOid: String) -> [String] {
        ["api", "graphql", "-f", "query=\(enqueueMutation)", "-f", "id=\(pullRequestID)", "-f", "oid=\(expectedHeadOid)"]
    }

    static func enableAutoMergeArguments(pullRequestID: String, method: MergeMethod, expectedHeadOid: String) -> [String] {
        ["api", "graphql", "-f", "query=\(enableAutoMergeMutation)", "-f", "id=\(pullRequestID)", "-f", "method=\(method.apiValue)", "-f", "oid=\(expectedHeadOid)"]
    }

    static func disableAutoMergeArguments(pullRequestID: String) -> [String] {
        ["api", "graphql", "-f", "query=\(disableAutoMergeMutation)", "-f", "id=\(pullRequestID)"]
    }

    static func commentArguments(url: URL, body: String) -> [String] {
        ["pr", "comment", url.absoluteString, "--body", body]
    }

    static func approveArguments(url: URL, body: String?) -> [String] {
        var args = ["pr", "review", url.absoluteString, "--approve"]
        if let body, !body.isEmpty { args += ["--body", body] }
        return args
    }

    static func openPullRequestsArguments(repo: String, base: String) -> [String] {
        ["pr", "list", "--repo", repo, "--base", base, "--state", "open", "--json", "number", "--limit", "100"]
    }

    func openPullRequests(repo: String, base: String) async -> GHOutcome {
        await run(Self.openPullRequestsArguments(repo: repo, base: base))
    }

    func version() async -> GHOutcome { await run(["--version"]) }
    func authStatus() async -> GHOutcome { await run(["auth", "status"]) }

    /// What `gh auth status` says about github.com's active account, and nothing else: a second host or
    /// account in trouble makes the plain command exit 1, which must not read as "not logged in".
    enum AuthStatus: Equatable, Sendable {
        case loggedIn(login: String?)
        case loggedOut
        /// gh could not verify the token: offline, or the token expired. Not the same as logged out.
        case unverifiable(String)
        case failed(String)
    }

    /// `--json hosts` carries a `state` per account; the text form before it (older gh) is parsed as a
    /// fallback, where an exit 1 cannot tell an expired token from a logged-out gh.
    func checkAuth(host: String = "github.com") async -> AuthStatus {
        let json = await run(["auth", "status", "--hostname", host, "--active", "--json", "hosts"])
        switch json {
        case .success(let data):
            return Self.interpretAuthStatus(json: data, host: host) ?? Self.interpretAuthStatus(text: json)
        case .failure(let message) where message.contains("unknown flag"):
            return Self.interpretAuthStatus(text: await run(["auth", "status", "--hostname", host]))
        default:
            return Self.interpretAuthStatus(text: json)
        }
    }

    private struct AuthHosts: Decodable {
        struct Entry: Decodable {
            let state: String
            let active: Bool?
            let login: String?
            let error: String?
        }
        let hosts: [String: [Entry]]
    }

    static func interpretAuthStatus(json: Data, host: String = "github.com") -> AuthStatus? {
        guard let decoded = try? JSONDecoder().decode(AuthHosts.self, from: json) else { return nil }
        let entries = decoded.hosts[host] ?? []
        guard let entry = entries.first(where: { $0.active == true }) ?? entries.first else { return .loggedOut }
        switch entry.state {
        case "success": return .loggedIn(login: entry.login)
        default: return .unverifiable(entry.error ?? entry.state)
        }
    }

    static func interpretAuthStatus(text outcome: GHOutcome) -> AuthStatus {
        switch outcome {
        case .success(let data):
            let text = String(decoding: data, as: UTF8.self)
            if let login = login(fromAuthStatusText: text) { return .loggedIn(login: login) }
            return text.contains("Logged in") ? .loggedIn(login: nil) : .loggedOut
        case .notAuthenticated: return .loggedOut
        case .failure(let message): return .unverifiable(message)
        case .ghNotFound: return .failed("gh not found")
        }
    }

    /// "Logged in to github.com account octocat (keyring)" or the older "… as octocat (…)".
    static func login(fromAuthStatusText text: String) -> String? {
        for marker in [" account ", " as "] {
            guard let range = text.range(of: marker) else { continue }
            let login = text[range.upperBound...].prefix { !$0.isWhitespace && $0 != "(" }
            if !login.isEmpty { return String(login) }
        }
        return nil
    }

    func merge(url: URL, method: MergeMethod, deleteBranch: Bool, matchHeadCommit: String?) async -> GHOutcome {
        await run(Self.mergeArguments(url: url, method: method, deleteBranch: deleteBranch, matchHeadCommit: matchHeadCommit))
    }

    func enqueue(pullRequestID: String, expectedHeadOid: String) async -> GHOutcome {
        await run(Self.enqueueArguments(pullRequestID: pullRequestID, expectedHeadOid: expectedHeadOid))
    }

    func enableAutoMerge(pullRequestID: String, method: MergeMethod, expectedHeadOid: String) async -> GHOutcome {
        await run(Self.enableAutoMergeArguments(pullRequestID: pullRequestID, method: method, expectedHeadOid: expectedHeadOid))
    }

    func disableAutoMerge(pullRequestID: String) async -> GHOutcome {
        await run(Self.disableAutoMergeArguments(pullRequestID: pullRequestID))
    }

    func markReady(url: URL) async -> GHOutcome {
        await run(["pr", "ready", url.absoluteString])
    }

    func comment(url: URL, body: String) async -> GHOutcome {
        await run(Self.commentArguments(url: url, body: body))
    }

    func approve(url: URL, body: String?) async -> GHOutcome {
        await run(Self.approveArguments(url: url, body: body))
    }

    private func run(_ arguments: [String]) async -> GHOutcome {
        guard let executable = locator() else { return .ghNotFound }
        let started = Date()
        let label = ghLogLabel(arguments)
        AppLog.shared.debug("\(label): \(redactedForLog(arguments))")
        do {
            let result = try await runProcess(executable: executable, arguments: arguments, timeout: Self.timeout)
            AppLog.shared.debug("\(label): exit \(result.exitCode) in \(Int(Date().timeIntervalSince(started) * 1000)) ms, \(result.stdout.count) bytes")
            return Self.interpret(
                exitCode: result.exitCode,
                stdout: result.stdout,
                stderr: String(decoding: result.stderr, as: UTF8.self)
            )
        } catch ProcessFailure.timedOut {
            logger.error("gh timed out after \(Self.timeout.components.seconds, privacy: .public)s")
            return .failure("gh timed out")
        } catch {
            logger.error("could not launch gh: \(String(describing: error), privacy: .public)")
            return .failure("could not launch gh")
        }
    }
}
