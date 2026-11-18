import Foundation
import Testing
@testable import Pullglance

/// The bench's command line: what an agent types is what runs.
@Suite struct ReviewBenchTests {
    @Test func absentWithoutTheFlagOrAnAddress() {
        #expect(ReviewBenchOptions.parse(["Pullglance"]) == nil)
        #expect(ReviewBenchOptions.parse(["Pullglance", "--review-bench"]) == nil)
        #expect(ReviewBenchOptions.parse(["Pullglance", "--review-bench", "--keep"]) == nil, "a flag is not an address")
    }

    @Test func defaultsToLookingWithoutTouching() throws {
        let options = try #require(ReviewBenchOptions.parse(["Pullglance", "--review-bench", "https://github.com/o/r/pull/1/files"]))
        #expect(options.url.absoluteString == "https://github.com/o/r/pull/1/files")
        #expect(options.steps == ["wait", "state", "shot"])
        #expect(options.directory == ReviewBenchOptions.defaultDirectory)
        #expect(!options.keep)
    }

    @Test func readsStepsDirectoryAndKeep() throws {
        let options = try #require(ReviewBenchOptions.parse(["Pullglance", "--review-bench", "https://github.com/o/r/pull/1/files",
                                                             "--steps", "wait, skip,shot,open:https://github.com/o/r/pull/2", "--out", "/tmp/bench", "--keep"]))
        #expect(options.steps == ["wait", "skip", "shot", "open:https://github.com/o/r/pull/2"])
        #expect(options.directory.path == "/tmp/bench")
        #expect(options.keep)
    }

    @Test func aStepKeepsTheColonsOfItsArgument() {
        #expect(ReviewBenchOptions.split("skip") == ("skip", nil))
        #expect(ReviewBenchOptions.split("wait:45") == ("wait", "45"))
        #expect(ReviewBenchOptions.split("open:https://github.com/o/r") == ("open", "https://github.com/o/r"))
    }
}
