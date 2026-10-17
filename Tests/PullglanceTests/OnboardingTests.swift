import Foundation
import Testing
@testable import Pullglance

@Suite struct OnboardingStepTests {
    @Test func sixStepsInTheAgreedOrder() {
        let steps = OnboardingStep.all
        #expect(steps.count == 6)
        #expect(Set(steps.map(\.id)).count == 6)
        #expect(steps[1].content == .requirements)
        #expect(steps.filter { $0.content == .requirements }.count == 1)
        #expect(steps.filter { $0.content == .notifications }.count == 1)
        // The shortcut comes after the keys inside the popover and before the send-off.
        #expect(OnboardingStep.index(of: "hotkey") == 4)
        #expect(steps[4].content == .hotkey)
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
    private nonisolated static let authOK = GHClient.AuthStatus.loggedIn(login: "octocat")

    private func checker(found: Bool, version: GHOutcome = .success(Data("gh version 2.86.0 (2026-09-01)\n".utf8)), auth: GHClient.AuthStatus) -> (RequirementChecker, Counter) {
        let counter = Counter()
        let checker = RequirementChecker(
            locate: { found ? Self.ghURL : nil },
            probe: { _ in counter.bump(); return (version, auth) },
            interval: .milliseconds(20))
        return (checker, counter)
    }

    @Test func missingGhIsMissingAndSkipsTheLoginProbe() async {
        let (checker, counter) = checker(found: false, auth: Self.authOK)
        await checker.checkOnce()
        #expect(checker.installed == .missing)
        #expect(checker.loggedIn == .unknown)
        #expect(checker.allPassed == false)
        #expect(counter.value == 0)
    }

    @Test func loggedOutIsMissingLogin() async {
        let (checker, _) = checker(found: true, auth: .loggedOut)
        await checker.checkOnce()
        #expect(checker.installed == .ok("/opt/homebrew/bin/gh · 2.86.0"))
        #expect(checker.loggedIn == .missing)
        #expect(checker.allPassed == false)
    }

    @Test func bothOkCarriesTheLogin() async {
        let (checker, _) = checker(found: true, auth: Self.authOK)
        await checker.checkOnce()
        #expect(checker.loggedIn == .ok("octocat"))
        #expect(checker.allPassed)
    }

    /// Network down, or any other gh failure: say so, rather than "not logged in" forever.
    @Test func otherFailuresAreReportedAsSuch() async {
        let (checker, _) = checker(found: true, auth: .unverifiable("error connecting to github.com"))
        await checker.checkOnce()
        #expect(checker.loggedIn == .failed("error connecting to github.com"))
    }

    @Test func pollingStopsOnceBothPass() async throws {
        let (checker, counter) = checker(found: true, auth: Self.authOK)
        checker.start()
        #expect(await waitUntil { checker.allPassed })
        let probes = counter.value
        try await Task.sleep(for: .milliseconds(120))
        #expect(counter.value == probes)
    }

    @Test func stopEndsThePolling() async throws {
        let (checker, counter) = checker(found: true, auth: .loggedOut)
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

@Suite struct OnboardingProgressTests {
    @Test func dueUntilCompleted() {
        let defaults = testDefaults()
        let progress = OnboardingProgress(defaults: defaults)
        #expect(progress.isDue)
        progress.markCompleted(version: "0.1.0")
        #expect(OnboardingProgress(defaults: defaults).isDue == false)
        #expect(OnboardingProgress(defaults: defaults).completedVersion == "0.1.0")
    }

    /// Closing the window counts as done only once gh is talking; before that it comes back next launch.
    @Test func closingCountsOnlyAfterGhPassed() {
        #expect(OnboardingProgress.shouldMarkCompleted(onClose: true))
        #expect(OnboardingProgress.shouldMarkCompleted(onClose: false) == false)
    }
}

@MainActor
@Suite struct OnboardingHandoffTests {
    @Test func finishingLeavesADotOnTheIcon() async throws {
        let store = PRStore(client: FakeGH(), defaults: testDefaults())
        #expect(store.hasUnseenWoke == false)
        store.showIconDot()
        #expect(store.hasUnseenWoke)
        store.popoverDidOpen()
        #expect(store.hasUnseenWoke == false)
    }
}

/// What `gh auth status` says, in the JSON form (gh ≥ 2.50-ish) and the text form before it.
@Suite struct AuthStatusInterpretationTests {
    @Test func jsonSuccessCarriesTheLogin() {
        let json = Data(#"{"hosts":{"github.com":[{"state":"success","active":true,"host":"github.com","login":"octocat","tokenSource":"keyring"}]}}"#.utf8)
        #expect(GHClient.interpretAuthStatus(json: json) == .loggedIn(login: "octocat"))
    }

    /// A token gh could not verify: offline, or expired. Either way "not logged in" would be wrong.
    @Test func jsonErrorAndTimeoutAreUnverifiable() {
        let error = Data(#"{"hosts":{"github.com":[{"state":"error","active":true,"host":"github.com","login":"octocat","error":"token invalid"}]}}"#.utf8)
        #expect(GHClient.interpretAuthStatus(json: error) == .unverifiable("token invalid"))
        let timeout = Data(#"{"hosts":{"github.com":[{"state":"timeout","active":true,"host":"github.com","login":"octocat"}]}}"#.utf8)
        #expect(GHClient.interpretAuthStatus(json: timeout) == .unverifiable("timeout"))
    }

    /// Only github.com matters: a second host or account in trouble must not block the step.
    @Test func jsonLooksOnlyAtGitHubComAndItsActiveAccount() {
        let json = Data(#"{"hosts":{"ghe.example.com":[{"state":"error","active":true,"host":"ghe.example.com","login":"old"}],"github.com":[{"state":"error","active":false,"host":"github.com","login":"spare"},{"state":"success","active":true,"host":"github.com","login":"octocat"}]}}"#.utf8)
        #expect(GHClient.interpretAuthStatus(json: json) == .loggedIn(login: "octocat"))
    }

    @Test func jsonWithoutTheHostIsLoggedOut() {
        #expect(GHClient.interpretAuthStatus(json: Data(#"{"hosts":{}}"#.utf8)) == .loggedOut)
        #expect(GHClient.interpretAuthStatus(json: Data("garbage".utf8)) == nil)
    }

    @Test func textFormsForOlderGh() {
        #expect(GHClient.interpretAuthStatus(text: .success(Data("github.com\n  ✓ Logged in to github.com account octocat (keyring)\n".utf8))) == .loggedIn(login: "octocat"))
        #expect(GHClient.interpretAuthStatus(text: .success(Data("You are not logged into any accounts on github.com\n".utf8))) == .loggedOut)
        #expect(GHClient.interpretAuthStatus(text: .notAuthenticated) == .loggedOut)
        #expect(GHClient.interpretAuthStatus(text: .failure("gh timed out")) == .unverifiable("gh timed out"))
    }
}

@MainActor
@Suite struct RequirementCheckerFlickerTests {
    /// Re-checking must not pass through "checking": the row would blink and its button vanish every 2 s.
    @Test func reCheckingKeepsTheLastState() async {
        let seen = Recorder()
        var checker: RequirementChecker!
        checker = RequirementChecker(
            locate: { URL(fileURLWithPath: "/opt/homebrew/bin/gh") },
            probe: { _ in
                let state = await MainActor.run { checker.loggedIn }
                seen.append(state)
                return (.success(Data("gh version 2.86.0\n".utf8)), .loggedOut)
            },
            interval: .seconds(1))
        await checker.checkOnce()
        await checker.checkOnce()
        #expect(seen.values == [.checking, .missing])
        #expect(checker.loggedIn == .missing)
    }
}

final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [RequirementState] = []
    var values: [RequirementState] { lock.withLock { items } }
    func append(_ state: RequirementState) { lock.withLock { items.append(state) } }
}

@Suite struct AppActivationTests {
    /// Closing one of our regular windows must not take the Dock icon from another that stays open.
    @Test func returnsToAccessoryOnlyWhenNoOtherRegularWindowStays() {
        #expect(AppActivation.shouldReturnToAccessory(otherVisible: []))
        #expect(AppActivation.shouldReturnToAccessory(otherVisible: [false]))
        #expect(AppActivation.shouldReturnToAccessory(otherVisible: [true, false]) == false)
    }
}
