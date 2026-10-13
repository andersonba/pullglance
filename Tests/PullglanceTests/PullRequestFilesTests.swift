import Foundation
import Testing
@testable import Pullglance

func filesEnvelope(total: Int, viewed: [Bool], next: String?) -> Data {
    let nodes = viewed.map { "{\"viewerViewedState\":\"\($0 ? "VIEWED" : "UNVIEWED")\"}" }.joined(separator: ",")
    let cursor = next.map { "\"\($0)\"" } ?? "null"
    return Data("{\"data\":{\"repository\":{\"pullRequest\":{\"changedFiles\":\(total),\"files\":{\"pageInfo\":{\"hasNextPage\":\(next != nil),\"endCursor\":\(cursor)},\"nodes\":[\(nodes)]}}}}}".utf8)
}

@Suite struct PullRequestFilesTests {
    @Test func parsesOnePage() throws {
        let page = try parsePullRequestFilesResponse(filesEnvelope(total: 3, viewed: [true, false, true], next: nil))
        #expect(page == FileCountsPage(total: 3, viewedOnPage: 2, nextCursor: nil))
    }

    @Test func dismissedCountsAsNotViewed() throws {
        let data = Data("{\"data\":{\"repository\":{\"pullRequest\":{\"changedFiles\":1,\"files\":{\"pageInfo\":{\"hasNextPage\":false,\"endCursor\":null},\"nodes\":[{\"viewerViewedState\":\"DISMISSED\"}]}}}}}".utf8)
        #expect(try parsePullRequestFilesResponse(data).viewedOnPage == 0)
    }

    @Test func missingPullRequestThrows() {
        let data = Data("{\"data\":{\"repository\":null},\"errors\":[{\"message\":\"Could not resolve to a Repository\"}]}".utf8)
        #expect(throws: DecodingFailure.self) { try parsePullRequestFilesResponse(data) }
    }

    @Test func pagesUntilTheLastOne() async {
        let gh = FakeGH()
        await gh.setPullRequestFiles([
            .success(filesEnvelope(total: 150, viewed: Array(repeating: true, count: 100), next: "c1")),
            .success(filesEnvelope(total: 150, viewed: Array(repeating: false, count: 50), next: nil)),
        ])
        let counts = await fetchFileCounts(gh, ref: PullRequestRef(owner: "acme", name: "web", number: 7))
        #expect(counts == FileCounts(total: 150, viewed: 100))
        #expect(await gh.fileLookups.map(\.after) == [nil, "c1"])
    }

    @Test func aFailedPageMeansNoCounts() async {
        let gh = FakeGH()
        await gh.setPullRequestFiles([.success(filesEnvelope(total: 150, viewed: [true], next: "c1")), .failure("boom")])
        #expect(await fetchFileCounts(gh, ref: PullRequestRef(owner: "acme", name: "web", number: 7)) == nil)
    }

    @Test func clientArgumentsCarryTheCursor() {
        let args = GHClient.pullRequestFilesArguments(owner: "acme", name: "web", number: 7, after: "c1")
        #expect(args.contains("after=c1"))
        #expect(GHClient.pullRequestFilesArguments(owner: "acme", name: "web", number: 7, after: nil).contains { $0.hasPrefix("after=") } == false)
    }
}
