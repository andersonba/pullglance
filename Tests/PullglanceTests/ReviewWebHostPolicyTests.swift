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
        #expect(ReviewWebHost.isRefusedDownload("run.sh\u{07}"))
        #expect(ReviewWebHost.isRefusedDownload("run.s\u{200B}h"))
        // Types the Finder opens and runs without a prompt.
        #expect(ReviewWebHost.isRefusedDownload("Installer.mpkg"))
        #expect(ReviewWebHost.isRefusedDownload("open.terminal"))
        #expect(ReviewWebHost.isRefusedDownload("script.tool"))
        #expect(ReviewWebHost.isRefusedDownload("Do.workflow"))
        #expect(ReviewWebHost.isRefusedDownload("where.fileloc"))
    }

    /// The window shows web pages: javascript: never navigates, data: and blob: only inside frames, where
    /// GitHub uses them; the main frame is always a real page.
    @Test func mainFrameTakesOnlyPages() {
        #expect(ReviewWebHost.allowsScheme("https", isMainFrame: true))
        #expect(ReviewWebHost.allowsScheme("about", isMainFrame: true))
        #expect(!ReviewWebHost.allowsScheme("javascript", isMainFrame: true))
        #expect(!ReviewWebHost.allowsScheme("javascript", isMainFrame: false))
        #expect(!ReviewWebHost.allowsScheme("data", isMainFrame: true))
        #expect(ReviewWebHost.allowsScheme("data", isMainFrame: false))
        #expect(ReviewWebHost.allowsScheme("blob", isMainFrame: false))
        #expect(!ReviewWebHost.allowsScheme("file", isMainFrame: false))
        #expect(!ReviewWebHost.allowsScheme("", isMainFrame: true))
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
