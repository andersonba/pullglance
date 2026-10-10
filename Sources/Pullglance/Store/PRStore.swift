import Foundation
import Observation
import os

enum SearchQuery {
    static let suffix = "archived:false sort:updated-desc"
    static let mine = "is:pr is:open author:@me \(suffix)"
    static let direct = "is:pr is:open user-review-requested:@me \(suffix)"
    static let viaTeam = "is:pr is:open review-requested:@me \(suffix)"

    static func mine(hiding owners: Set<String>) -> String { mine + exclusions(owners) }
    static func direct(hiding owners: Set<String>) -> String { direct + exclusions(owners) }
    static func viaTeam(hiding owners: Set<String>) -> String { viaTeam + exclusions(owners) }

    /// `-user:` works for organizations and personal accounts alike, and several of them AND together.
    private static func exclusions(_ owners: Set<String>) -> String {
        owners.sorted().map { " -user:\($0)" }.joined()
    }
}

/// An organization or account that can own pull requests shown by the app.
struct OwnerInfo: Equatable, Identifiable, Sendable {
    let login: String
    let isViewer: Bool
    /// Open PRs currently loaded for this owner; nil when hidden (nothing is fetched for it).
    let openCount: Int?
    var id: String { login }
}

@Observable
@MainActor
final class PRStore {
    static let expandedKey = "viaTeamExpanded"
    static let intervalKey = "refreshIntervalSeconds"
    static let hiddenOwnersKey = "hiddenOwners"
    static let visibleSectionsKey = "visibleSections"
    static let badgeSectionsKey = "badgeSections"
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
    private(set) var viewerLogin: String? = nil
    private(set) var viewerOrganizations: [String] = []

    /// Owners excluded from every search, and therefore from both tabs and the badge. Stored per machine.
    var hiddenOwners: Set<String> {
        didSet {
            guard hiddenOwners != oldValue else { return }
            defaults.set(hiddenOwners.sorted(), forKey: Self.hiddenOwnersKey)
            viaTeam = nil
            viaTeamError = nil
            Task { await refresh() }
        }
    }

    /// Sections shown in the popover. Missing from defaults means all.
    var visibleSections: Set<Section> {
        didSet { defaults.set(visibleSections.map(\.rawValue).sorted(), forKey: Self.visibleSectionsKey) }
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

    /// The team search runs every cycle when the section is open or counted in the badge.
    private var wantsTeamFetch: Bool { isViaTeamExpanded || badgeSections.contains(.needsTeamsReview) }

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
            defaults.set(Int(refreshInterval.components.seconds), forKey: Self.intervalKey)
            if timerTask != nil { restartTimer() }
        }
    }

    private let client: any GHRunning
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: AppInfo.bundleID, category: "store")
    private var inFlight = false
    /// A refresh asked for while a cycle runs (manual, timer or a filter change) runs once the cycle ends.
    private var pendingRefresh = false
    private var timerTask: Task<Void, Never>?

    init(client: any GHRunning, defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.defaults = defaults
        self.now = now
        self.isViaTeamExpanded = defaults.bool(forKey: Self.expandedKey)
        self.hiddenOwners = Set(defaults.stringArray(forKey: Self.hiddenOwnersKey) ?? [])
        self.visibleSections = Self.sections(in: defaults, key: Self.visibleSectionsKey) ?? Set(Section.allCases)
        self.badgeSections = Self.sections(in: defaults, key: Self.badgeSectionsKey) ?? Section.defaultBadge
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

    func orderedSections(_ tab: Section.Tab) -> [Section] {
        sectionOrder.filter { $0.tab == tab }
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

    var mineGroups: MineGroups { groupMine(mine.value) }
    var directList: [PullRequest] { sortedByRecency(direct.value) }
    var viaTeamList: [PullRequest] {
        filterViaTeam(all: viaTeam?.value ?? [], direct: direct.value, viewerLogin: viewerLogin)
    }
    /// Approximate count for the header: team requests minus the ones already shown as direct.
    var viaTeamTotal: Int? { viaTeam.map { max(0, $0.total - direct.total) } }
    var hasAnyData: Bool { mine.fetchedAt != nil || direct.fetchedAt != nil }

    /// Numbers on the tab picker: only what the visible sections would show.
    var mineTabCount: Int {
        let groups = mineGroups
        return orderedSections(.mine).filter { visibleSections.contains($0) }.reduce(0) { $0 + groups[$1].count }
    }

    /// Direct requests use the API total (there may be more than one page); team requests are not counted here.
    var reviewTabCount: Int {
        visibleSections.contains(.needsYourReview) ? direct.total : 0
    }

    /// Everything that can own a PR of yours: your account, your organizations, owners seen in results,
    /// and owners currently hidden (so they can be shown again). Sorted by login.
    var knownOwners: [OwnerInfo] {
        var counts: [String: Int] = [:]
        for pr in mine.value + direct.value + (viaTeam?.value ?? []) {
            counts[pr.ownerLogin, default: 0] += 1
        }
        var logins = Set(counts.keys).union(viewerOrganizations).union(hiddenOwners)
        if let viewerLogin { logins.insert(viewerLogin) }
        return logins.sorted().map { login in
            OwnerInfo(
                login: login,
                isViewer: login == viewerLogin,
                openCount: hiddenOwners.contains(login) ? nil : counts[login, default: 0]
            )
        }
    }
    var isRefreshing: Bool { phase == .loading }
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

    func start() { restartTimer() }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func restartTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
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

    private func runCycle() async {
        phase = .loading

        async let mineOutcome = client.search(SearchQuery.mine(hiding: hiddenOwners), includeMergeState: true)
        async let directOutcome = client.search(SearchQuery.direct(hiding: hiddenOwners), includeMergeState: false)
        let (m, d) = await (mineOutcome, directOutcome)

        var errors: [ErrorKind] = []
        if let error = apply(m, to: &mine) { errors.append(error) }
        if let error = apply(d, to: &direct) { errors.append(error) }

        if wantsTeamFetch {
            let t = await client.search(SearchQuery.viaTeam(hiding: hiddenOwners), includeMergeState: false)
            var snapshot = viaTeam ?? Snapshot(value: [], total: 0, fetchedAt: nil)
            if let error = apply(t, to: &snapshot) {
                errors.append(error)
                viaTeamError = error
            } else {
                viaTeam = snapshot
                viaTeamError = nil
            }
        }

        finish(errors: errors)
    }

    /// Fetches only the team section, outside the regular cycle. Does not touch `phase`.
    func refreshViaTeam() async {
        isLoadingViaTeam = true
        defer { isLoadingViaTeam = false }
        let outcome = await client.search(SearchQuery.viaTeam(hiding: hiddenOwners), includeMergeState: false)
        var snapshot = viaTeam ?? Snapshot(value: [], total: 0, fetchedAt: nil)
        if let error = apply(outcome, to: &snapshot) {
            viaTeamError = error
        } else {
            viaTeam = snapshot
            viaTeamError = nil
            recomputeBadge()
        }
    }

    /// Updates `snapshot` on success and returns nil; returns the error kind otherwise and leaves it untouched.
    private func apply(_ outcome: GHOutcome, to snapshot: inout Snapshot<[PullRequest]>) -> ErrorKind? {
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

    private func finish(errors: [ErrorKind]) {
        let date = now()
        if errors.isEmpty {
            lastError = nil
            phase = .ok(date)
            badgeCount = computeBadgeCount(mine: mine.value, direct: direct.value, viaTeam: viaTeamList, counting: badgeSections)
        } else {
            let kind = mostSevere(errors)
            lastError = kind
            phase = .error(kind, date)
        }
    }

    /// Only once a full cycle has succeeded; before that the badge stays nil on purpose.
    private func recomputeBadge() {
        guard badgeCount != nil else { return }
        badgeCount = computeBadgeCount(mine: mine.value, direct: direct.value, viaTeam: viaTeamList, counting: badgeSections)
    }

    private func mostSevere(_ errors: [ErrorKind]) -> ErrorKind {
        if errors.contains(.ghNotFound) { return .ghNotFound }
        if errors.contains(.notAuthenticated) { return .notAuthenticated }
        return errors[0]
    }
}
