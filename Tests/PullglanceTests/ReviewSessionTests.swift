import Foundation
import Testing
@testable import Pullglance

/// Scripted page script: returns what it is told and records every call.
@MainActor
final class FakeScripting: ReviewScripting {
    var results: [String: Result<Any?, Error>] = [:]
    private(set) var calls: [(function: String, args: [Any])] = []
    struct Boom: Error {}
    /// Functions whose next call suspends until `release()`; each hold applies once.
    var holds: Set<String> = []
    private var held: [CheckedContinuation<Void, Never>] = []
    func release() { let waiting = held; held = []; waiting.forEach { $0.resume() } }
    func call(_ function: String, _ arguments: [String: Any]) async throws -> Any? {
        calls.append((function, arguments["args"] as? [Any] ?? []))
        if holds.remove(function) != nil { await withCheckedContinuation { held.append($0) } }
        guard let result = results[function] else { return nil }
        return try result.get()
    }
}

@MainActor
@Suite struct ReviewSessionTests {
    private let pr7 = makePR(repo: "acme/web", number: 7)

    private func make(mine: [PullRequest] = []) async -> (ReviewSession, FakeGH, FakeScripting, PRStore) {
        let gh = FakeGH()
        await gh.set(.success(envelope(nodes: mine.map { node(number: $0.number, ci: "SUCCESS", decision: "APPROVED") })), for: SearchQuery.mine)
        await gh.set(.success(envelope(nodes: [])), for: SearchQuery.direct)
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        await store.refresh()
        let scripting = FakeScripting()
        scripting.results["counts"] = .success(["total": 3, "viewed": 1, "matching": 2, "partial": false, "perRule": ["js-unit": 2]])
        let session = ReviewSession(store: store, client: gh, scripting: scripting, settings: ReviewSettingsStore(defaults: testDefaults()), defaults: testDefaults())
        return (session, gh, scripting, store)
    }

    /// The URL changes before the new document exists, so the first push can land on the document being
    /// replaced. The fresh document's script posts `context` with `ready: false`: that is the cue to push again.
    @Test func aFreshDocumentWithoutSettingsGetsThemPushedAgain() async {
        let (s, gh, scripting, _) = await make(mine: [pr7])
        await gh.setPullRequestFiles([.success(filesEnvelope(total: 3, viewed: [true, false, false], next: nil))])
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7/files"))
        await s.settle()
        #expect(scripting.calls.map(\.function) == ["setSettings", "counts"])
        s.scriptEvent("context", ["kind": "pull", "basePath": "/acme/web/pull/7", "key": "k", "ready": true])
        await s.settle()
        #expect(scripting.calls.map(\.function) == ["setSettings", "counts"], "a document that has settings is left alone")
        s.scriptEvent("context", ["kind": "pull", "basePath": "/acme/web/pull/7", "key": "k", "ready": false])
        await s.settle()
        #expect(scripting.calls.map(\.function) == ["setSettings", "counts", "setSettings", "counts"])
    }

    @Test func enteringAPullRequestPicksTheStoresPRAndFetchesCounts() async {
        let (s, gh, scripting, _) = await make(mine: [pr7])
        await gh.setPullRequestFiles([.success(filesEnvelope(total: 3, viewed: [true, false, false], next: nil))])
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7/files"))
        await s.settle()
        #expect(s.page == .pullRequest(repo: "acme/web", number: 7, tab: .files))
        #expect(s.pullRequest?.number == 7)
        #expect(s.fileCounts == FileCounts(total: 3, viewed: 1))
        #expect(s.pageCounts?.matching == 2)
        #expect(scripting.calls.map(\.function) == ["setSettings", "counts"])
        #expect(s.showsBar)
    }

    @Test func otherPagesHideTheBarAndFetchNothing() async {
        let (s, gh, _, _) = await make()
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pulls"))
        await s.settle()
        #expect(s.showsBar == false)
        #expect(await gh.fileLookups.isEmpty)
    }

    @Test func markShowsTheResultAndRefreshesCounts() async {
        let (s, gh, scripting, _) = await make(mine: [pr7])
        await gh.setPullRequestFiles([.success(filesEnvelope(total: 3, viewed: [true, false, false], next: nil)), .success(filesEnvelope(total: 3, viewed: [true, true, true], next: nil))])
        scripting.results["mark"] = .success(["marked": 2, "failed": 0, "skipped": 0, "unknown": 0, "canUndo": true])
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7/files"))
        await s.settle()
        await s.mark()
        #expect(s.notice == .marked(count: 2, failed: 0, canUndo: true))
        #expect(s.busy == false)
        #expect(s.fileCounts == FileCounts(total: 3, viewed: 3))
        #expect(scripting.calls.last { $0.function == "mark" }?.args.first is NSNull)   // auto → null rule ids
    }

    @Test func chosenPresetIsPassedAndRemembered() async {
        let (s, _, scripting, _) = await make(mine: [pr7])
        scripting.results["mark"] = .success(["marked": 1, "failed": 0, "skipped": 0, "unknown": 0, "canUndo": true])
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7/files"))
        await s.settle()
        s.choose(.preset("python"))
        await s.mark()
        #expect(scripting.calls.last { $0.function == "mark" }?.args.first as? [String] == ["python"])
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7"))
        await s.settle()
        #expect(s.presetChoice == .preset("python"))
    }

    @Test func scriptFailureEndsBusyWithAnErrorNotice() async {
        let (s, _, scripting, _) = await make(mine: [pr7])
        scripting.results["mark"] = .failure(FakeScripting.Boom())
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7/files"))
        await s.settle()
        await s.mark()
        #expect(s.busy == false)
        if case .error = s.notice {} else { Issue.record("expected an error notice, got \(String(describing: s.notice))") }
    }

    @Test func contextChangeSwitchesPullRequestAndDropsUndo() async {
        let pr8 = makePR(repo: "acme/web", number: 8)
        let (s, gh, scripting, _) = await make(mine: [pr7, pr8])
        // Three pages: PR 7 on entry, PR 7 again after mark (perform refreshes counts), then PR 8.
        await gh.setPullRequestFiles([
            .success(filesEnvelope(total: 3, viewed: [true, false, false], next: nil)),
            .success(filesEnvelope(total: 3, viewed: [true, true, true], next: nil)),
            .success(filesEnvelope(total: 5, viewed: [false, false, false, false, false], next: nil)),
        ])
        scripting.results["mark"] = .success(["marked": 2, "failed": 0, "skipped": 0, "unknown": 0, "canUndo": true])
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7/files"))
        await s.settle()
        await s.mark()
        #expect(s.notice == .marked(count: 2, failed: 0, canUndo: true))
        // Turbo navigation inside GitHub: the script reports a new context before any didFinish.
        s.scriptEvent("context", ["kind": "pull", "basePath": "/acme/web/pull/8", "key": "k8"])
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/8/files"))
        await s.settle()
        #expect(s.pullRequest?.number == 8)
        #expect(s.notice == nil)
        #expect(s.fileCounts == FileCounts(total: 5, viewed: 0))
    }

    @Test func compareHasPageCountsButNoGraphQL() async {
        let (s, gh, _, _) = await make()
        s.pageChanged(to: URL(string: "https://github.com/acme/web/compare/main...feat%2Fx"))
        await s.settle()
        #expect(s.page.compareTitle == "main…feat/x")
        #expect(s.fileCounts == nil)
        #expect(s.pageCounts?.total == 3)
        #expect(await gh.fileLookups.isEmpty)
    }

    @Test func settingsEditsAreCoalescedIntoOnePush() async throws {
        let gh = FakeGH()
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        let scripting = FakeScripting()
        let settings = ReviewSettingsStore(defaults: testDefaults())
        let s = ReviewSession(store: store, client: gh, scripting: scripting, settings: settings, defaults: testDefaults())
        s.pageChanged(to: URL(string: "https://github.com/acme/web/compare/main...feat"))
        await s.settle()
        for text in ["*", "*.", "*.md"] { settings.settings.customGlobsText = text }   // one per keystroke
        try await Task.sleep(for: ReviewSession.settingsPushDelay * 3)
        await s.settle()
        #expect(scripting.calls.map(\.function) == ["setSettings", "counts", "setSettings", "counts"])
    }

    @Test func aPageChangeDuringASettingsPushPushesAgainBeforeCounting() async {
        let (s, _, scripting, _) = await make(mine: [pr7])
        scripting.holds = ["setSettings"]
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7/files"))
        while scripting.calls.isEmpty { await Task.yield() }   // first push is suspended in the page
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7"))   // new document: needs settings again
        scripting.release()
        await s.settle()
        let functions = scripting.calls.map(\.function)
        let pushes = functions.indices.filter { functions[$0] == "setSettings" }
        #expect(pushes.count >= 2, "calls: \(functions)")
        if pushes.count >= 2, let firstCount = functions.firstIndex(of: "counts") {
            #expect(firstCount > pushes[1], "counts ran before the second setSettings: \(functions)")
        }
    }

    @Test func markRightAfterAPageChangePushesSettingsFirst() async {
        let (s, _, scripting, _) = await make(mine: [pr7])
        scripting.results["mark"] = .success(["marked": 1, "failed": 0, "skipped": 0, "unknown": 0, "canUndo": true])
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7/files"))
        await s.settle()
        let before = scripting.calls.count
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7"))
        #expect(s.pageCounts != nil)   // kept across a tab change, so Mark stays enabled
        await s.mark()
        let tail = Array(scripting.calls.map(\.function).dropFirst(before))
        #expect(tail.first == "setSettings", "calls after the page change: \(tail)")
        #expect(tail.contains("mark"))
    }

    @Test func hidingTheBarPersists() async {
        let defaults = testDefaults()
        let gh = FakeGH()
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        let s = ReviewSession(store: store, client: gh, scripting: FakeScripting(), settings: ReviewSettingsStore(defaults: testDefaults()), defaults: defaults)
        s.isBarHidden = true
        let again = ReviewSession(store: store, client: gh, scripting: FakeScripting(), settings: ReviewSettingsStore(defaults: testDefaults()), defaults: defaults)
        #expect(again.isBarHidden)
    }
    @Test func autoMarkMarksOncePerPullRequest() async {
        let gh = FakeGH()
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        let scripting = FakeScripting()
        scripting.results["counts"] = .success(["total": 3, "viewed": 1, "matching": 2, "partial": false, "perRule": ["js-unit": 2]])
        scripting.results["mark"] = .success(["marked": 2, "failed": 0, "canUndo": true])
        let settings = ReviewSettingsStore(defaults: testDefaults())
        settings.settings.autoMark = true
        let s = ReviewSession(store: store, client: gh, scripting: scripting, settings: settings, defaults: testDefaults())
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7/files"))
        await s.settle()
        #expect(scripting.calls.filter { $0.function == "mark" }.count == 1)
        #expect(s.notice == .marked(count: 2, failed: 0, canUndo: true))
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7"))
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7/files"))
        await s.settle()
        #expect(scripting.calls.filter { $0.function == "mark" }.count == 1)
    }
    /// Auto-mark is once per pull request, across app runs too: a restart (an update installs one) must not
    /// mark again the files the user unmarked on a visit before it.
    @Test func autoMarkRemembersThePullRequestAcrossSessions() async {
        let gh = FakeGH()
        let defaults = testDefaults()
        let store = PRStore(client: gh, defaults: defaults, now: { Date() })
        let settings = ReviewSettingsStore(defaults: defaults)
        settings.settings.autoMark = true
        func session() -> (ReviewSession, FakeScripting) {
            let scripting = FakeScripting()
            scripting.results["counts"] = .success(["total": 3, "viewed": 1, "matching": 2, "partial": false, "perRule": ["js-unit": 2]])
            scripting.results["mark"] = .success(["marked": 2, "failed": 0, "canUndo": true])
            return (ReviewSession(store: store, client: gh, scripting: scripting, settings: settings, defaults: defaults), scripting)
        }
        let (first, firstScripting) = session()
        first.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7/files"))
        await first.settle()
        #expect(firstScripting.calls.filter { $0.function == "mark" }.count == 1)
        let (second, secondScripting) = session()
        second.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7/files"))
        await second.settle()
        #expect(secondScripting.calls.filter { $0.function == "mark" }.isEmpty)
        // Another pull request is still new.
        second.pageChanged(to: URL(string: "https://github.com/acme/web/pull/8/files"))
        await second.settle()
        #expect(secondScripting.calls.filter { $0.function == "mark" }.count == 1)
    }

    @Test func aFailedMergeShowsInTheBarAndSuccessStaysQuiet() async {
        let (s, _, _, _) = await make(mine: [pr7])
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7"))
        await s.settle()
        await s.report(.success(note: nil))
        #expect(s.notice == nil)
        await s.report(.failure("Merge blocked"))
        #expect(s.notice == .error("Merge blocked"))
    }

    @Test func samePageReportedTwiceFetchesCountsOnce() async {
        let (s, gh, _, _) = await make(mine: [pr7])
        await gh.setPullRequestFiles([.success(filesEnvelope(total: 3, viewed: [true, false, false], next: nil))])
        let url = URL(string: "https://github.com/acme/web/pull/7/files")
        s.pageChanged(to: url)
        s.pageChanged(to: url)
        await s.settle()
        #expect(await gh.fileLookups.count == 1)
        #expect(s.fileCounts == FileCounts(total: 3, viewed: 1))
    }

    /// URL KVO starts the fetch; didFinish reports the same document while it is still in flight.
    @Test func samePageReportedWhileCountsAreInFlightFetchesOnce() async {
        let (s, gh, _, _) = await make(mine: [pr7])
        await gh.setPullRequestFiles([.success(filesEnvelope(total: 3, viewed: [true, false, false], next: nil))])
        await gh.holdFileLookups()
        let url = URL(string: "https://github.com/acme/web/pull/7/files")
        s.pageChanged(to: url)
        while await gh.fileLookups.isEmpty { await Task.yield() }
        s.pageChanged(to: url)
        await gh.releaseFileLookups()
        await s.settle()
        #expect(await gh.fileLookups.count == 1)
        #expect(s.fileCounts == FileCounts(total: 3, viewed: 1))
    }

    @Test func undoWithoutAnUndoableMarkingDoesNothing() async {
        let (s, _, scripting, _) = await make(mine: [pr7])
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7/files"))
        await s.settle()
        await s.undo()
        #expect(!scripting.calls.contains { $0.function == "undo" })
        #expect(s.notice == nil)
    }

    @Test func editingInThePageIsTracked() async {
        let (s, _, _, _) = await make(mine: [pr7])
        #expect(!s.isEditingInPage)
        s.scriptEvent("editing", ["active": true])
        #expect(s.isEditingInPage)
        s.scriptEvent("editing", ["active": false])
        #expect(!s.isEditingInPage)
    }

    @Test func reloadingTheSamePageClearsTheEditingFlag() async {
        let (s, _, _, _) = await make(mine: [pr7])
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7/files"))
        await s.settle()
        s.scriptEvent("editing", ["active": true])
        // ⌘R while typing: the new document starts with no focused field and never posts {active: false}.
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7/files"))
        await s.settle()
        #expect(!s.isEditingInPage)
    }

    /// The pill's arrows and ⌘↑/⌘↓ are one movement: the previous or next unviewed file while some are left,
    /// and every file once all are viewed, so a mark can be undone from there.
    @Test func unviewedStepWalksEveryFileOnceAllAreViewed() async {
        let (s, _, scripting, _) = await make(mine: [pr7])
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7/files"))
        await s.settle()
        s.scriptEvent("listing", nil)
        await s.settle()
        #expect(s.unviewedLeft == 2)
        await s.stepUnviewed(1)
        #expect(scripting.calls.last?.function == "scrollToUnviewed")
        #expect(scripting.calls.last?.args.first as? String == "next")
        scripting.results["counts"] = .success(["total": 3, "viewed": 3, "matching": 0, "partial": false, "perRule": [:]])
        s.scriptEvent("listing", nil)
        await s.settle()
        #expect(s.unviewedLeft == 0)
        await s.stepUnviewed(-1)
        #expect(scripting.calls.last?.function == "stepFile")
        #expect(scripting.calls.last?.args.first as? Int == -1)
    }

    @Test func fileCursorComesFromTheScriptAndDrivesThePill() async {
        let (s, _, scripting, _) = await make(mine: [pr7])
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7/files"))
        await s.settle()
        #expect(!s.showsFilePill)
        s.scriptEvent("current", ["id": "h1", "path": "src/checkout/api.ts", "index": 12, "total": 34, "viewed": false])
        #expect(s.currentFile?.name == "api.ts")
        #expect(s.currentFile?.index == 12)
        #expect(s.showsFilePill)
        await s.stepFile(1)
        await s.markCurrentAndNext()
        await s.unmarkCurrent()
        #expect(scripting.calls.map(\.function).filter { ["stepFile", "markCurrentAndNext", "setCurrentViewed"].contains($0) } == ["stepFile", "markCurrentAndNext", "setCurrentViewed"])
        #expect(scripting.calls.first { $0.function == "setCurrentViewed" }?.args.first as? Bool == false)
        #expect(scripting.calls.first { $0.function == "stepFile" }?.args.first as? Int == 1)
        #expect(s.busy == false)
        // Conversation has no file list: no pill. Another PR: cursor dropped.
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7"))
        await s.settle()
        #expect(!s.showsFilePill)
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/8/files"))
        await s.settle()
        #expect(s.currentFile == nil)
    }

    @Test func resultsAreTransientAndEmptyOnesNeverShow() async throws {
        let (s, gh, scripting, _) = await make(mine: [pr7])
        await gh.setPullRequestFiles([.success(filesEnvelope(total: 3, viewed: [true, false, false], next: nil)), .success(filesEnvelope(total: 3, viewed: [true, true, true], next: nil))])
        s.noticeLifetime = .milliseconds(30)
        scripting.results["mark"] = .success(["marked": 2, "failed": 0, "skipped": 0, "unknown": 0, "canUndo": true])
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7/files"))
        await s.settle()
        await s.mark()
        #expect(s.notice == .marked(count: 2, failed: 0, canUndo: true))
        try await Task.sleep(for: .milliseconds(120))
        #expect(s.notice == nil)
        scripting.results["mark"] = .success(["marked": 0, "failed": 0, "skipped": 0, "unknown": 0, "canUndo": false])
        await s.mark()
        #expect(s.notice == nil)
    }

    @Test func aNavigationDoesNotWaitForACallTheOldDocumentWillNeverAnswer() async {
        let (s, _, scripting, _) = await make(mine: [pr7])
        scripting.holds = ["counts"]                                      // the first document dies mid-call (a redirect)
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7/files"))
        try? await Task.sleep(for: .milliseconds(30))
        s.pageChanged(to: URL(string: "https://github.com/acme/web/pull/7/changes"))   // the document GitHub redirected to
        await s.settle()
        #expect(scripting.calls.filter { $0.function == "setSettings" }.count == 2)
        #expect(s.pageCounts?.total == 3)
    }

    @Test func reviewShortcutsNeedPageFocusAndNoModal() {
        #expect(ReviewWindowController.handlesReviewShortcut(focusInWebView: true, modalPresented: false, editingInPage: false))
        #expect(!ReviewWindowController.handlesReviewShortcut(focusInWebView: false, modalPresented: false, editingInPage: false))
        #expect(!ReviewWindowController.handlesReviewShortcut(focusInWebView: true, modalPresented: true, editingInPage: false))
        // A GitHub textarea keeps ⇧⌘V (Paste and Match Style) and ⌘K (insert link).
        #expect(!ReviewWindowController.handlesReviewShortcut(focusInWebView: true, modalPresented: false, editingInPage: true))
    }

    @Test func fileStepIsCommandJAndKAndTheArrowsStayThePages() {
        #expect(ReviewWindowController.fileStep(flags: .command, key: "j") == 1)
        #expect(ReviewWindowController.fileStep(flags: .command, key: "k") == -1)
        // ⌘↓ and ⌘↑ are the page's scroll to the end and to the top, as in any browser: never taken.
        #expect(ReviewWindowController.fileStep(flags: .command, key: "\u{F701}") == nil)
        #expect(ReviewWindowController.fileStep(flags: [.command, .function], key: "\u{F700}") == nil)
        #expect(ReviewWindowController.fileStep(flags: [.command, .shift], key: "J") == nil)
        #expect(ReviewWindowController.fileStep(flags: [], key: "j") == nil)
    }

    @Test func browserKeysAreCommandArrowsForHistoryAndCommandEForTheSelection() {
        #expect(ReviewWindowController.browserKey(flags: .command, key: "\u{F702}") == .back)
        #expect(ReviewWindowController.browserKey(flags: [.command, .function, .numericPad], key: "\u{F703}") == .forward)
        #expect(ReviewWindowController.browserKey(flags: .command, key: "e") == .useSelectionForFind)
        #expect(ReviewWindowController.browserKey(flags: [], key: "\u{F702}") == nil)
        #expect(ReviewWindowController.browserKey(flags: [.command, .shift], key: "\u{F702}") == nil)
        #expect(ReviewWindowController.browserKey(flags: [.command, .shift], key: "E") == nil)
    }

    @Test func escapeDismissesTheModalThenTheFindBarThenStopsALoad() {
        #expect(ReviewWindowController.escapeAction(modalPresented: true, findShown: true, isLoading: true) == .dismissModal)
        #expect(ReviewWindowController.escapeAction(modalPresented: false, findShown: true, isLoading: true) == .hideFind)
        #expect(ReviewWindowController.escapeAction(modalPresented: false, findShown: false, isLoading: true) == .stop)
        #expect(ReviewWindowController.escapeAction(modalPresented: false, findShown: false, isLoading: false) == nil)
    }
}
