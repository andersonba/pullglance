import Foundation
import Observation

/// A published release of the app on GitHub: the latest non-draft, non-prerelease one.
struct Release: Equatable, Sendable {
    let version: String
    let url: URL

    /// The `releases/latest` object: tag `vX.Y.Z` (the v is optional), its page.
    static func parse(_ data: Data) -> Release? {
        struct Raw: Decodable { let tag_name: String; let html_url: URL; let draft: Bool?; let prerelease: Bool? }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data), raw.draft != true, raw.prerelease != true else { return nil }
        let version = raw.tag_name.hasPrefix("v") ? String(raw.tag_name.dropFirst()) : raw.tag_name
        return Release(version: version, url: raw.html_url)
    }

    /// Numeric, component by component; a missing component is 0. Anything that is not numbers (a dev
    /// build) is never older than a release.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = components(candidate), let b = components(current) else { return false }
        let n = max(a.count, b.count)
        for i in 0..<n {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func isComparable(_ version: String) -> Bool { components(version) != nil }

    private static func components(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.map { $0! }
    }
}

/// Asks GitHub for the latest release through the same gh: shortly after launch, then once a day while the
/// app runs. Nothing is downloaded: the offer opens the release page, whose notes carry the upgrade command.
/// A skipped version stays quiet in the menus until a newer one; a check asked by hand still reports it.
@MainActor
@Observable
final class UpdateChecker {
    enum CheckResult: Equatable, Sendable {
        case available(Release)
        case upToDate
        /// gh missing, offline, no release yet (404): the message, for a check asked by hand.
        case failed(String)
    }

    static let skippedKey = "updates.skippedVersion"

    /// The newer release the menus offer, if any.
    private(set) var available: Release?
    private let defaults: UserDefaults
    private let currentVersion: String
    private let fetch: @Sendable () async -> GHOutcome
    private var inFlight: Task<GHOutcome, Never>?

    init(defaults: UserDefaults = .standard, currentVersion: String = AppInfo.version, fetch: @escaping @Sendable () async -> GHOutcome) {
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.fetch = fetch
    }

    /// One request at a time: a second call while one is out waits for the same answer.
    @discardableResult
    func check(manual: Bool = false) async -> CheckResult {
        let outcome: GHOutcome
        if let inFlight {
            outcome = await inFlight.value
        } else {
            let task = Task { [fetch] in await fetch() }
            inFlight = task
            outcome = await task.value
            inFlight = nil
        }
        let release: Release
        switch outcome {
        case .success(let data):
            guard let parsed = Release.parse(data) else { return .failed("Unexpected answer from GitHub") }
            release = parsed
        case .ghNotFound: return .failed("gh not found")
        case .notAuthenticated: return .failed("gh is not logged in")
        case .failure(let message): return .failed(message)
        }
        guard Release.isNewer(release.version, than: currentVersion) else {
            available = nil
            // A dev build ("dev") is never nagged; asked by hand, it gets the page rather than "dev is the latest".
            return manual && !Release.isComparable(currentVersion) ? .available(release) : .upToDate
        }
        let skipped = defaults.string(forKey: Self.skippedKey)
        available = release.version == skipped ? nil : release
        return manual || available != nil ? .available(release) : .upToDate
    }

    func skip() {
        guard let available else { return }
        defaults.set(available.version, forKey: Self.skippedKey)
        self.available = nil
    }

    /// 20 s after launch, then daily for the life of the app. Nothing is persisted between launches: a
    /// known release is found again on the next start.
    func start() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                guard let self else { return }
                await self.check()
                try? await Task.sleep(for: .seconds(24 * 3_600))
            }
        }
    }
}
