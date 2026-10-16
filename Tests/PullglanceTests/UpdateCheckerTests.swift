import Foundation
import Testing
@testable import Pullglance

@Suite struct ReleaseTests {
    @Test func parsesTheLatestRelease() throws {
        let json = Data(#"{"tag_name":"v0.2.0","name":"0.2.0","html_url":"https://github.com/acme/widgets/releases/tag/v0.2.0","draft":false,"prerelease":false,"published_at":"2026-10-20T10:00:00Z"}"#.utf8)
        let release = try #require(Release.parse(json))
        #expect(release.version == "0.2.0")
        #expect(release.url.absoluteString == "https://github.com/acme/widgets/releases/tag/v0.2.0")
    }

    @Test func draftsAndPrereleasesAndGarbageAreNotReleases() {
        #expect(Release.parse(Data(#"{"tag_name":"v0.3.0","html_url":"https://x","draft":true,"prerelease":false}"#.utf8)) == nil)
        #expect(Release.parse(Data(#"{"tag_name":"v0.3.0-beta.1","html_url":"https://x","draft":false,"prerelease":true}"#.utf8)) == nil)
        #expect(Release.parse(Data("not json".utf8)) == nil)
    }

    @Test func numericVersionOrder() {
        #expect(Release.isNewer("0.2.0", than: "0.1.0"))
        #expect(Release.isNewer("0.10.0", than: "0.9.3"))
        #expect(Release.isNewer("1.0.0", than: "0.99.99"))
        #expect(Release.isNewer("0.1.1", than: "0.1.0"))
        #expect(Release.isNewer("0.1.0", than: "0.1.0") == false)
        #expect(Release.isNewer("0.1.0", than: "0.2.0") == false)
        #expect(Release.isNewer("0.2", than: "0.1.9"))          // a short tag compares as 0.2.0
        #expect(Release.isNewer("0.2.0", than: "dev") == false)  // a dev build never nags
    }
}

@MainActor
@Suite struct UpdateCheckerTests {
    private func checker(latest: GHOutcome, version: String = "0.1.0", defaults: UserDefaults? = nil) -> (UpdateChecker, UserDefaults) {
        let defaults = defaults ?? testDefaults()
        let checker = UpdateChecker(defaults: defaults, currentVersion: version, fetch: { latest })
        return (checker, defaults)
    }
    private let newer = GHOutcome.success(Data(#"{"tag_name":"v0.2.0","html_url":"https://github.com/acme/widgets/releases/tag/v0.2.0","draft":false,"prerelease":false}"#.utf8))

    @Test func aNewerReleaseIsOffered() async {
        let (checker, _) = checker(latest: newer)
        let result = await checker.check()
        #expect(checker.available?.version == "0.2.0")
        #expect(result == .available(Release(version: "0.2.0", url: URL(string: "https://github.com/acme/widgets/releases/tag/v0.2.0")!)))
    }

    @Test func theCurrentOrOlderReleaseIsNot() async {
        let (checker, _) = checker(latest: newer, version: "0.2.0")
        #expect(await checker.check() == .upToDate)
        #expect(checker.available == nil)
        let (older, _) = self.checker(latest: newer, version: "0.3.0")
        #expect(await older.check() == .upToDate)
        #expect(older.available == nil)
    }

    /// Before the first release exists, GitHub answers 404: nothing to offer. The result says so for a manual
    /// check; the automatic one has nothing to show and nothing worth a line in the log.
    @Test func noReleaseYetIsQuiet() async {
        let (checker, _) = checker(latest: .failure("HTTP 404: Not Found (https://api.github.com/repos/acme/widgets/releases/latest)"))
        let result = await checker.check()
        #expect(checker.available == nil)
        guard case .failed(let message) = result else { Issue.record("expected a failure, got \(result)"); return }
        #expect(message.contains("404"))
    }

    @Test func skippingAVersionSilencesItUntilTheNextOne() async {
        let (checker, defaults) = checker(latest: newer)
        await checker.check()
        checker.skip()
        #expect(checker.available == nil)
        let (again, _) = self.checker(latest: newer, defaults: defaults)
        await again.check()
        #expect(again.available == nil)
        let next = GHOutcome.success(Data(#"{"tag_name":"v0.2.1","html_url":"https://github.com/acme/widgets/releases/tag/v0.2.1","draft":false,"prerelease":false}"#.utf8))
        let (later, _) = self.checker(latest: next, defaults: defaults)
        await later.check()
        #expect(later.available?.version == "0.2.1")
    }

    /// Asking by hand means "tell me", skipped or not; the quiet offer in the menus still honours the skip.
    @Test func aManualCheckIgnoresTheSkippedVersion() async {
        let (checker, _) = checker(latest: newer)
        await checker.check()
        checker.skip()
        let result = await checker.check(manual: true)
        guard case .available(let release) = result else { Issue.record("expected the release, got \(result)"); return }
        #expect(release.version == "0.2.0")
        #expect(checker.available == nil)
    }

    /// `swift run` reports "dev": never nagged, but a check by hand still shows the release.
    @Test func aDevBuildIsQuietUnlessAsked() async {
        let (checker, _) = checker(latest: newer, version: "dev")
        #expect(await checker.check() == .upToDate)
        #expect(checker.available == nil)
        guard case .available(let release) = await checker.check(manual: true) else { Issue.record("expected the release"); return }
        #expect(release.version == "0.2.0")
        #expect(checker.available == nil)
    }

    /// Two checks at once (the daily timer and a click) share one request.
    @Test func concurrentChecksShareOneFetch() async {
        let calls = Counter()
        let checker = UpdateChecker(defaults: testDefaults(), currentVersion: "0.1.0", fetch: { [newer] in
            calls.bump()
            try? await Task.sleep(for: .milliseconds(50))
            return newer
        })
        async let first = checker.check()
        async let second = checker.check(manual: true)
        let results = await [first, second]
        #expect(results.allSatisfy { if case .available = $0 { return true } else { return false } })
        #expect(calls.value == 1)
    }
}
