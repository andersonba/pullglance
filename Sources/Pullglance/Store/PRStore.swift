import Foundation
import Observation
import SwiftUI
import os

enum SearchQuery {
    static let suffix = "archived:false sort:updated-desc"
    static let mine = "is:pr is:open author:@me \(suffix)"
    static let direct = "is:pr is:open user-review-requested:@me \(suffix)"
    /// Team requests only: the direct ones are already in `direct`, and leaving them out here is what
    /// makes `issueCount` the number the section header should show.
    static let viaTeam = "is:pr is:open review-requested:@me -user-review-requested:@me \(suffix)"

    static func mine(hiding owners: Set<String>, repos: Set<String> = []) -> String { mine + exclusions(owners, repos) }
    static func direct(hiding owners: Set<String>, repos: Set<String> = []) -> String { direct + exclusions(owners, repos) }
    static func viaTeam(hiding owners: Set<String>, repos: Set<String> = []) -> String { viaTeam + exclusions(owners, repos) }

    /// `-user:` works for organizations and personal accounts alike; `-repo:` for single repositories.
    /// Several of them AND together.
    private static func exclusions(_ owners: Set<String>, _ repos: Set<String>) -> String {
        owners.sorted().map { " -user:\($0)" }.joined() + repos.sorted().map { " -repo:\($0)" }.joined()
    }
}

/// How one owner's repositories are filtered. Only the user's choice is stored; nothing derived from results.
enum RepoMode: String, Sendable, Equatable, Codable {
    /// Everything but `repos`. Applied in the search as `-repo:`; new repositories show up.
    case allExcept
    /// Nothing but `repos`. Applied in the app after the search; new repositories stay out.
    case only
}

struct RepoRule: Equatable, Sendable, Codable {
    var mode: RepoMode = .allExcept
    var repos: Set<String> = []
    static let none = RepoRule()
}

/// A repository present in the loaded results, with its count.
struct RepoInfo: Equatable, Identifiable, Sendable {
    let fullName: String
    let openCount: Int
    var id: String { fullName }
    var name: String { fullName.split(separator: "/").last.map(String.init) ?? fullName }
}

/// An organization or account that can own pull requests shown by the app.
struct OwnerInfo: Equatable, Identifiable, Sendable {
    let login: String
    let isViewer: Bool
    /// Open PRs currently loaded for this owner; nil when hidden (nothing is fetched for it).
    let openCount: Int?
    let rule: RepoRule
    var id: String { login }
}

@Observable
@MainActor
final class PRStore {
    static let expandedKey = "viaTeamExpanded"
    static let intervalKey = "refreshIntervalSeconds"
    static let hiddenOwnersKey = "hiddenOwners"
    static let repoRulesKey = "repoRules"
    static let dormantKey = "dormant"
    static let manualOrdersKey = "manualOrders"
    static let verboseLoggingKey = "verboseLogging"
    static let hiddenSectionsKey = "hiddenSections"
    static let badgeSectionsKey = "badgeSections"
    static let dualBadgeFirstKey = "dualBadgeFirst"
    static let dualBadgeSecondKey = "dualBadgeSecond"
    static let badgeModeKey = "badgeMode"
    static let sectionOrderKey = "sectionOrder"

    private(set) var mine = Snapshot<[PullRequest]>(value: [], total: 0, fetchedAt: nil)
    private(set) var direct = Snapshot<[PullRequest]>(value: [], total: 0, fetchedAt: nil)
    /// nil until the "Via team" section is expanded for the first time.
    private(set) var viaTeam: Snapshot<[PullRequest]>? = nil
    private(set) var isLoadingViaTeam = false
    /// Error of the last team fetch, nil after a successful one. Lets the section show "Try again" instead of a spinner.
    private(set) var viaTeamError: ErrorKind? = nil
    private(set) var phase: Phase = .idle
    /// Error of the last finished cycle, nil after a fully successful one. Survives the next `.loading`
    /// so the error screen and the warning glyph do not flicker away on every refresh.
    private(set) var lastError: ErrorKind? = nil
    /// nil until the first fully successful refresh; kept on later failures.
    private(set) var badgeCount: Int? = nil
    /// The second number in dual mode; nil in single mode or before the first successful refresh.
    private(set) var badgeSecondCount: Int? = nil

    /// What the menu bar shows next to the icon, once there is data.
    var badgeText: String? {
        guard let badgeCount else { return nil }
        return Pullglance.badgeText(first: badgeCount, second: badgeSecondCount, mode: badgeMode)
    }
    private(set) var viewerLogin: String? = nil
    private(set) var viewerOrganizations: [String] = []
    /// Snoozed PRs by id, with the state they had when snoozed. Stored per machine.
    /// Hand-made row orders, by section raw value; see `applyManualOrder`.
    private(set) var manualOrders: [String: [String]] {
        didSet { defaults.set(try? JSONEncoder().encode(manualOrders), forKey: Self.manualOrdersKey) }
    }

    func isManuallyOrdered(_ section: Section) -> Bool { manualOrders[section.rawValue] != nil }

    func setManualOrder(_ ids: [String], for section: Section) {
        manualOrders[section.rawValue] = ids.isEmpty ? nil : ids
    }

    /// Back to newest first.
    func resetManualOrder(for section: Section) {
        manualOrders[section.rawValue] = nil
    }

    private func manuallyOrdered(_ prs: [PullRequest], _ section: Section) -> [PullRequest] {
        applyManualOrder(prs, ids: manualOrders[section.rawValue] ?? [])
    }

    private(set) var dormant: [String: DormantMark] {
        didSet {
            guard dormant != oldValue else { return }
            defaults.set(try? JSONEncoder().encode(dormant), forKey: Self.dormantKey)
            recomputeBadge()
        }
    }
    private var dormantIDs: Set<String> { Set(dormant.keys) }

    /// Per-PR action state, so a row can show its own spinner, "merged", or a failure.
    private(set) var actionStates: [String: ActionState] = [:]
    /// How long a merged PR stays visible as "Merged" before leaving the list.
    private let successLinger: Duration

    /// True while a cycle triggered by a settings change (owners, repository rules) is running, so the UI
    /// can show that the change is being applied rather than silently waiting for the search.
    private(set) var isApplyingSettingsChange = false
    private var applyingCount = 0

    /// When the timer will run the next cycle; nil before the first one completes.
    private(set) var nextRefreshAt: Date? = nil
    /// Newest first, capped at `failureLogLimit`. In memory only.
    private(set) var failureLog: [LogEntry] = []
    static let failureLogLimit = 100

    /// Owners excluded from every search, and therefore from both tabs and the badge. Stored per machine.
    var hiddenOwners: Set<String> {
        didSet {
            guard hiddenOwners != oldValue else { return }
            appLog.info("hidden owners: \(hiddenOwners.count)")
            defaults.set(hiddenOwners.sorted(), forKey: Self.hiddenOwnersKey)
            viaTeam = nil
            viaTeamError = nil
            Task { await refreshForSettingsChange() }
        }
    }

    /// Per-owner repository rules ("owner" → rule). Absent means "all except nothing". Stored per machine.
    private(set) var repoRules: [String: RepoRule] {
        didSet {
            guard repoRules != oldValue else { return }
            defaults.set(try? JSONEncoder().encode(repoRules), forKey: Self.repoRulesKey)
            let exceptChanged = Self.excludedRepos(repoRules) != Self.excludedRepos(oldValue)
            if exceptChanged {
                viaTeam = nil
                viaTeamError = nil
                Task { await refreshForSettingsChange() }
            } else {
                recomputeBadge()
            }
        }
    }

    /// Repositories excluded in the searches: the "all except" rules.
    private static func excludedRepos(_ rules: [String: RepoRule]) -> Set<String> {
        rules.values.filter { $0.mode == .allExcept }.reduce(into: Set<String>()) { $0.formUnion($1.repos) }
    }
    private var excludedRepos: Set<String> { Self.excludedRepos(repoRules) }

    /// Session-only lens over the loaded lists: show only these repositories. Empty means no filter.
    /// Does not touch the badge; the tab numbers follow it.
    var quickRepoFilter: Set<String> = []

    /// Sections shown in the popover. Missing from defaults means all.
    /// Persisted as the hidden set, so a section added in a later version shows up for existing users.
    var visibleSections: Set<Section> {
        didSet { defaults.set(Set(Section.allCases).subtracting(visibleSections).map(\.rawValue).sorted(), forKey: Self.hiddenSectionsKey) }
    }

    /// Display order across both tabs. Each tab keeps its own relative order; see `orderedSections(_:)`.
    private(set) var sectionOrder: [Section] {
        didSet { defaults.set(sectionOrder.map(\.rawValue), forKey: Self.sectionOrderKey) }
    }

    /// Sections whose items add up to the menu bar number.
    var badgeSections: Set<Section> {
        didSet {
            defaults.set(badgeSections.map(\.rawValue).sorted(), forKey: Self.badgeSectionsKey)
            recomputeBadge()
            if wantsTeamFetch, viaTeam == nil, !isLoadingViaTeam {
                Task { await refreshViaTeam() }
            }
        }
    }

    /// Tooltip for the menu bar item: which sections are behind each number.
    var badgeDescription: String? {
        guard let badgeCount else { return nil }
        let names = { (sections: Set<Section>) in
            self.sectionOrder.filter(sections.contains).map(\.title).joined(separator: ", ")
        }
        switch badgeMode {
        case .single: return "\(badgeCount) · \(names(badgeSections))"
        case .dual: return "\(badgeCount) · \(names(dualBadgeFirst))\n\(badgeSecondCount ?? 0) · \(names(dualBadgeSecond))"
        }
    }

    /// Dual mode has its own configuration, so switching modes brings back what each one had.
    /// `badgeSections` belongs to single mode; these two, disjoint, to dual mode.
    static let defaultDualFirst: Set<Section> = [.needsAction, .readyToMerge]
    static let defaultDualSecond: Set<Section> = [.needsYourReview]

    private(set) var dualBadgeFirst: Set<Section> {
        didSet { defaults.set(dualBadgeFirst.map(\.rawValue).sorted(), forKey: Self.dualBadgeFirstKey); badgeSetsChanged() }
    }

    private(set) var dualBadgeSecond: Set<Section> {
        didSet { defaults.set(dualBadgeSecond.map(\.rawValue).sorted(), forKey: Self.dualBadgeSecondKey); badgeSetsChanged() }
    }

    private func badgeSetsChanged() {
        recomputeBadge()
        if wantsTeamFetch, viaTeam == nil, !isLoadingViaTeam {
            Task { await refreshViaTeam() }
        }
    }

    var badgeMode: BadgeMode {
        didSet {
            defaults.set(badgeMode.rawValue, forKey: Self.badgeModeKey)
            badgeSetsChanged()
        }
    }

    /// Dual mode: which number a section counts toward.
    func badgeSlot(for section: Section) -> BadgeSlot? {
        if dualBadgeFirst.contains(section) { return .first }
        if dualBadgeSecond.contains(section) { return .second }
        return nil
    }

    /// Dual mode: moves a section to one number, the other, or out. A section never counts twice.
    func setBadgeSlot(_ slot: BadgeSlot?, for section: Section) {
        var first = dualBadgeFirst
        var second = dualBadgeSecond
        first.remove(section)
        second.remove(section)
        switch slot {
        case .first: first.insert(section)
        case .second: second.insert(section)
        case nil: break
        }
        if first != dualBadgeFirst { dualBadgeFirst = first }
        if second != dualBadgeSecond { dualBadgeSecond = second }
    }

    /// The sections counted right now, per the mode.
    private var countedSections: (first: Set<Section>, second: Set<Section>?) {
        badgeMode == .dual ? (dualBadgeFirst, dualBadgeSecond) : (badgeSections, nil)
    }

    /// The team search runs every cycle when the section is open or counted in the badge.
    private var wantsTeamFetch: Bool {
        let counted = countedSections
        return isViaTeamExpanded || counted.first.contains(.needsTeamsReview) || (counted.second?.contains(.needsTeamsReview) ?? false)
    }

    var isViaTeamExpanded: Bool {
        didSet {
            defaults.set(isViaTeamExpanded, forKey: Self.expandedKey)
            if isViaTeamExpanded, viaTeam == nil {
                Task { await refreshViaTeam() }
            }
        }
    }

    var refreshInterval: Duration {
        didSet {
            appLog.info("refresh interval \(refreshInterval.components.seconds) s")
            defaults.set(Int(refreshInterval.components.seconds), forKey: Self.intervalKey)
            if timerTask != nil { restartTimer() }
        }
    }

    private let client: any GHRunning
    /// The rolling file log; see `AppLog`.
    let appLog: AppLog

    /// DEBUG lines in the file log (gh commands and timings). Persisted; takes effect at once.
    var verboseLogging: Bool {
        didSet {
            defaults.set(verboseLogging, forKey: Self.verboseLoggingKey)
            appLog.isVerbose = verboseLogging
            appLog.info("verbose logging \(verboseLogging ? "on" : "off")")
            if verboseLogging, appLog === AppLog.shared { MainThreadWatchdog.shared.start() }
        }
    }

    /// Facts for a bug report. Asks gh for its version and login state; neither output is stored.
    func diagnosticsReport() async -> DiagnosticsReport {
        let version: String? = {
            if case .success(let data) = $0 { return String(decoding: data, as: UTF8.self).split(separator: "\n").first.map(String.init) }
            return nil
        }(await client.version())
        let authenticated: Bool? = {
            switch $0 {
            case .success: return true
            case .notAuthenticated: return false
            case .ghNotFound, .failure: return nil
            }
        }(await client.authStatus())
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return DiagnosticsReport(
            appVersion: AppInfo.version,
            macOSVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            ghVersion: version,
            ghAuthenticated: authenticated,
            refreshIntervalSeconds: Int(refreshInterval.components.seconds),
            badgeMode: badgeMode.rawValue,
            visibleSections: sectionOrder.filter(visibleSections.contains).map(\.rawValue),
            badgeSections: sectionOrder.filter((badgeMode == .dual ? dualBadgeFirst.union(dualBadgeSecond) : badgeSections).contains).map(\.rawValue),
            hiddenOwnerCount: hiddenOwners.count,
            repoRuleCount: repoRules.count,
            lastGoodDate: lastGoodDate,
            lastError: lastError.map { String(describing: $0) },
            failureCount: failureLog.count,
            verbose: verboseLogging
        )
    }
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: AppInfo.bundleID, category: "store")
    private var inFlight = false
    /// A refresh asked for while a cycle runs (manual, timer or a filter change) runs once the cycle ends.
    private var pendingRefresh = false
    private var timerTask: Task<Void, Never>?

    init(client: any GHRunning, defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { Date() }, successLinger: Duration = .seconds(1), log: AppLog = .shared, ciPollInterval: Duration = .seconds(20)) {
        self.client = client
        self.defaults = defaults
        self.now = now
        self.successLinger = successLinger
        self.ciPollInterval = ciPollInterval
        self.appLog = log
        let verbose = defaults.bool(forKey: Self.verboseLoggingKey)
        self.verboseLogging = verbose
        log.isVerbose = verbose
        if verbose, log === AppLog.shared { MainThreadWatchdog.shared.start() }
        self.isViaTeamExpanded = defaults.bool(forKey: Self.expandedKey)
        self.hiddenOwners = Set(defaults.stringArray(forKey: Self.hiddenOwnersKey) ?? [])
        var rules = (defaults.data(forKey: Self.repoRulesKey)).flatMap { try? JSONDecoder().decode([String: RepoRule].self, from: $0) } ?? [:]
        // Migration from the earlier flat deny list.
        if let legacy = defaults.stringArray(forKey: "hiddenRepos") {
            for repo in legacy {
                guard let owner = repo.split(separator: "/").first.map(String.init) else { continue }
                rules[owner, default: .none].repos.insert(repo)
            }
            defaults.removeObject(forKey: "hiddenRepos")
            defaults.removeObject(forKey: "seenRepos")
            defaults.set(try? JSONEncoder().encode(rules), forKey: Self.repoRulesKey)
        }
        self.repoRules = rules
        self.dormant = defaults.data(forKey: Self.dormantKey).flatMap { try? JSONDecoder().decode([String: DormantMark].self, from: $0) } ?? [:]
        self.manualOrders = defaults.data(forKey: Self.manualOrdersKey).flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
        if let legacyVisible = Self.sections(in: defaults, key: "visibleSections") {
            // Older builds stored the visible set, before the Snoozed sections existed; those must not come up hidden.
            let hidden = Set(Section.allCases).subtracting(legacyVisible).filter { !$0.isSnoozed }
            defaults.set(hidden.map(\.rawValue).sorted(), forKey: Self.hiddenSectionsKey)
            defaults.removeObject(forKey: "visibleSections")
        }
        self.visibleSections = Set(Section.allCases).subtracting(Self.sections(in: defaults, key: Self.hiddenSectionsKey) ?? [])
        self.badgeSections = Self.sections(in: defaults, key: Self.badgeSectionsKey) ?? Section.defaultBadge
        let dualFirst = Self.sections(in: defaults, key: Self.dualBadgeFirstKey) ?? Self.defaultDualFirst
        self.dualBadgeFirst = dualFirst
        self.dualBadgeSecond = (Self.sections(in: defaults, key: Self.dualBadgeSecondKey) ?? Self.defaultDualSecond).subtracting(dualFirst)
        self.badgeMode = defaults.string(forKey: Self.badgeModeKey).flatMap(BadgeMode.init(rawValue:)) ?? .single
        self.sectionOrder = Self.normalizedOrder(defaults.stringArray(forKey: Self.sectionOrderKey)?.compactMap(Section.init(rawValue:)) ?? [])
        let seconds = defaults.integer(forKey: Self.intervalKey)
        self.refreshInterval = .seconds(seconds > 0 ? seconds : 120)
    }

    /// Drops unknown entries, removes duplicates and appends any section missing from the stored order.
    private static func normalizedOrder(_ stored: [Section]) -> [Section] {
        var seen = Set<Section>()
        var order = stored.filter { seen.insert($0).inserted }
        order += Section.allCases.filter { !seen.contains($0) }
        return order
    }

    // MARK: Section order

    /// Work sections of a tab in display order. The snoozed section is not here: it is always rendered last.
    func orderedSections(_ tab: Section.Tab) -> [Section] {
        sectionOrder.filter { $0.tab == tab && !$0.isSnoozed }
    }


    /// Drag-and-drop semantics, as SwiftUI's `onMove` reports them.
    func moveSections(in tab: Section.Tab, from source: IndexSet, to destination: Int) {
        var tabOrder = orderedSections(tab)
        tabOrder.move(fromOffsets: source, toOffset: destination)
        apply(tabOrder: tabOrder, for: tab)
    }


    func resetSectionsToDefault() {
        sectionOrder = Section.allCases
        visibleSections = Set(Section.allCases)
        badgeMode = .single
        dualBadgeFirst = Self.defaultDualFirst
        dualBadgeSecond = Self.defaultDualSecond
        badgeSections = Section.defaultBadge
    }

    private func apply(tabOrder: [Section], for tab: Section.Tab) {
        var iterator = tabOrder.makeIterator()
        sectionOrder = sectionOrder.map { $0.tab == tab ? (iterator.next() ?? $0) : $0 }
    }

    private static func sections(in defaults: UserDefaults, key: String) -> Set<Section>? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return Set((defaults.stringArray(forKey: key) ?? []).compactMap(Section.init(rawValue:)))
    }

    // MARK: Derived state for the UI

    // MARK: Repository rules

    func repoRule(for owner: String) -> RepoRule { repoRules[owner] ?? .none }

    /// A rule without repositories is no rule at all: it falls back to "all repositories" in either mode.
    func setRule(_ rule: RepoRule, for owner: String) {
        appLog.info("repository rule for \(owner): \(rule.repos.isEmpty ? "all" : "\(rule.mode) \(rule.repos.count)")")
        repoRules[owner] = rule.repos.isEmpty ? nil : rule
    }

    func removeRepo(_ repo: String, from owner: String) {
        var rule = repoRule(for: owner)
        rule.repos.remove(repo)
        setRule(rule, for: owner)
    }

    /// Suggestions for the picker: the owner's repositories present in the loaded results, unfiltered.
    func recentRepos(for owner: String) -> [RepoInfo] {
        var counts: [String: Int] = [:]
        for pr in loadedPullRequests where pr.ownerLogin == owner { counts[pr.repo, default: 0] += 1 }
        return counts.keys.sorted().map { RepoInfo(fullName: $0, openCount: counts[$0] ?? 0) }
    }

    func searchRepos(owner: String, term: String) async -> RepoSearchResult? {
        guard case .success(let data) = await client.searchRepos(query: RepoSearchQuery.string(owner: owner, term: term)) else { return nil }
        return try? parseRepoSearch(data)
    }

    /// The "only" rules, applied to anything that reaches the screen or the badge.
    private func allowed(_ prs: [PullRequest]) -> [PullRequest] {
        let onlyRules = repoRules.filter { $0.value.mode == .only }
        guard !onlyRules.isEmpty else { return prs }
        return prs.filter { pr in
            guard let rule = onlyRules[pr.ownerLogin] else { return true }
            return rule.repos.contains(pr.repo)
        }
    }
    private var hasOnlyRules: Bool { repoRules.values.contains { $0.mode == .only } }

    /// "Only" rules plus the session quick filter: what the lists show.
    private func lens(_ prs: [PullRequest]) -> [PullRequest] {
        let base = allowed(prs)
        return quickRepoFilter.isEmpty ? base : base.filter { quickRepoFilter.contains($0.repo) }
    }

    var mineGroups: MineGroups {
        var groups = groupMine(lens(mine.value), dormant: dormantIDs)
        groups.needsAction = manuallyOrdered(groups.needsAction, .needsAction)
        groups.readyToMerge = manuallyOrdered(groups.readyToMerge, .readyToMerge)
        groups.waitingForReview = manuallyOrdered(groups.waitingForReview, .waitingForReview)
        groups.drafts = manuallyOrdered(groups.drafts, .drafts)
        return groups
    }
    var directList: [PullRequest] {
        manuallyOrdered(sortedByRecency(lens(direct.value)).filter { !dormantIDs.contains($0.id) }, .needsYourReview)
    }
    var viaTeamList: [PullRequest] {
        filterViaTeam(all: lens(viaTeam?.value ?? []), direct: direct.value, viewerLogin: viewerLogin).filter { !dormantIDs.contains($0.id) }
    }
    /// Snoozed review requests, direct and team, newest first.
    var snoozedReviewList: [PullRequest] {
        let team = filterViaTeam(all: lens(viaTeam?.value ?? []), direct: direct.value, viewerLogin: viewerLogin, limit: .max)
        return sortedByRecency((lens(direct.value) + team).filter { dormantIDs.contains($0.id) })
    }

    /// Where a PR would sit if it were not snoozed; shown on snoozed rows.
    func originSection(of pr: PullRequest) -> Section {
        if mine.value.contains(where: { $0.id == pr.id }) { return mineSection(for: pr) }
        if direct.value.contains(where: { $0.id == pr.id }) { return .needsYourReview }
        return .needsTeamsReview
    }

    // MARK: Dormancy

    func isDormant(_ pr: PullRequest) -> Bool { dormant[pr.id] != nil }

    // `dormant` is replaced wholesale rather than mutated in place: its didSet reads it back (badge), and an
    // in-place subscript write would overlap that read in an exclusivity violation.
    func snooze(_ pr: PullRequest) {
        appLog.info("snooze \(pr.id)")
        var marks = dormant
        marks[pr.id] = DormantMark(pr)
        dormant = marks
    }

    func wake(_ pr: PullRequest) {
        if dormant[pr.id] != nil { appLog.info("wake \(pr.id)") }
        var marks = dormant
        marks[pr.id] = nil
        dormant = marks
    }

    /// Called after every successful search: a snoozed PR with new activity wakes up by itself.
    private func wakeChanged(in prs: [PullRequest]) {
        var marks = dormant
        for pr in prs where marks[pr.id]?.shouldWake(for: pr) == true { marks[pr.id] = nil }
        dormant = marks
    }

    // MARK: Actions

    func actionState(for pr: PullRequest) -> ActionState? { actionStates[pr.id] }

    func clearActionState(for pr: PullRequest) {
        var states = actionStates
        states[pr.id] = nil
        actionStates = states
    }

    private func setActionState(_ state: ActionState?, for pr: PullRequest) {
        var states = actionStates
        states[pr.id] = state
        actionStates = states
    }

    /// Merges on GitHub, pinned to the commit we are showing. The row shows the progress: running, then
    /// "merged" for `successLinger` (already out of the badge), then it leaves the list; the next cycle confirms.
    /// Failures stay on the row until dismissed. They are not logged: they belong to the row, not to the Logs tab.
    func merge(_ listed: PullRequest, method: MergeMethod, deleteBranch: Bool) async -> ActionResult {
        setActionState(.running(.merge), for: listed)
        // Decided on what the modal showed: "merge now" never quietly becomes "merge later".
        let whenReady = listed.offersAutoMerge
        // Listed without merge fields (a review request): whether the base has a queue is unknown, and
        // guessing "no" is how the wrong mechanism gets used. One lookup settles it.
        var pr = listed
        if !listed.hasMergeState, let ref = PullRequestRef(repo: listed.repo, number: listed.number),
           case .success(let data) = await client.pullRequest(owner: ref.owner, name: ref.name, number: ref.number, includeMergeState: true),
           case .open(let fresh)? = try? parsePullRequestResponse(data) {
            replaceLocally(fresh)
            // The lookup settles the mechanism, never the commit: merging what the user did not see is what
            // --match-head-commit exists to prevent. The row now shows the newer head; a retry merges that.
            guard fresh.headRefOid == listed.headRefOid else {
                // Worded like gh's own refusal so the row and the modal classify it as "branch changed".
                let message = "Head branch was modified. Review and try the merge again."
                setActionState(.failed(.merge, message), for: listed)
                appLog.info("merge \(listed.id): refused, head moved between list and lookup")
                return .failure(message)
            }
            pr = fresh
        }
        var deleting = deleteBranch
        var note: String? = nil
        let result: ActionResult
        if pr.usesMergeQueue {
            // The queue refuses a strategy and merges (and deletes, if the repository does) on its own time.
            result = enqueueResult(await client.enqueue(pullRequestID: pr.nodeID, expectedHeadOid: pr.headRefOid))
            if case .success(let queueNote) = result { note = queueNote }
            appLog.info("enqueue \(pr.id): \(result.logDescription)")
        } else if whenReady {
            // GitHub merges by itself once the requirements pass; the branch, if deleted, is deleted by the
            // repository setting then. Nothing to check or delete here.
            result = ackResult(await client.enableAutoMerge(pullRequestID: pr.nodeID, method: method, expectedHeadOid: pr.headRefOid), field: "enablePullRequestAutoMerge")
            if case .success = result { note = String(localized: "Auto-merge on: GitHub merges it when the requirements pass", bundle: .app) }
            appLog.info("auto-merge on \(pr.id) \(method.ghFlag): \(result.logDescription)")
        } else {
            // Deleting a branch that other open pull requests are based on closes them (GitHub does not retarget
            // when the deletion comes right after the merge). Keep the branch in that case, or when unsure.
            if deleteBranch {
                switch await client.openPullRequests(repo: pr.repo, base: pr.headRefName) {
                case .success(let data):
                    let count = parseOpenPullRequestCount(data)
                    if count == nil || count! > 0 {
                        deleting = false
                        note = count.map { String(format: String(localized: "Branch kept: %lld open pull requests are based on it", bundle: .app), $0) }
                            ?? String(localized: "Branch kept: could not check for pull requests based on it", bundle: .app)
                    }
                default:
                    deleting = false
                    note = String(localized: "Branch kept: could not check for pull requests based on it", bundle: .app)
                }
            }
            result = outcomeResult(await client.merge(url: pr.url, method: method, deleteBranch: deleting, matchHeadCommit: pr.headRefOid))
            appLog.info("merge \(pr.id) \(method.ghFlag) delete-branch=\(deleting): \(result.logDescription)")
        }
        switch result {
        case .success:
            setActionState(.succeeded(.merge), for: pr)
            wake(pr)
            recomputeBadge()
            Task { [successLinger] in
                try? await Task.sleep(for: successLinger)
                if pr.usesMergeQueue || whenReady {
                    // Queued or scheduled is not merged: the row stays, and the lookup brings the state in for the pill.
                    clearActionState(for: pr)
                    _ = await refreshOne(pr, quiet: true)
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        removeLocally(pr)
                        clearActionState(for: pr)
                    }
                }
            }
            return .success(note: note)
        case .failure(let message):
            setActionState(.failed(.merge, message), for: pr)
        }
        return result
    }

    func comment(_ pr: PullRequest, body: String) async -> ActionResult {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(String(localized: "Empty comment", bundle: .app)) }
        setActionState(.running(.comment), for: pr)
        let result = outcomeResult(await client.comment(url: pr.url, body: trimmed))
        appLog.info("comment \(pr.id): \(result.logDescription)")
        setActionState(nil, for: pr)
        return result
    }

    /// An empty body approves without a comment.
    func approve(_ pr: PullRequest, body: String) async -> ActionResult {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        setActionState(.running(.approve), for: pr)
        let result = outcomeResult(await client.approve(url: pr.url, body: trimmed.isEmpty ? nil : trimmed))
        appLog.info("approve \(pr.id): \(result.logDescription)")
        setActionState(nil, for: pr)
        return result
    }

    /// GitHub's "Disable auto-merge". The row is read again so the pill and the menu follow.
    func disableAutoMerge(_ pr: PullRequest) async -> ActionResult {
        setActionState(.running(.disableAutoMerge), for: pr)
        let result = ackResult(await client.disableAutoMerge(pullRequestID: pr.nodeID), field: "disablePullRequestAutoMerge")
        appLog.info("auto-merge off \(pr.id): \(result.logDescription)")
        switch result {
        case .success:
            clearActionState(for: pr)
            _ = await refreshOne(pr, quiet: true)
        case .failure(let message):
            setActionState(.failed(.disableAutoMerge, message), for: pr)
        }
        return result
    }

    /// A mutation that only acknowledges, through the same envelope rules as `enqueueResult`.
    private func ackResult(_ outcome: GHOutcome, field: String) -> ActionResult {
        guard case .success(let data) = outcome else { return outcomeResult(outcome) }
        do {
            try parseMutationAck(data, field: field)
            return .success()
        } catch DecodingFailure.noData(let errors) where !errors.isEmpty {
            return .failure(errors.joined(separator: "; "))
        } catch {
            return .failure(String(localized: "GitHub returned an unexpected answer", bundle: .app))
        }
    }

    /// `gh api graphql` exits non-zero on GraphQL errors but still prints the envelope, so the note or the
    /// failure both come out of the decoder. The note names the position when GitHub gives one.
    private func enqueueResult(_ outcome: GHOutcome) -> ActionResult {
        guard case .success(let data) = outcome else { return outcomeResult(outcome) }
        do {
            let note = try parseEnqueueResponse(data).map { String(format: String(localized: "Added to the merge queue · position %lld", bundle: .app), $0) }
                ?? String(localized: "Added to the merge queue", bundle: .app)
            return .success(note: note)
        } catch DecodingFailure.noData(let errors) where !errors.isEmpty {
            return .failure(errors.joined(separator: "; "))
        } catch {
            return .failure(String(localized: "GitHub returned an unexpected answer", bundle: .app))
        }
    }

    private func outcomeResult(_ outcome: GHOutcome) -> ActionResult {
        switch outcome {
        case .success: .success()
        case .ghNotFound: .failure(String(localized: "gh CLI not found", bundle: .app))
        case .notAuthenticated: .failure(String(localized: "gh is not logged in to github.com", bundle: .app))
        case .failure(let message): .failure(message)
        }
    }

    /// Fetches this one pull request again and puts the answer in place: the row moves section if its
    /// state changed, leaves if it was merged or closed, and counts follow. Much cheaper than a full
    /// refresh, which is what makes it worth a menu item ("did CI finish yet?").
    /// `quiet` is the poller: no spinner, no failure on the row (just the log).
    func refreshOne(_ pr: PullRequest, quiet: Bool = false) async -> ActionResult {
        if !quiet { setActionState(.running(.refresh), for: pr) }
        let parts = pr.repo.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return fail(pr, "bad repository name", quiet: quiet) }
        // One pull request is cheap to compute merge state for (the page-size limit is what keeps it off the
        // review lists), and the review window merges review requests too.
        let outcome = await client.pullRequest(owner: parts[0], name: parts[1], number: pr.number, includeMergeState: true)
        switch outcome {
        case .success(let data):
            do {
                switch try parsePullRequestResponse(data) {
                case .open(let fresh):
                    replaceLocally(fresh)
                    wakeChanged(in: [fresh])
                    recomputeBadge()
                    appLog.info("refresh \(pr.id): ok")
                case .closed, .notFound:
                    appLog.info("refresh \(pr.id): gone")
                    withAnimation(.easeInOut(duration: 0.3)) { removeLocally(pr) }
                }
                if !quiet { clearActionState(for: pr) }
                return .success()
            } catch DecodingFailure.noData(let errors) {
                return fail(pr, errors.first ?? "no data", quiet: quiet)
            } catch {
                return fail(pr, String(describing: error), quiet: quiet)
            }
        case .ghNotFound, .notAuthenticated, .failure:
            if case .failure(let message) = outcomeResult(outcome) { return fail(pr, message, quiet: quiet) }
            return fail(pr, "unknown error", quiet: quiet)
        }
    }

    private func fail(_ pr: PullRequest, _ message: String, quiet: Bool) -> ActionResult {
        appLog.info("refresh \(pr.id): failed (\(message))")
        if !quiet { setActionState(.failed(.refresh, message), for: pr) }
        return .failure(message)
    }

    /// Whole-value assignments on purpose: writing through `viaTeam?.value` while reading `viaTeam` on the
    /// right-hand side is an exclusivity violation (it crashed), as it was once with `dormant`.
    private func replaceLocally(_ fresh: PullRequest) {
        let swap = { (prs: [PullRequest]) in prs.map { $0.id == fresh.id ? fresh : $0 } }
        var mineSnapshot = mine
        mineSnapshot.value = swap(mine.value)
        mine = mineSnapshot
        var directSnapshot = direct
        directSnapshot.value = swap(direct.value)
        direct = directSnapshot
        if var teamSnapshot = viaTeam {
            teamSnapshot.value = swap(teamSnapshot.value)
            viaTeam = teamSnapshot
        }
    }

    private func removeLocally(_ pr: PullRequest) {
        mine.value.removeAll { $0.id == pr.id }
        direct.value.removeAll { $0.id == pr.id }
        viaTeam?.value.removeAll { $0.id == pr.id }
        recomputeBadge()
    }

    /// A PR shown as "merged" is still in the lists for a moment, but must not count any more.
    private var mergedIDs: Set<String> {
        Set(actionStates.compactMap { key, state in state == .succeeded(.merge) ? key : nil })
    }


    /// What the user can actually see or count. Team requests only join while their section is open or
    /// counted; otherwise their repositories would show up in the filter lists without ever appearing.
    private var loadedPullRequests: [PullRequest] {
        mine.value + direct.value + (wantsTeamFetch ? (viaTeam?.value ?? []) : [])
    }

    /// Repositories present in what is shown, for the quick filter.
    var availableRepos: [RepoInfo] {
        var counts: [String: Int] = [:]
        for pr in allowed(loadedPullRequests) { counts[pr.repo, default: 0] += 1 }
        return counts.keys.sorted().map { RepoInfo(fullName: $0, openCount: counts[$0] ?? 0) }
    }
    /// Approximate count for the header: team requests minus the ones already shown as direct.
    var viaTeamTotal: Int? { viaTeam.map { max(0, $0.total - direct.total) } }
    var hasAnyData: Bool { mine.fetchedAt != nil || direct.fetchedAt != nil }

    /// Numbers on the tab picker: only what the visible sections would show.
    var mineTabCount: Int {
        let groups = mineGroups
        return orderedSections(.mine).filter { visibleSections.contains($0) }.reduce(0) { $0 + groups[$1].count }
    }

    /// Direct requests use the API total (there may be more than one page) unless the quick repo filter
    /// is on, in which case only the matching loaded rows count. Team requests are not counted here.
    var reviewTabCount: Int {
        guard visibleSections.contains(.needsYourReview) else { return 0 }
        return quickRepoFilter.isEmpty && !hasOnlyRules ? direct.total : directList.count
    }

    /// Everything that can own a PR of yours: your account, your organizations, owners seen in results,
    /// and owners currently hidden (so they can be shown again). Sorted by login.
    var knownOwners: [OwnerInfo] {
        var counts: [String: Int] = [:]
        for pr in allowed(loadedPullRequests) { counts[pr.ownerLogin, default: 0] += 1 }
        var logins = Set(loadedPullRequests.map(\.ownerLogin))
            .union(viewerOrganizations).union(hiddenOwners).union(repoRules.keys)
        if let viewerLogin { logins.insert(viewerLogin) }
        return logins.sorted().map { login in
            OwnerInfo(
                login: login,
                isViewer: login == viewerLogin,
                openCount: hiddenOwners.contains(login) ? nil : counts[login, default: 0],
                rule: repoRule(for: login)
            )
        }
    }

    var lastGoodDate: Date? {
        [mine.fetchedAt, direct.fetchedAt].compactMap { $0 }.max()
    }
    /// An error that must replace the lists: no data yet, or gh itself is unusable.
    var blockingError: ErrorKind? {
        guard let kind = lastError else { return nil }
        switch kind {
        case .ghNotFound, .notAuthenticated: return kind
        case .other: return hasAnyData ? nil : kind
        }
    }

    // MARK: Lifecycle

    /// While true the timer skips its cycles (the list must not move under a drag). Manual refresh still works.
    var holdsAutoRefresh = false

    // MARK: CI polling while the popover is open

    /// Only CI changes by itself within minutes, and only while the popover is open does anyone wait for
    /// it. So, while it is open, every `ciPollInterval` the rows with CI still running are looked up one by
    /// one (`refreshOne`, quietly) and move section when the result comes in. The poller always yields:
    /// it skips a round while a full cycle is in flight or about to start, while reorder mode holds the
    /// list, and skips a row the user is acting on. Not a setting: there is no trade-off worth a knob.
    let ciPollInterval: Duration
    static let ciPollMaxPerRound = 10
    /// A full cycle this close brings the same answers, more completely.
    static let ciPollYieldWindow: TimeInterval = 5
    private var ciPollTask: Task<Void, Never>?

    func startCIPolling() {
        guard ciPollTask == nil else { return }
        ciPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: self.ciPollInterval)
                guard !Task.isCancelled else { return }
                _ = await self.pollPendingCI()
            }
        }
    }

    func stopCIPolling() {
        ciPollTask?.cancel()
        ciPollTask = nil
    }

    /// One round. Returns how many pull requests were looked up.
    @discardableResult
    func pollPendingCI() async -> Int {
        guard !inFlight, !holdsAutoRefresh else { return 0 }
        if let nextRefreshAt, nextRefreshAt.timeIntervalSince(now()) < Self.ciPollYieldWindow { return 0 }
        var seen = Set<String>()
        let candidates = (mine.value + direct.value + (viaTeam?.value ?? [])).filter { pr in
            guard pr.ciState == .pending, !dormantIDs.contains(pr.id), actionStates[pr.id] == nil, !seen.contains(pr.id) else { return false }
            seen.insert(pr.id)
            return true
        }
        let round = Array(candidates.prefix(Self.ciPollMaxPerRound))
        guard !round.isEmpty else { return 0 }
        appLog.debug("ci poll: \(candidates.count) pending, checking \(round.count)")
        var checked = 0
        for pr in round {
            // Re-check before each one: the poller may have been stopped, a cycle may have started, or the
            // user may have acted meanwhile.
            guard !Task.isCancelled else { break }
            guard !inFlight, !holdsAutoRefresh, actionStates[pr.id] == nil else { continue }
            _ = await refreshOne(pr, quiet: true)
            checked += 1
        }
        return checked
    }

    func start() { restartTimer() }

    private func restartTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.holdsAutoRefresh { await self.refresh() }
                let interval = self.refreshInterval
                try? await Task.sleep(for: interval)
            }
        }
    }

    // MARK: Refresh

    /// One cycle in flight at a time. A request made while refreshing is coalesced into a single
    /// follow-up cycle, so a filter changed mid-cycle is always applied.
    func refresh() async {
        guard !inFlight else {
            pendingRefresh = true
            return
        }
        inFlight = true
        await runCycle()
        inFlight = false
        if pendingRefresh {
            pendingRefresh = false
            await refresh()
        }
    }

    /// Page sizes. The team search is a sample (20 shown) and was most of a cycle's time at 100 nodes;
    /// 30 keeps a margin over the 20 after the author filter and costs about half the time.
    static let pageSize = 100
    static let teamPageSize = 30

    private func runCycle() async {
        phase = .loading
        cycleStarted = now()
        appLog.debug("refresh start; hidden owners \(hiddenOwners.count), excluded repos \(excludedRepos.count), team \(wantsTeamFetch)")

        // All three at once: the team search no longer needs the direct list to exclude anything.
        let wantsTeam = wantsTeamFetch
        async let mineOutcome = client.search(SearchQuery.mine(hiding: hiddenOwners, repos: excludedRepos), includeMergeState: true, first: Self.pageSize)
        async let directOutcome = client.search(SearchQuery.direct(hiding: hiddenOwners, repos: excludedRepos), includeMergeState: false, first: Self.pageSize)
        async let teamOutcome: GHOutcome? = wantsTeam
            ? client.search(SearchQuery.viaTeam(hiding: hiddenOwners, repos: excludedRepos), includeMergeState: false, first: Self.teamPageSize)
            : nil
        let (m, d, t) = await (mineOutcome, directOutcome, teamOutcome)

        var errors: [ErrorKind] = []
        if let error = apply(m, to: &mine, search: .mine) { errors.append(error) } else { await reconcileMine() }
        if let error = apply(d, to: &direct, search: .direct) { errors.append(error) }

        if let t {
            var snapshot = viaTeam ?? Snapshot(value: [], total: 0, fetchedAt: nil)
            if let error = apply(t, to: &snapshot, search: .team) {
                errors.append(error)
                viaTeamError = error
            } else {
                viaTeam = snapshot
                viaTeamError = nil
            }
        }

        // After every snapshot is in place (no inout borrow left): snoozed PRs with new activity wake up.
        wakeChanged(in: mine.value + direct.value + (viaTeam?.value ?? []))
        finish(errors: errors)
    }

    /// The search index lags the repository by minutes (an approval showed up five refreshes late). The
    /// user's own pull requests are few, so one direct lookup after the search makes them authoritative.
    /// Any failure keeps the search result: this is a correction, never a condition.
    private func reconcileMine() async {
        let refs = mine.value.compactMap { PullRequestRef(repo: $0.repo, number: $0.number) }
        guard !refs.isEmpty else { return }
        let outcome = await client.pullRequests(refs, includeMergeState: true)
        guard case .success(let data) = outcome else {
            appLog.debug("reconcile mine skipped: \(outcomeResult(outcome))")
            return
        }
        do {
            let lookups = try parsePullRequestsResponse(data)
            var value = mine.value
            var changed = 0
            for (index, ref) in refs.enumerated() {
                guard let lookup = lookups["p\(index)"] else { continue }
                let position = value.firstIndex { $0.number == ref.number && $0.repo == "\(ref.owner)/\(ref.name)" }
                guard let position else { continue }
                switch lookup {
                case .open(let fresh):
                    if value[position] != fresh { value[position] = fresh; changed += 1 }
                case .closed, .notFound:
                    value.remove(at: position)
                    changed += 1
                }
            }
            var snapshot = mine
            snapshot.value = value
            mine = snapshot
            appLog.debug("reconcile mine: \(refs.count) looked up, \(changed) changed")
        } catch {
            appLog.debug("reconcile mine failed: \(error)")
        }
    }

    /// A refresh caused by a settings change; flagged until that cycle (and any coalesced follow-up) ends.
    func refreshForSettingsChange() async {
        applyingCount += 1
        isApplyingSettingsChange = true
        await refresh()
        applyingCount -= 1
        isApplyingSettingsChange = applyingCount > 0
    }

    /// Fetches only the team section, outside the regular cycle. Does not touch `phase`.
    func refreshViaTeam() async {
        isLoadingViaTeam = true
        defer { isLoadingViaTeam = false }
        let outcome = await client.search(SearchQuery.viaTeam(hiding: hiddenOwners, repos: excludedRepos), includeMergeState: false, first: Self.teamPageSize)
        var snapshot = viaTeam ?? Snapshot(value: [], total: 0, fetchedAt: nil)
        if let error = apply(outcome, to: &snapshot, search: .team) {
            viaTeamError = error
        } else {
            viaTeam = snapshot
            viaTeamError = nil
            wakeChanged(in: snapshot.value)
            recomputeBadge()
        }
    }

    func clearFailureLog() {
        failureLog.removeAll()
    }

    private func log(_ kind: ErrorKind, search: SearchKind) {
        appLog.info("search \(search.rawValue) failed: \(kind)")
        failureLog.insert(LogEntry(date: now(), search: search, kind: kind), at: 0)
        if failureLog.count > Self.failureLogLimit { failureLog.removeLast(failureLog.count - Self.failureLogLimit) }
    }

    /// Updates `snapshot` on success and returns nil; returns the error kind otherwise and leaves it untouched.
    private func apply(_ outcome: GHOutcome, to snapshot: inout Snapshot<[PullRequest]>, search: SearchKind) -> ErrorKind? {
        let error = applyOutcome(outcome, to: &snapshot)
        if let error { log(error, search: search) }
        return error
    }

    private func applyOutcome(_ outcome: GHOutcome, to snapshot: inout Snapshot<[PullRequest]>) -> ErrorKind? {
        switch outcome {
        case .ghNotFound:
            return .ghNotFound
        case .notAuthenticated:
            return .notAuthenticated
        case .failure(let message):
            logger.error("gh failed: \(message, privacy: .public)")
            return .other(message)
        case .success(let data):
            do {
                let page = try parseSearchResponse(data)
                for message in page.errorMessages {
                    logger.warning("GraphQL error: \(message, privacy: .public)")
                }
                snapshot = Snapshot(value: page.pullRequests, total: page.issueCount, fetchedAt: now())
                if let login = page.viewerLogin { viewerLogin = login }
                if !page.viewerOrganizations.isEmpty { viewerOrganizations = page.viewerOrganizations }
                return nil
            } catch DecodingFailure.noData(let errors) {
                logger.error("GraphQL returned no data: \(errors.joined(separator: "; "), privacy: .public)")
                return .other(errors.first ?? "GraphQL returned no data")
            } catch {
                logger.error("unexpected gh output: \(String(describing: error), privacy: .public)")
                return .other("Unexpected response from gh")
            }
        }
    }

    private var cycleStarted: Date?

    private func finish(errors: [ErrorKind]) {
        let date = now()
        let elapsed = cycleStarted.map { Int(date.timeIntervalSince($0) * 1000) } ?? 0
        if errors.isEmpty {
            appLog.info("refresh ok in \(elapsed) ms: mine \(mine.value.count), direct \(direct.value.count), team \(viaTeam?.value.count ?? 0)")
        } else {
            appLog.info("refresh failed in \(elapsed) ms: \(errors.map { String(describing: $0) }.joined(separator: "; "))")
        }
        nextRefreshAt = date.addingTimeInterval(TimeInterval(refreshInterval.components.seconds))
        if errors.isEmpty {
            lastError = nil
            phase = .ok(date)
            badgeCount = 0
            recomputeBadge()
            let present = Set((mine.value + direct.value).map(\.id))
            let pruned = pruneManualOrders(manualOrders, keeping: present)
            if pruned != manualOrders { manualOrders = pruned }
        } else {
            let kind = mostSevere(errors)
            lastError = kind
            phase = .error(kind, date)
        }
    }

    /// Only once a full cycle has succeeded; before that the badge stays nil on purpose.
    private func recomputeBadge() {
        guard badgeCount != nil else { return }
        let count = { (sections: Set<Section>) in
            computeBadgeCount(mine: self.allowed(self.mine.value), direct: self.allowed(self.direct.value), viaTeam: self.viaTeamList, counting: sections, dormant: self.dormantIDs.union(self.mergedIDs))
        }
        let counted = countedSections
        badgeCount = count(counted.first)
        badgeSecondCount = counted.second.map(count)
    }

    private func mostSevere(_ errors: [ErrorKind]) -> ErrorKind {
        if errors.contains(.ghNotFound) { return .ghNotFound }
        if errors.contains(.notAuthenticated) { return .notAuthenticated }
        return errors[0]
    }
}
