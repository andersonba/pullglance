import Foundation
import Testing
@testable import Pullglance

@Suite struct OnboardingStepTests {
    @Test func fiveStepsInTheAgreedOrder() {
        let steps = OnboardingStep.all
        #expect(steps.count == 5)
        #expect(Set(steps.map(\.id)).count == 5)
        #expect(steps[1].content == .requirements)
        #expect(steps.filter { $0.content == .requirements }.count == 1)
        #expect(steps.filter { $0.content == .notifications }.count == 1)
        #expect(steps.last?.content == .notifications)
        #expect(steps[1].pose == .waiting)
        #expect(steps.last?.pose == .pointing)
        #expect(OnboardingStep.index(of: "gh") == 1)
        #expect(OnboardingStep.index(of: "nope") == nil)
    }
}

@MainActor
@Suite struct RequirementCheckerTests {
    private nonisolated static let ghURL = URL(fileURLWithPath: "/opt/homebrew/bin/gh")
    private nonisolated static let authOK = Data("github.com\n  ✓ Logged in to github.com account octocat (keyring)\n".utf8)

    private func checker(found: Bool, version: GHOutcome = .success(Data("gh version 2.86.0 (2026-09-01)\n".utf8)), auth: GHOutcome) -> (RequirementChecker, Counter) {
        let counter = Counter()
        let checker = RequirementChecker(
            locate: { found ? Self.ghURL : nil },
            probe: { _ in counter.bump(); return (version, auth) },
            interval: .milliseconds(20))
        return (checker, counter)
    }

    @Test func missingGhIsMissingAndSkipsTheLoginProbe() async {
        let (checker, counter) = checker(found: false, auth: .success(Self.authOK))
        await checker.checkOnce()
        #expect(checker.installed == .missing)
        #expect(checker.loggedIn == .unknown)
        #expect(checker.allPassed == false)
        #expect(counter.value == 0)
    }

    @Test func loggedOutIsMissingLogin() async {
        let (checker, _) = checker(found: true, auth: .notAuthenticated)
        await checker.checkOnce()
        #expect(checker.installed == .ok("/opt/homebrew/bin/gh · 2.86.0"))
        #expect(checker.loggedIn == .missing)
        #expect(checker.allPassed == false)
    }

    @Test func bothOkCarriesTheLogin() async {
        let (checker, _) = checker(found: true, auth: .success(Self.authOK))
        await checker.checkOnce()
        #expect(checker.loggedIn == .ok("octocat"))
        #expect(checker.allPassed)
    }

    /// Network down, or any other gh failure: say so, rather than "not logged in" forever.
    @Test func otherFailuresAreReportedAsSuch() async {
        let (checker, _) = checker(found: true, auth: .failure("error connecting to github.com"))
        await checker.checkOnce()
        #expect(checker.loggedIn == .failed("error connecting to github.com"))
    }

    @Test func pollingStopsOnceBothPass() async throws {
        let (checker, counter) = checker(found: true, auth: .success(Self.authOK))
        checker.start()
        #expect(await waitUntil { checker.allPassed })
        let probes = counter.value
        try await Task.sleep(for: .milliseconds(120))
        #expect(counter.value == probes)
    }

    @Test func stopEndsThePolling() async throws {
        let (checker, counter) = checker(found: true, auth: .notAuthenticated)
        checker.start()
        #expect(await waitUntil { counter.value >= 2 })
        checker.stop()
        let probes = counter.value
        try await Task.sleep(for: .milliseconds(120))
        #expect(counter.value <= probes + 1)   // at most the probe already in flight
    }

    @Test func loginParserFallsBackToPlainLoggedIn() {
        #expect(RequirementChecker.login(from: "✓ Logged in to github.com account octocat (keyring)") == "octocat")
        #expect(RequirementChecker.login(from: "Logged in to github.com as octocat (oauth_token)") == "octocat")
        #expect(RequirementChecker.login(from: "something new") == nil)
        #expect(RequirementChecker.version(from: "gh version 2.86.0 (2026-09-01)\nhttps://github.com/cli/cli/releases/tag/v2.86.0") == "2.86.0")
        #expect(RequirementChecker.version(from: "garbage") == "")
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func bump() { lock.withLock { count += 1 } }
}
