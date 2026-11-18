import AppKit
import WebKit

/// `Pullglance --review-bench <url> [--steps a,b,c] [--out directory] [--keep]`: the Review Desk without the
/// popover, for working on it from a terminal. The app opens the Desk on the address, runs the steps in
/// order, writes what each one left behind (the session's state as JSON, a picture of the window) and exits
/// with 0 when every step went through. The popover only opens on a real click, and the Desk only opens
/// from the popover; this is the way in for a person or an agent that has neither.
///
/// Meant for `swift run`, whose identity is the debug one: its own defaults and its own GitHub session, so
/// nothing here touches the installed app's. Sign in once with `--review-bench https://github.com/login
/// --keep`. Marking is real: point it at pull requests made for it.
///
/// Steps, comma-separated (default `wait,state,shot`):
/// - `wait` or `wait:45`: until the page has loaded and, where there is a review bar, the script has counted
///   the files; the number is the limit in seconds.
/// - `state`: the session as JSON. `shot`: the window as PNG. `inspect`: the script's structural summary.
/// - `skip`, `undo`, `unmark-all`, `mark-current`, `unmark-current`, `refresh`, `reload`.
/// - `next`, `prev` (any file), `next-unviewed`, `prev-unviewed`.
/// - `choose:auto`, `choose:custom`, `choose:<preset id>`: the Skip menu.
/// - `preset:<id>=on|off`, `globs:<glob>;<glob>`: the rules in Settings.
/// - `open:<url>`, `sleep:<milliseconds>`.
struct ReviewBenchOptions: Equatable {
    static let flag = "--review-bench"
    static let defaultDirectory = FileManager.default.temporaryDirectory.appending(path: "pullglance-review-bench", directoryHint: .isDirectory)
    static let defaultSteps = ["wait", "state", "shot"]

    var url: URL
    var steps = defaultSteps
    var directory = defaultDirectory
    /// Leave the window up after the steps, until it is closed by hand: signing in, looking around.
    var keep = false

    static func parse(_ arguments: [String]) -> ReviewBenchOptions? {
        guard let index = arguments.firstIndex(of: flag), let address = arguments.dropFirst(index + 1).first,
              let url = URL(string: address), url.scheme != nil else { return nil }
        var options = ReviewBenchOptions(url: url)
        func value(after name: String) -> String? {
            arguments.firstIndex(of: name).flatMap { arguments.dropFirst($0 + 1).first }.flatMap { $0.hasPrefix("--") ? nil : $0 }
        }
        if let steps = value(after: "--steps") {
            options.steps = steps.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if let out = value(after: "--out") { options.directory = URL(fileURLWithPath: out, isDirectory: true) }
        options.keep = arguments.contains("--keep")
        return options
    }

    /// `name` and what follows the first colon, so an address keeps its own colons.
    static func split(_ step: String) -> (name: String, argument: String?) {
        guard let colon = step.firstIndex(of: ":") else { return (step, nil) }
        return (String(step[..<colon]), String(step[step.index(after: colon)...]))
    }
}

@MainActor
enum ReviewBench {
    struct StepFailure: Error { let message: String }

    /// The installed app's identity holds the user's real GitHub session and review marks; the bench stays out.
    static var refusesThisIdentity: Bool { Bundle.main.bundleIdentifier == "com.andersonba.pullglance" }

    /// Runs the steps and returns whether all of them went through. Files land in `options.directory`.
    static func run(_ options: ReviewBenchOptions, store: PRStore) async -> Bool {
        try? FileManager.default.createDirectory(at: options.directory, withIntermediateDirectories: true)
        AppLog.shared.isVerbose = true
        ReviewWindowController.configure(store: store)
        guard let desk = ReviewWindowController.shared else { return false }
        // The pull request's state on the bar comes from the store's lists; one fetch, no polling.
        Task { await store.refresh() }
        desk.open(url: options.url)
        var report: [[String: Any]] = []
        var allPassed = true
        for (index, step) in options.steps.enumerated() {
            let label = String(format: "%02d-%@", index + 1, ReviewBenchOptions.split(step).name)
            let started = Date()
            var entry: [String: Any] = ["step": step]
            do {
                if let wrote = try await perform(step, label: label, desk: desk, directory: options.directory) { entry["file"] = wrote.lastPathComponent }
                entry["ok"] = true
            } catch let failure as StepFailure {
                entry["ok"] = false; entry["error"] = failure.message; allPassed = false
            } catch {
                entry["ok"] = false; entry["error"] = String(describing: error); allPassed = false
            }
            entry["ms"] = Int(Date().timeIntervalSince(started) * 1000)
            entry["after"] = brief(desk)
            report.append(entry)
            print("\(entry["ok"] as? Bool == true ? "ok  " : "FAIL") \(label) \(entry["ms"] ?? 0)ms \(entry["error"] ?? entry["file"] ?? "")")
        }
        write(["url": options.url.absoluteString, "passed": allPassed, "steps": report], to: options.directory.appending(path: "report.json"))
        print("report: \(options.directory.appending(path: "report.json").path)")
        print("log: \(AppLog.shared.fileURL.path)")
        return allPassed
    }

    private static func perform(_ step: String, label: String, desk: ReviewWindowController, directory: URL) async throws -> URL? {
        let (name, argument) = ReviewBenchOptions.split(step)
        let session = desk.session
        let noticeBefore = session.notice
        switch name {
        case "wait":
            try await wait(desk, limit: argument.flatMap(Double.init) ?? 30)
        case "state":
            let file = directory.appending(path: "\(label).json")
            write(await state(desk), to: file)
            return file
        case "inspect":
            let file = directory.appending(path: "\(label).json")
            write((try? await desk.host.bridge.call("inspect", ["args": []])) ?? ["error": "inspect failed"], to: file)
            return file
        case "shot":
            guard let png = await desk.picture() else { throw StepFailure(message: "no picture") }
            let file = directory.appending(path: "\(label).png")
            try png.write(to: file)
            return file
        case "skip": await session.mark()
        case "undo": await session.undo()
        case "unmark-all": await session.unmarkAll()
        case "mark-current": await session.markCurrentAndNext()
        case "unmark-current": await session.unmarkCurrent()
        case "refresh": await session.refresh()
        case "reload":
            desk.host.webView.reload()
            try await Task.sleep(for: .milliseconds(300))
        case "next": await session.stepFile(1)
        case "prev": await session.stepFile(-1)
        case "next-unviewed": await session.stepUnviewed(1)
        case "prev-unviewed": await session.stepUnviewed(-1)
        case "choose":
            switch argument {
            case "auto"?: session.choose(.auto)
            case "custom"?: session.choose(.custom)
            case let id?: session.choose(.preset(id))
            case nil: throw StepFailure(message: "choose needs auto, custom or a preset id")
            }
            await session.settle()
        case "preset":
            let parts = (argument ?? "").split(separator: "=").map(String.init)
            guard parts.count == 2, ReviewPresets.all.contains(where: { $0.id == parts[0] }), ["on", "off"].contains(parts[1]) else {
                throw StepFailure(message: "preset needs <id>=on|off; ids: \(ReviewPresets.all.map(\.id).joined(separator: " "))")
            }
            ReviewSettingsStore.shared.settings.presets[parts[0]] = parts[1] == "on"
            await session.settle()
        case "globs":
            ReviewSettingsStore.shared.settings.customGlobsText = (argument ?? "").split(separator: ";").joined(separator: "\n")
            await session.settle()
        case "open":
            guard let url = argument.flatMap(URL.init(string:)) else { throw StepFailure(message: "open needs an address") }
            desk.open(url: url)
            try await Task.sleep(for: .milliseconds(300))
        case "sleep":
            try await Task.sleep(for: .milliseconds(argument.flatMap(Int.init) ?? 500))
        default:
            throw StepFailure(message: "unknown step")
        }
        // An action answers with a notice; a failure is the step's failure. One left by an earlier step is not.
        if case .error(let message) = session.notice, session.notice != noticeBefore { throw StepFailure(message: "notice: \(message)") }
        return nil
    }

    /// Loaded, and where the page has a review bar, counted by the script and idle.
    private static func wait(_ desk: ReviewWindowController, limit: Double) async throws {
        let deadline = Date().addingTimeInterval(limit)
        while Date() < deadline {
            let session = desk.session
            let loaded = !desk.host.isParked && !desk.host.webView.isLoading && desk.host.webView.url != nil
            if loaded, !session.page.showsBar || (session.pageCounts != nil && !session.busy) {
                await session.settle()
                return
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw StepFailure(message: "not ready after \(Int(limit))s: loading=\(desk.host.webView.isLoading) counts=\(desk.session.pageCounts != nil) busy=\(desk.session.busy)")
    }

    /// The few facts worth having after every step, in the report.
    private static func brief(_ desk: ReviewWindowController) -> [String: Any] {
        let session = desk.session
        var brief: [String: Any] = ["matching": session.matchCount, "busy": session.busy]
        if let counts = session.pageCounts { brief["viewed"] = counts.viewed; brief["total"] = counts.total }
        if let left = session.unviewedLeft { brief["left"] = left }
        if let file = session.currentFile { brief["file"] = file.path; brief["fileViewed"] = file.viewed }
        if let notice = session.notice { brief["notice"] = String(describing: notice) }
        return brief
    }

    private static func state(_ desk: ReviewWindowController) async -> [String: Any] {
        let session = desk.session, web = desk.host.webView
        var state: [String: Any] = [
            "url": web.url?.absoluteString ?? "", "loading": web.isLoading, "parked": desk.host.isParked,
            "page": String(describing: session.page), "showsBar": session.showsBar, "showsFilePill": session.showsFilePill,
            "busy": session.busy, "matching": session.matchCount, "choice": String(describing: session.presetChoice),
            "knowsPullRequest": session.pullRequest != nil, "editingInPage": session.isEditingInPage,
        ]
        if let counts = session.pageCounts {
            state["pageCounts"] = ["total": counts.total, "viewed": counts.viewed, "matching": counts.matching, "enabled": counts.enabled,
                                   "partial": counts.partial, "perRule": counts.perRule.filter { $0.value > 0 }] as [String: Any]
        }
        if let counts = session.fileCounts { state["fileCounts"] = String(describing: counts) }
        if let left = session.unviewedLeft { state["unviewedLeft"] = left }
        if let file = session.currentFile {
            state["currentFile"] = ["path": file.path, "index": file.index, "total": file.total, "viewed": file.viewed] as [String: Any]
        }
        if let notice = session.notice { state["notice"] = String(describing: notice) }
        // Whether GitHub has a session here; marking needs one. Only the fact, not the login.
        let login = try? await web.evaluateJavaScript("document.querySelector('meta[name=\"user-login\"]')?.content || ''") as? String
        state["signedIn"] = !(login ?? "").isEmpty
        let presets = ReviewSettingsStore.shared.settings.presets
        state["presetsOn"] = ReviewPresets.all.filter { presets[$0.id] ?? $0.enabled }.map(\.id)
        state["customGlobs"] = ReviewSettingsStore.shared.settings.customGlobs
        return state
    }

    private static func write(_ object: Any, to file: URL) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return }
        try? data.write(to: file)
    }
}
