import Foundation
import Testing
@testable import Pullglance

@Suite struct FooterStatusTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func idleAndFirstLoadAreFetching() {
        #expect(footerStatus(phase: .idle, hasData: false, nextRefresh: nil, now: t0) == .fetching)
        #expect(footerStatus(phase: .loading, hasData: false, nextRefresh: nil, now: t0) == .fetching)
    }

    @Test func loadingWithDataIsRefreshing() {
        #expect(footerStatus(phase: .loading, hasData: true, nextRefresh: nil, now: t0) == .refreshing)
    }

    @Test func justUpdatedShowsUpdatedNowForTenSeconds() {
        let next = t0.addingTimeInterval(120)
        #expect(footerStatus(phase: .ok(t0), hasData: true, nextRefresh: next, now: t0.addingTimeInterval(3)) == .updatedNow)
        #expect(footerStatus(phase: .ok(t0), hasData: true, nextRefresh: next, now: t0.addingTimeInterval(9.9)) == .updatedNow)
        #expect(footerStatus(phase: .ok(t0), hasData: true, nextRefresh: next, now: t0.addingTimeInterval(10)) == .countdown(seconds: 110))
    }

    @Test func countdownNeverGoesNegative() {
        let next = t0.addingTimeInterval(120)
        #expect(footerStatus(phase: .ok(t0), hasData: true, nextRefresh: next, now: t0.addingTimeInterval(500)) == .countdown(seconds: 0))
    }

    @Test func failureCarriesTheDates() {
        let failedAt = t0.addingTimeInterval(60)
        #expect(footerStatus(phase: .error(.other("x"), failedAt), hasData: true, nextRefresh: nil, now: failedAt) == .failed(at: failedAt))
    }

    @Test func onlyCountdownAndFailureAcceptAManualRefresh() {
        #expect(FooterStatus.fetching.allowsManualRefresh == false)
        #expect(FooterStatus.refreshing.allowsManualRefresh == false)
        #expect(FooterStatus.updatedNow.allowsManualRefresh == false)
        #expect(FooterStatus.countdown(seconds: 5).allowsManualRefresh == true)
        #expect(FooterStatus.failed(at: t0).allowsManualRefresh == true)
    }

    @Test func countdownFormatsAsMinutesAndSeconds() {
        #expect(FooterStatus.countdown(seconds: 102).countdownText == "1:42")
        #expect(FooterStatus.countdown(seconds: 7).countdownText == "0:07")
        #expect(FooterStatus.countdown(seconds: 300).countdownText == "5:00")
    }
}

@MainActor
@Suite struct FailureLogTests {
    @Test func failedSearchesAreLoggedWithTheirSearchAndMessage() async throws {
        let gh = FakeGH()
        await gh.set(.failure("error connecting to api.github.com"), for: SearchQuery.mine)
        await gh.set(.notAuthenticated, for: SearchQuery.direct)
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date(timeIntervalSince1970: 1_000) })
        await store.refresh()
        #expect(store.failureLog.count == 2)
        let mine = try #require(store.failureLog.first { $0.search == .mine })
        #expect(mine.kind == .other("error connecting to api.github.com"))
        #expect(mine.date == Date(timeIntervalSince1970: 1_000))
        #expect(store.failureLog.first { $0.search == .direct }?.kind == .notAuthenticated)
    }

    @Test func successfulSearchesLogNothingAndTheLogIsCapped() async throws {
        let gh = FakeGH()
        await gh.set(.success(try fixture("search-mine.json")), for: SearchQuery.mine)
        await gh.set(.failure("boom"), for: SearchQuery.direct)
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        for _ in 0..<(PRStore.failureLogLimit + 5) { await store.refresh() }
        #expect(store.failureLog.count == PRStore.failureLogLimit)
        #expect(store.failureLog.allSatisfy { $0.search == .direct })
        store.clearFailureLog()
        #expect(store.failureLog.isEmpty)
    }

    @Test func nextRefreshIsScheduledAfterEachCycle() async throws {
        let gh = FakeGH()
        await gh.set(.success(try fixture("search-mine.json")), for: SearchQuery.mine)
        await gh.set(.success(try fixture("search-direct.json")), for: SearchQuery.direct)
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date(timeIntervalSince1970: 1_000) })
        #expect(store.nextRefreshAt == nil)
        await store.refresh()
        #expect(store.nextRefreshAt == Date(timeIntervalSince1970: 1_120))
    }
}
