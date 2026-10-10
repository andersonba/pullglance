import Foundation
import Synchronization
import Testing
@testable import Pullglance

@Suite struct GHClientTests {
    @Test func exitZeroIsSuccess() {
        let data = Data("{\"data\":{}}".utf8)
        #expect(GHClient.interpret(exitCode: 0, stdout: data, stderr: "") == .success(data))
    }

    @Test func exitFourIsNotAuthenticated() {
        let stderr = "To get started with GitHub CLI, please run:  gh auth login\n"
        #expect(GHClient.interpret(exitCode: 4, stdout: Data(), stderr: stderr) == .notAuthenticated)
    }

    @Test func authHintInStderrIsNotAuthenticatedEvenWithOtherExitCode() {
        #expect(GHClient.interpret(exitCode: 1, stdout: Data(), stderr: "error: run gh auth login first") == .notAuthenticated)
    }

    // Review Focus 3
    @Test func nonZeroExitWithJSONOnStdoutIsSuccess() {
        let data = Data("{\"errors\":[{\"message\":\"x\"}],\"data\":{\"search\":{\"issueCount\":0,\"nodes\":[]}}}".utf8)
        #expect(GHClient.interpret(exitCode: 1, stdout: data, stderr: "gh: x") == .success(data))
    }

    @Test func nonZeroExitWithoutJSONIsFailureWithStderr() {
        #expect(GHClient.interpret(exitCode: 1, stdout: Data(), stderr: "error connecting to api.github.com\n") == .failure("error connecting to api.github.com"))
    }

    @Test func locatePrefersHomebrewOverPATH() {
        let url = GHClient.locate(environmentPath: "/usr/bin:/Users/me/bin") { $0 == "/opt/homebrew/bin/gh" || $0 == "/Users/me/bin/gh" }
        #expect(url?.path == "/opt/homebrew/bin/gh")
    }

    @Test func locateFallsBackToPATHEntries() {
        let url = GHClient.locate(environmentPath: "/usr/bin:/Users/me/bin") { $0 == "/Users/me/bin/gh" }
        #expect(url?.path == "/Users/me/bin/gh")
    }

    @Test func locateReturnsNilWhenNothingExists() {
        #expect(GHClient.locate(environmentPath: nil) { _ in false } == nil)
    }

    @Test func mergeFieldsAreOptInViaAGraphQLVariable() {
        let with = GHClient.arguments(for: "is:pr", includeMergeState: true)
        let without = GHClient.arguments(for: "is:pr", includeMergeState: false)
        #expect(with.contains("withMerge=true"))
        #expect(without.contains("withMerge=false"))
        #expect(with.contains("q=is:pr"))
        #expect(GHClient.searchQuery.contains("@include(if: $withMerge)"))
    }

    @Test func missingExecutableYieldsGhNotFound() async {
        let client = GHClient(executable: nil)
        #expect(await client.search("is:pr", includeMergeState: false) == .ghNotFound)
    }

    // Review Focus 5: gh installed after the app started must be picked up without a restart.
    @Test func relocatesGhOnEveryCallUntilFound() async {
        let calls = Mutex(0)
        let client = GHClient(locator: {
            calls.withLock { $0 += 1; return $0 >= 2 ? URL(fileURLWithPath: "/usr/bin/true") : nil }
        })
        #expect(await client.search("q", includeMergeState: false) == .ghNotFound)
        #expect(await client.search("q", includeMergeState: false) == .success(Data()))
    }

    /// Blocking cooperative-pool threads made the timeout never fire once enough processes ran at once.
    @Test(.timeLimit(.minutes(1))) func timeoutFiresUnderConcurrencyPressure() async throws {
        let count = ProcessInfo.processInfo.activeProcessorCount * 2
        let start = ContinuousClock.now
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<count {
                group.addTask {
                    await #expect(throws: ProcessFailure.timedOut) {
                        _ = try await runProcess(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["60"], timeout: .milliseconds(500))
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test func runProcessCapturesOutputAndExitCode() async throws {
        let result = try await runProcess(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo out; echo err 1>&2; exit 3"], timeout: .seconds(5))
        #expect(result.exitCode == 3)
        #expect(String(decoding: result.stdout, as: UTF8.self) == "out\n")
        #expect(String(decoding: result.stderr, as: UTF8.self) == "err\n")
    }

    @Test func runProcessTimesOut() async {
        await #expect(throws: ProcessFailure.timedOut) {
            _ = try await runProcess(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: .milliseconds(200))
        }
    }
}
