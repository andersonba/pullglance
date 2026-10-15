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
    private let probe: @Sendable (URL) async -> (version: GHOutcome, auth: GHClient.AuthStatus)
    private let interval: Duration
    private var task: Task<Void, Never>?

    init(locate: @escaping @Sendable () -> URL? = { GHClient.locate() },
         probe: @escaping @Sendable (URL) async -> (version: GHOutcome, auth: GHClient.AuthStatus) = { url in
             let client = GHClient(executable: url)
             return (await client.version(), await client.checkAuth())
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
        // Only the first look shows "checking": later rounds keep the last answer, so a row does not blink
        // and its button does not vanish for the length of a network call every cycle.
        if installed == .unknown { installed = .checking }
        if loggedIn == .unknown { loggedIn = .checking }
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
        case .loggedIn(let login):
            loggedIn = .ok(login ?? String(localized: "Logged in", bundle: .app))
        case .loggedOut:
            loggedIn = .missing
        case .unverifiable(let message), .failed(let message):
            loggedIn = .failed(String(message.prefix(120)))
        }
    }

    nonisolated static func login(from authStatusOutput: String) -> String? { GHClient.login(fromAuthStatusText: authStatusOutput) }

    /// "gh version 2.86.0 (…)" → "2.86.0".
    nonisolated static func version(from output: String) -> String {
        guard let range = output.range(of: "gh version ") else { return "" }
        return String(output[range.upperBound...].prefix { !$0.isWhitespace })
    }
}
