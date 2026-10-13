import Foundation
import Testing
@testable import Pullglance

@Suite struct ReviewPageTests {
    private func page(_ s: String) -> ReviewPage { ReviewPage.classify(URL(string: s)) }

    @Test func pullRequestTabs() {
        #expect(page("https://github.com/acme/web/pull/42") == .pullRequest(repo: "acme/web", number: 42, tab: .conversation))
        #expect(page("https://github.com/acme/web/pull/42/files") == .pullRequest(repo: "acme/web", number: 42, tab: .files))
        #expect(page("https://github.com/acme/web/pull/42/files/abc123..def456") == .pullRequest(repo: "acme/web", number: 42, tab: .files))
        #expect(page("https://github.com/acme/web/pull/42/changes") == .pullRequest(repo: "acme/web", number: 42, tab: .files))
        #expect(page("https://github.com/acme/web/pull/42/commits") == .pullRequest(repo: "acme/web", number: 42, tab: .commits))
        #expect(page("https://github.com/acme/web/pull/42/checks") == .pullRequest(repo: "acme/web", number: 42, tab: .checks))
        #expect(page("https://github.com/acme/web/pull/42?diff=split#issuecomment-1") == .pullRequest(repo: "acme/web", number: 42, tab: .conversation))
    }

    @Test func decodesCompareRanges() {
        let p = page("https://github.com/acme/web/compare/main...feat%2Fcheckout?expand=1")
        #expect(p == .compare(repo: "acme/web", range: "main...feat/checkout"))
        #expect(p.compareTitle == "main…feat/checkout")
        #expect(page("https://github.com/acme/web/compare/v1.0.0...v1.1.0") == .compare(repo: "acme/web", range: "v1.0.0...v1.1.0"))
    }

    @Test func everythingElseIsOther() {
        #expect(page("https://github.com/acme/web/pulls") == .other)
        #expect(page("https://github.com/acme/web") == .other)
        #expect(page("https://github.com/acme/web/pull/notanumber") == .other)
        #expect(page("https://example.org/acme/web/pull/42") == .other)
        #expect(page("https://github.com/acme/web/compare") == .other)
        #expect(ReviewPage.classify(nil) == .other)
        #expect(page("https://github.com/acme/web/pulls").showsBar == false)
        #expect(page("https://github.com/acme/web/pull/42").showsBar == true)
        #expect(page("https://github.com/acme/web/pull/42").repo == "acme/web")
    }
}
