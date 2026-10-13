import Foundation
import Testing
@testable import Pullglance

@Suite struct ReviewAddressTests {
    @Test func barePathsAreGitHubPaths() {
        #expect(ReviewAddress.normalize("acme/web/pull/7")?.absoluteString == "https://github.com/acme/web/pull/7")
        #expect(ReviewAddress.normalize("github.com/acme")?.absoluteString == "https://github.com/acme")
        #expect(ReviewAddress.normalize("https://github.com/acme/web")?.absoluteString == "https://github.com/acme/web")
        #expect(ReviewAddress.normalize("example.org/x")?.host == "example.org")
        #expect(ReviewAddress.normalize("localhost:3000") == nil)
        #expect(ReviewAddress.normalize("   ") == nil)
    }

    @Test func titleFallsBackToHostAndTruncates() {
        #expect(ReviewAddress.windowTitle(pageTitle: "  PR #7  ", url: nil, fallback: "Review") == "PR #7")
        #expect(ReviewAddress.windowTitle(pageTitle: nil, url: URL(string: "https://github.com/x"), fallback: "Review") == "github.com")
        #expect(ReviewAddress.windowTitle(pageTitle: nil, url: nil, fallback: "Review") == "Review")
        let long = String(repeating: "a", count: 80)
        #expect(ReviewAddress.windowTitle(pageTitle: long, url: nil, fallback: "").count == 55)
    }

    @Test func zoomWalksSafarisSteps() {
        #expect(ReviewAddress.zoomStep(after: 1.0) == 1.15)
        #expect(ReviewAddress.zoomStep(before: 1.0) == 0.85)
        #expect(ReviewAddress.zoomStep(after: 3.0) == 3.0)
        #expect(ReviewAddress.zoomStep(before: 0.5) == 0.5)
    }

    @Test func landingPagesPerTab() {
        let pr = makePR(repo: "acme/web", number: 7)
        #expect(ReviewAddress.url(for: pr, landing: .conversation) == pr.url)
        #expect(ReviewAddress.url(for: pr, landing: .files).path.hasSuffix("/7/files"))
    }
}
