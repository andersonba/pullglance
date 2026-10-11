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

    private static func document(_ name: String) -> String {
        guard let url = Bundle.app.url(forResource: name, withExtension: "graphql"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("\(name).graphql is missing from the resource bundle")
        }
        return text
    }

    /// `-F` sends a typed value, so `withMerge` reaches GraphQL as a Boolean.
    static func arguments(for query: String, includeMergeState: Bool) -> [String] {
        ["api", "graphql", "-f", "query=\(searchQuery)", "-f", "q=\(query)", "-F", "withMerge=\(includeMergeState)"]
    }

    func search(_ query: String, includeMergeState: Bool) async -> GHOutcome {
        await run(Self.arguments(for: query, includeMergeState: includeMergeState))
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

    static func commentArguments(url: URL, body: String) -> [String] {
        ["pr", "comment", url.absoluteString, "--body", body]
    }

    static func openPullRequestsArguments(repo: String, base: String) -> [String] {
        ["pr", "list", "--repo", repo, "--base", base, "--state", "open", "--json", "number", "--limit", "100"]
    }

    func openPullRequests(repo: String, base: String) async -> GHOutcome {
        await run(Self.openPullRequestsArguments(repo: repo, base: base))
    }

    func merge(url: URL, method: MergeMethod, deleteBranch: Bool, matchHeadCommit: String?) async -> GHOutcome {
        await run(Self.mergeArguments(url: url, method: method, deleteBranch: deleteBranch, matchHeadCommit: matchHeadCommit))
    }

    func comment(url: URL, body: String) async -> GHOutcome {
        await run(Self.commentArguments(url: url, body: body))
    }

    private func run(_ arguments: [String]) async -> GHOutcome {
        guard let executable = locator() else { return .ghNotFound }
        do {
            let result = try await runProcess(executable: executable, arguments: arguments, timeout: Self.timeout)
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
