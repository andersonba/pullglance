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

    static let searchQuery: String = {
        guard let url = Bundle.app.url(forResource: "search", withExtension: "graphql"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("search.graphql is missing from the resource bundle")
        }
        return text
    }()

    func search(_ query: String) async -> GHOutcome {
        guard let executable = locator() else { return .ghNotFound }
        let arguments = ["api", "graphql", "-f", "query=\(Self.searchQuery)", "-f", "q=\(query)"]
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
