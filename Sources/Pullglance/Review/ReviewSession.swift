import Foundation
import Observation

enum ScrollDirection: String { case next, previous }

/// What the review bar shows and does for the page in the window. Page data comes from the URL and the
/// script; pull request data from the store; viewed/total from GraphQL; actions from the script and the store.
@Observable
@MainActor
final class ReviewSession {
    enum Notice: Equatable {
        case loading
        case marked(count: Int, failed: Int, canUndo: Bool)
        case undone(count: Int)
        case error(String)
    }
    struct PageCounts: Equatable {
        var total: Int
        var viewed: Int
        var matching: Int
        var partial: Bool
        var perRule: [String: Int]
    }

    /// Settings edits arrive per keystroke; one push after this pause.
    static let settingsPushDelay: Duration = .milliseconds(300)

    let store: PRStore
    @ObservationIgnored private let client: GHRunning
    @ObservationIgnored private let scripting: ReviewScripting
    @ObservationIgnored private let settingsStore: ReviewSettingsStore
    @ObservationIgnored private let defaults: UserDefaults
    /// Bumped whenever the page needs `setSettings` again (new document, edited settings). A push records the
    /// epoch it started in only if no reset happened while it was awaiting, so a late push can't hide a newer reset.
    @ObservationIgnored private var settingsEpoch = 0
    @ObservationIgnored private var pushedEpoch = -1
    private var needsSettingsPush: Bool { pushedEpoch != settingsEpoch }
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    @ObservationIgnored private var pendingSettingsPush: Task<Void, Never>?
    /// Bumped whenever the pull request under the bar may change; a GraphQL answer for an older value is dropped.
    @ObservationIgnored private var generation = 0
    /// Bumped only when the page moves to another pull request. A GraphQL file-count answer is kept while this
    /// holds: reloads of the same document (URL KVO, then didFinish) bump `generation` but not this.
    @ObservationIgnored private var countsEpoch = 0
    /// `repo#number` whose file counts are being fetched; a second report of the same page does not refetch.
    @ObservationIgnored private var countsInFlightFor: String?
    /// `repo#number` of pull requests auto-marked in this app run; auto-mark happens once per pull request.
    @ObservationIgnored private var autoMarked: Set<String> = []

    private(set) var page: ReviewPage = .other
    /// The store's pull request for the page, read live: the store is observable, so the bar follows its cycles.
    var pullRequest: PullRequest? { storedPullRequest(for: page) }
    private(set) var fileCounts: FileCounts?
    private(set) var pageCounts: PageCounts?
    private(set) var busy = false
    private(set) var notice: Notice?
    private(set) var presetChoice: ReviewPresetChoice = .auto
    /// The caret is in a page field (textarea, input, contenteditable): review shortcuts leave the keys to it.
    private(set) var isEditingInPage = false
    var isBarHidden: Bool { didSet { defaults.set(isBarHidden, forKey: "reviewBarHidden") } }

    var showsBar: Bool { page.showsBar && !isBarHidden }
    /// Files matching the current choice, from the page; what the Mark button shows.
    var matchCount: Int { pageCounts?.matching ?? 0 }

    init(store: PRStore, client: GHRunning, scripting: ReviewScripting, settings: ReviewSettingsStore, defaults: UserDefaults) {
        self.store = store
        self.client = client
        self.scripting = scripting
        self.settingsStore = settings
        self.defaults = defaults
        isBarHidden = defaults.bool(forKey: "reviewBarHidden")
        settings.onChange = { [weak self] _ in self?.scheduleSettingsPush() }
    }

    // MARK: page

    func pageChanged(to url: URL?) {
        let newPage = ReviewPage.classify(url)
        let samePR: Bool = {
            if case .pullRequest(let r1, let n1, _) = newPage, case .pullRequest(let r2, let n2, _) = page { return r1 == r2 && n1 == n2 }
            return newPage == page
        }()
        page = newPage
        if let repo = newPage.repo { presetChoice = ReviewPresetChoice.load(defaults, repo: repo) }
        // Another page: the old document's focused field is gone with it (its focusout may never arrive).
        if !samePR { notice = nil; fileCounts = nil; pageCounts = nil; countsEpoch += 1 }
        // Every load reinstalls the script, and a fresh document only posts `editing` on a change: a reload
        // while typing would otherwise leave the flag stuck and the review shortcuts dead.
        isEditingInPage = false
        // A full load restarts the script, which needs setSettings before anything else; it is idempotent.
        settingsEpoch += 1
        generation += 1
        guard newPage.showsBar else { inFlight?.cancel(); inFlight = nil; return }
        let gen = generation
        let previous = inFlight
        inFlight = Task { [weak self] in
            await previous?.value
            guard let self, gen == self.generation else { return }
            await self.pushSettingsAndCount()
            if case .pullRequest(let repo, let number, _) = newPage,
               !samePR || (self.fileCounts == nil && self.countsInFlightFor != "\(repo)#\(number)") {
                await self.refreshFileCounts()
            }
            await self.autoMarkIfNeeded(generation: gen)
        }
    }

    func scriptEvent(_ name: String, _ payload: Any?) {
        switch name {
        case "context":
            // The page moved under us (Turbo). A new diff means undo no longer applies.
            if let dict = payload as? [String: Any], let base = dict["basePath"] as? String, base != currentBasePath { notice = nil }
        case "editing":
            if let dict = payload as? [String: Any], let active = dict["active"] as? Bool { isEditingInPage = active }
        case "listing":
            let gen = generation
            track { await $0.recount(); await $0.autoMarkIfNeeded(generation: gen) }
        default: break
        }
    }

    private var currentBasePath: String? {
        switch page {
        case .pullRequest(let repo, let number, _): "/\(repo)/pull/\(number)"
        case .compare(let repo, let range): "/\(repo)/compare/\(range)"
        case .other: nil
        }
    }

    private func storedPullRequest(for page: ReviewPage) -> PullRequest? {
        guard case .pullRequest(let repo, let number, _) = page else { return nil }
        return (store.mine.value + store.direct.value + (store.viaTeam?.value ?? [])).first { $0.repo == repo && $0.number == number }
    }

    /// Runs `work` after whatever is in flight, and makes it what `settle()` waits for.
    private func track(_ work: @escaping @MainActor (ReviewSession) async -> Void) {
        let previous = inFlight
        inFlight = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await work(self)
        }
    }

    /// Settings › Review "Mark automatically": once the Files tab of a pull request has matching files, mark them,
    /// once per pull request per app run (a later visit respects what the user unmarked).
    private func autoMarkIfNeeded(generation gen: Int) async {
        guard gen == generation, settingsStore.settings.autoMark, matchCount > 0, !busy,
              case .pullRequest(let repo, let number, .files) = page else { return }
        guard autoMarked.insert("\(repo)#\(number)").inserted else { return }
        await mark()
    }

    // MARK: counts

    private func scheduleSettingsPush() {
        settingsEpoch += 1
        pendingSettingsPush?.cancel()
        pendingSettingsPush = Task { [weak self] in
            try? await Task.sleep(for: Self.settingsPushDelay)
            guard !Task.isCancelled, let self else { return }
            self.track { await $0.pushSettingsAndCount() }
        }
    }

    private func pushSettingsAndCount() async {
        guard page.showsBar else { return }
        try? await ensureSettingsPushed()
        await recount()
    }

    /// The page script ignores everything until `setSettings`; every script call goes through here first.
    /// Pushes again if a reset happened while a push was awaiting.
    private func ensureSettingsPushed() async throws {
        while needsSettingsPush {
            let epoch = settingsEpoch
            _ = try await scripting.call("setSettings", ["args": [settingsStore.settings.scriptPayload]])
            if epoch == settingsEpoch { pushedEpoch = epoch }
        }
    }

    /// The script takes `null` for "the rules as configured".
    private func ruleArgument(_ ids: [String]?) -> Any { ids.map { $0 as Any } ?? NSNull() }

    private func recount() async {
        guard page.showsBar, !needsSettingsPush else { return }
        let ids = ruleIDs(for: presetChoice, settings: settingsStore.settings)
        guard let raw = try? await scripting.call("counts", ["args": [ruleArgument(ids)]]) as? [String: Any] else { return }
        pageCounts = PageCounts(total: raw["total"] as? Int ?? 0, viewed: raw["viewed"] as? Int ?? 0, matching: raw["matching"] as? Int ?? 0,
                                partial: raw["partial"] as? Bool ?? false, perRule: raw["perRule"] as? [String: Int] ?? [:])
    }

    /// The answer is kept unless the page moved to another pull request meanwhile.
    private func refreshFileCounts() async {
        guard case .pullRequest(let repo, let number, _) = page, let ref = PullRequestRef(repo: repo, number: number) else { return }
        let key = "\(repo)#\(number)", epoch = countsEpoch
        countsInFlightFor = key
        let counts = await fetchFileCounts(client, ref: ref)
        if countsInFlightFor == key { countsInFlightFor = nil }
        guard epoch == countsEpoch else { return }
        fileCounts = counts
    }

    func refresh() async {
        let gen = generation
        await pushSettingsAndCount()
        if case .pullRequest = page {
            await refreshFileCounts()
            if let pullRequest, gen == generation { _ = await store.refreshOne(pullRequest, quiet: true) }
        }
    }

    /// Test hook: wait for the work `pageChanged` (and anything chained after it) started.
    func settle() async {
        while let task = inFlight {
            await task.value
            if inFlight == task { break }
        }
    }

    // MARK: actions

    func choose(_ choice: ReviewPresetChoice) {
        presetChoice = choice
        if let repo = page.repo { choice.save(defaults, repo: repo) }
        track { await $0.recount() }
    }

    func mark() async {
        await perform { [self] in
            let ids = ruleIDs(for: presetChoice, settings: settingsStore.settings)
            let raw = try await scripting.call("mark", ["args": [ruleArgument(ids)]]) as? [String: Any] ?? [:]
            return .marked(count: raw["marked"] as? Int ?? 0, failed: raw["failed"] as? Int ?? 0, canUndo: raw["canUndo"] as? Bool ?? false)
        }
    }

    func undo() async {
        // Only a marking the page can undo; otherwise the script would throw and the bar blame the page.
        guard case .marked(_, _, canUndo: true) = notice else { return }
        await perform { [self] in
            let raw = try await scripting.call("undo", ["args": []]) as? [String: Any] ?? [:]
            return .undone(count: raw["marked"] as? Int ?? 0)
        }
    }

    func unmarkAll() async {
        await perform { [self] in
            let raw = try await scripting.call("unmarkAll", ["args": []]) as? [String: Any] ?? [:]
            return .undone(count: raw["marked"] as? Int ?? 0)
        }
    }

    /// The outcome of a pull request action taken from the window (merge, approve, comment): a failure shows in the bar,
    /// success stays quiet; either way the review state is refreshed.
    func report(_ result: ActionResult) async {
        if case .failure(let message) = result { notice = .error(message) }
        await refresh()
    }

    func scroll(_ direction: ScrollDirection) async {
        guard (try? await ensureSettingsPushed()) != nil else { return }
        _ = try? await scripting.call("scrollToUnviewed", ["args": [direction.rawValue]])
    }

    private func perform(_ action: @MainActor () async throws -> Notice) async {
        guard !busy else { return }
        busy = true
        notice = .loading
        // A context change clears the notice; a result for the old diff then stays unshown.
        do {
            try await ensureSettingsPushed()
            let result = try await action()
            if notice == .loading { notice = result }
        } catch {
            if notice == .loading { notice = .error(String(localized: "The page did not respond. Reload and try again.", bundle: .app)) }
            AppLog.shared.info("review action failed: \(type(of: error))")
        }
        busy = false
        await recount()
        await refreshFileCounts()
    }
}
