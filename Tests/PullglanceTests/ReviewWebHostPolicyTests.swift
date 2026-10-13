import Foundation
import Testing
@testable import Pullglance

@MainActor
struct ReviewWebHostPolicyTests {
    @Test func refusesExecutableDownloads() {
        #expect(!ReviewWebHost.isRefusedDownload("report.pdf"))
        #expect(ReviewWebHost.isRefusedDownload("setup.pkg"))
        #expect(!ReviewWebHost.isRefusedDownload("Archive.zip"))
        #expect(ReviewWebHost.isRefusedDownload("run.sh"))
        #expect(ReviewWebHost.isRefusedDownload("Tool.APP"))
        #expect(ReviewWebHost.isRefusedDownload("run.sh. "))
    }

    @Test func identityProvidersStayOnlyInsidePopups() {
        let idp = URL(string: "https://example.okta.com/login")
        let page = URL(string: "https://github.com/acme/widgets/pull/1")
        #expect(ReviewWebHost.clickLeavesWindow(idp, from: page, inPopup: false))
        #expect(!ReviewWebHost.clickLeavesWindow(idp, from: page, inPopup: true))
        #expect(!ReviewWebHost.clickLeavesWindow(URL(string: "https://github.com/acme"), from: page, inPopup: false))
        #expect(ReviewWebHost.clickLeavesWindow(URL(string: "https://example.com/"), from: page, inPopup: true))
        // Already on that host (reached by redirect): stays, in either web view.
        #expect(!ReviewWebHost.clickLeavesWindow(idp, from: URL(string: "https://example.okta.com/start"), inPopup: false))
    }
}
