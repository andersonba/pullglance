import Foundation
import Observation

enum RequirementState: Equatable, Sendable {
    case unknown
    case checking
    /// Detail shown under the title: path and version, or the login.
    case ok(String)
    case missing
    /// gh answered with something other than "not logged in": the message, shortened.
    case failed(String)

    var passed: Bool { if case .ok = self { return true }; return false }
}

/// Is gh installed, and logged in? Checked every `interval` while `start()`ed, until both pass or
/// `stop()`. `probe` runs `gh --version` and `gh auth status` for a found executable; injected so tests
/// need no gh.
@MainActor
@Observable
final class RequirementChecker {
    private(set) var installed: RequirementState = .unknown
    private(set) var loggedIn: RequirementState = .unknown
    var allPassed: Bool { installed.passed && loggedIn.passed }

    private let locate: @Sendable () -> URL?
    private let probe: @Sendable (URL) async -> (version: GHOutcome, auth: GHOutcome)
    private let interval: Duration
    private var task: Task<Void, Never>?

    init(locate: @escaping @Sendable () -> URL? = { GHClient.locate() },
         probe: @escaping @Sendable (URL) async -> (version: GHOutcome, auth: GHOutcome) = { url in
             let client = GHClient(executable: url)
             return (await client.version(), await client.authStatus())
         },
         interval: Duration = .seconds(2)) {
        self.locate = locate
        self.probe = probe
        self.interval = interval
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.checkOnce()
                if self.allPassed { self.task = nil; return }
                try? await Task.sleep(for: self.interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func checkOnce() async {
        guard let url = locate() else {
            installed = .missing
            loggedIn = .unknown
            return
        }
        if !installed.passed { installed = .checking }
        if !loggedIn.passed { loggedIn = .checking }
        let result = await probe(url)
        switch result.version {
        case .success(let data):
            let version = Self.version(from: String(decoding: data, as: UTF8.self))
            installed = .ok(version.isEmpty ? url.path : "\(url.path) · \(version)")
        case .ghNotFound:
            installed = .missing
            loggedIn = .unknown
            return
        case .notAuthenticated, .failure:
            installed = .ok(url.path)
        }
        switch result.auth {
        case .success(let data):
            let login = Self.login(from: String(decoding: data, as: UTF8.self))
            loggedIn = .ok(login ?? String(localized: "Logged in", bundle: .app))
        case .notAuthenticated:
            loggedIn = .missing
        case .ghNotFound:
            installed = .missing
            loggedIn = .unknown
        case .failure(let message):
            loggedIn = .failed(String(message.prefix(120)))
        }
    }

    /// "Logged in to github.com account octocat (keyring)" or the older "… as octocat (…)".
    nonisolated static func login(from authStatusOutput: String) -> String? {
        for marker in [" account ", " as "] {
            guard let range = authStatusOutput.range(of: marker) else { continue }
            let rest = authStatusOutput[range.upperBound...]
            let login = rest.prefix { !$0.isWhitespace && $0 != "(" }
            if !login.isEmpty { return String(login) }
        }
        return nil
    }

    /// "gh version 2.86.0 (…)" → "2.86.0".
    nonisolated static func version(from output: String) -> String {
        guard let range = output.range(of: "gh version ") else { return "" }
        return String(output[range.upperBound...].prefix { !$0.isWhitespace })
    }
}
