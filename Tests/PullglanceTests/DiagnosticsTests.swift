import Foundation
import Testing
@testable import Pullglance

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "diag-\(UUID().uuidString)")
}

@Suite struct AppLogTests {
    @Test func writesTimestampedLinesAndCreatesTheFolder() throws {
        let log = AppLog(directory: tempDir())
        defer { try? FileManager.default.removeItem(at: log.directory) }
        log.info("refresh ok")
        let text = try String(contentsOf: log.fileURL, encoding: .utf8)
        let line = try #require(text.split(separator: "\n").first)
        #expect(line.hasSuffix(" INFO refresh ok"))
        #expect(line.count > " INFO refresh ok".count + 15)
    }

    @Test func debugLinesOnlyWhenVerbose() throws {
        let log = AppLog(directory: tempDir())
        defer { try? FileManager.default.removeItem(at: log.directory) }
        log.debug("hidden")
        #expect(!FileManager.default.fileExists(atPath: log.fileURL.path))
        log.isVerbose = true
        log.debug("shown")
        let text = try String(contentsOf: log.fileURL, encoding: .utf8)
        #expect(text.contains(" DEBUG shown"))
        #expect(!text.contains("hidden"))
    }

    @Test func rotatesOnceTheFileOutgrowsTheLimit() throws {
        let log = AppLog(directory: tempDir(), maxBytes: 200)
        defer { try? FileManager.default.removeItem(at: log.directory) }
        for i in 0..<20 { log.info("line number \(i) with some padding text") }
        #expect(FileManager.default.fileExists(atPath: log.rotatedURL.path))
        let current = try Data(contentsOf: log.fileURL)
        #expect(current.count <= 200)
        let rotated = try String(contentsOf: log.rotatedURL, encoding: .utf8)
        #expect(rotated.contains("line number"))
    }

    @Test func ghArgumentsAreRedactedBeforeLogging() {
        #expect(redactedForLog(["pr", "comment", "https://github.com/acme/web/pull/7", "--body", "secret text"]) ==
                "pr comment https://github.com/acme/web/pull/7 --body <redacted>")
        #expect(redactedForLog(["pr", "list", "--repo", "acme/web"]) == "pr list --repo acme/web")
        #expect(redactedForLog(["api", "graphql", "-f", "query=query { a }", "-f", "q=is:pr author:@me"]) == "api graphql -f query=<graphql 11 chars> -f q=is:pr author:@me")
        #expect(redactedForLog(["--body", "line one\nline two"]) == "--body <redacted>")
        #expect(redactedForLog(["x", "first\nsecond"]) == "x first…")
        #expect(ghLogLabel(["api", "graphql", "-f", "query=q", "-f", "q=is:pr is:open author:@me archived:false sort:updated-desc"]) == "gh api graphql [is:pr is:open author:@me archived:false…]")
        #expect(ghLogLabel(["pr", "merge", "https://github.com/acme/web/pull/7", "--squash"]) == "gh pr merge https://github.com/acme/web/pull/7")
        #expect(ghLogLabel(["--version"]) == "gh --version")
        #expect(ghLogLabel(["api", "graphql", "-f", "query=query($owner: String!) {\n}", "-f", "owner=acme", "-f", "name=web", "-F", "number=7"]) == "gh api graphql acme/web#7")
    }
}

@Suite struct DiagnosticsReportTests {
    @Test func rendersOneFactPerLine() {
        let report = DiagnosticsReport(
            appVersion: "0.1.0", macOSVersion: "15.1", ghVersion: "gh version 2.60.0", ghAuthenticated: true,
            refreshIntervalSeconds: 120, badgeMode: "single", visibleSections: ["needsAction"], badgeSections: ["needsAction"],
            hiddenOwnerCount: 1, repoRuleCount: 2, lastGoodDate: Date(timeIntervalSince1970: 0), lastError: nil, failureCount: 0, verbose: true
        )
        let text = report.render()
        #expect(text.contains("Pullglance 0.1.0"))
        #expect(text.contains("macOS 15.1"))
        #expect(text.contains("gh: gh version 2.60.0"))
        #expect(text.contains("gh authenticated: yes"))
        #expect(text.contains("refresh interval: 120 s"))
        #expect(text.contains("hidden owners: 1"))
        #expect(text.contains("repository rules: 2"))
        #expect(text.contains("verbose logging: on"))
        #expect(!text.contains("token"))
    }
}

@Suite struct DiagnosticsExporterTests {
    @Test func zipsTheSummaryTheLogsAndTheScreenshots() throws {
        let work = tempDir()
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let log = work.appending(path: "pullglance.log")
        try Data("hello\n".utf8).write(to: log)
        let shot = work.appending(path: "popover.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: shot)
        let zip = work.appending(path: "out.zip")
        try DiagnosticsExporter.export(to: zip, summary: "Pullglance 0.1.0", logs: [log, work.appending(path: "missing.log")], screenshots: [shot])
        let unpacked = work.appending(path: "unpacked")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, unpacked.path]
        try ditto.run()
        ditto.waitUntilExit()
        let root = unpacked.appending(path: "Pullglance-diagnostics")
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "summary.txt").path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "pullglance.log").path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "screenshots/popover.png").path))
        #expect(try String(contentsOf: root.appending(path: "summary.txt"), encoding: .utf8) == "Pullglance 0.1.0")
    }
}

@MainActor
@Suite struct StoreLoggingTests {
    @Test func refreshesAndActionsLeaveATrailAndVerbosePersists() async throws {
        let gh = FakeGH()
        await gh.set(.success(try fixture("search-mine.json")), for: SearchQuery.mine)
        await gh.set(.success(try fixture("search-direct.json")), for: SearchQuery.direct)
        let log = AppLog(directory: tempDir())
        defer { try? FileManager.default.removeItem(at: log.directory) }
        let defaults = testDefaults()
        let store = PRStore(client: gh, defaults: defaults, now: { Date() }, log: log)
        #expect(store.verboseLogging == false)
        store.verboseLogging = true
        #expect(log.isVerbose)
        await store.refresh()
        let pr = store.mineGroups.readyToMerge[0]
        _ = await store.merge(pr, method: .squash, deleteBranch: false)
        store.snooze(pr)
        let text = try String(contentsOf: log.fileURL, encoding: .utf8)
        #expect(text.contains("refresh ok"))
        #expect(text.contains("merge \(pr.id)"))
        #expect(text.contains("snooze \(pr.id)"))
        #expect(!text.contains(pr.title), "titles stay out of the log")
        let reloaded = PRStore(client: gh, defaults: defaults, now: { Date() }, log: log)
        #expect(reloaded.verboseLogging)
    }
}

@MainActor
@Suite struct DiagnosticsExportFlowTests {
    @Test func exportsAZipWithSummaryLogAndScreenshots() async throws {
        let gh = FakeGH()
        await gh.set(.success(try fixture("search-mine.json")), for: SearchQuery.mine)
        await gh.set(.success(try fixture("search-direct.json")), for: SearchQuery.direct)
        let work = tempDir()
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let log = AppLog(directory: work.appending(path: "logs"))
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() }, log: log)
        await store.refresh()
        let zip = work.appending(path: "diag.zip")
        try await DiagnosticsExport.run(store: store, to: zip, includeScreenshots: true)
        let unpacked = work.appending(path: "unpacked")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, unpacked.path]
        try ditto.run()
        ditto.waitUntilExit()
        let root = unpacked.appending(path: DiagnosticsExporter.folderName)
        let summary = try String(contentsOf: root.appending(path: "summary.txt"), encoding: .utf8)
        #expect(summary.contains("gh: not found"))
        #expect(summary.contains("gh authenticated: unknown"))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "pullglance.log").path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "screenshots/popover-mine.png").path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "screenshots/popover-review.png").path))
    }
}
