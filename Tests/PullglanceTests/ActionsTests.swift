import Foundation
import Testing
@testable import Pullglance

@Suite struct ActionModelTests {
    @Test func decodesBranchesAndMergeOptions() throws {
        let page = try parseSearchResponse(envelope(nodes: [node(number: 1, ci: "SUCCESS", headRefOid: "deadbeef")]))
        let pr = try #require(page.pullRequests.first)
        #expect(pr.baseRefName == "main")
        #expect(pr.headRefName == "feature-1")
        #expect(pr.headRefOid == "deadbeef")
        #expect(pr.mergeOptions == MergeOptions(allowed: [.squash], defaultMethod: .squash, deleteBranchOnMerge: true))
    }

    @Test func missingMergeFieldsFallBackToEverythingAllowed() throws {
        let page = try parseSearchResponse(envelope(nodes: [node(number: 1, ci: nil, repoExtra: "\"isPrivate\":false")]))
        let pr = try #require(page.pullRequests.first)
        #expect(pr.mergeOptions == MergeOptions(allowed: [.merge, .squash, .rebase], defaultMethod: .merge, deleteBranchOnMerge: false))
    }

    @Test func decodesMergeQueueFields() throws {
        let queued = node(number: 1, ci: "SUCCESS", prExtra: "\"id\":\"PR_kwDOabc\",\"isMergeQueueEnabled\":true,\"mergeQueueEntry\":{\"position\":3,\"state\":\"QUEUED\"},\"mergeQueue\":{\"configuration\":{\"mergeMethod\":\"SQUASH\"}}")
        let waiting = node(number: 2, ci: "SUCCESS", prExtra: "\"id\":\"PR_kwDOdef\",\"isMergeQueueEnabled\":true,\"mergeQueueEntry\":null,\"mergeQueue\":{\"configuration\":{\"mergeMethod\":\"MERGE\"}}")
        let page = try parseSearchResponse(envelope(nodes: [queued, waiting, node(number: 3, ci: nil), node(number: 4, ci: nil, mergeable: nil)]))
        #expect(page.pullRequests.map(\.nodeID) == ["PR_kwDOabc", "PR_kwDOdef", "", ""])
        #expect(page.pullRequests.map(\.usesMergeQueue) == [true, true, false, false])
        #expect(page.pullRequests.map(\.mergeQueuePosition) == [3, nil, nil, nil])
        #expect(page.pullRequests.map(\.queueMergeMethod) == [.squash, .merge, nil, nil])
        // A list fetched without merge fields knows nothing about queues; the merge path must look first.
        #expect(page.pullRequests.map(\.hasMergeState) == [true, true, true, false])
    }

    @Test func decodesAutoMergeFields() throws {
        let blocked = node(number: 1, ci: "PENDING", mergeState: "BLOCKED", prExtra: "\"viewerCanEnableAutoMerge\":true,\"autoMergeRequest\":null")
        let scheduled = node(number: 2, ci: "PENDING", mergeState: "BLOCKED", prExtra: "\"viewerCanEnableAutoMerge\":false,\"autoMergeRequest\":{\"mergeMethod\":\"SQUASH\"}")
        let page = try parseSearchResponse(envelope(nodes: [blocked, scheduled, node(number: 3, ci: "SUCCESS")]))
        #expect(page.pullRequests.map(\.isBlocked) == [true, true, false])
        #expect(page.pullRequests.map(\.canEnableAutoMerge) == [true, false, false])
        #expect(page.pullRequests.map(\.autoMergeMethod) == [nil, .squash, nil])
    }

    /// GitHub's own rule for showing "Enable auto-merge": the viewer may, and the PR cannot merge right now.
    @Test func autoMergeIsOfferedOnlyWhereGitHubWouldOfferIt() {
        #expect(makePR(isBlocked: true, canEnableAutoMerge: true).offersAutoMerge == true)
        #expect(makePR(isBlocked: false, canEnableAutoMerge: true).offersAutoMerge == false, "mergeable now: merge now")
        #expect(makePR(isBlocked: true, canEnableAutoMerge: false).offersAutoMerge == false)
        #expect(makePR(usesMergeQueue: true, isBlocked: true, canEnableAutoMerge: true).offersAutoMerge == false, "the queue is the way there")
        #expect(makePR(isBlocked: true, canEnableAutoMerge: true, autoMergeMethod: .squash).offersAutoMerge == false, "already on")
        #expect(makePR(hasMergeState: false, isBlocked: true, canEnableAutoMerge: true).offersAutoMerge == false, "unknown is not yes")
    }

    @Test func autoMergeArgumentsMatchTheGhCLI() {
        let enable = GHClient.enableAutoMergeArguments(pullRequestID: "PR_1", method: .squash, expectedHeadOid: "abc")
        #expect(Array(enable.prefix(3)) == ["api", "graphql", "-f"])
        #expect(enable[3].contains("enablePullRequestAutoMerge"))
        #expect(Array(enable.suffix(6)) == ["-f", "id=PR_1", "-f", "method=SQUASH", "-f", "oid=abc"])
        let disable = GHClient.disableAutoMergeArguments(pullRequestID: "PR_1")
        #expect(disable[3].contains("disablePullRequestAutoMerge"))
        #expect(Array(disable.suffix(2)) == ["-f", "id=PR_1"])
    }

    @Test func mutationAcknowledgementsRejectErrors() throws {
        try parseMutationAck(Data(#"{"data":{"enablePullRequestAutoMerge":{"clientMutationId":null}}}"#.utf8), field: "enablePullRequestAutoMerge")
        let refused = Data(#"{"data":{"enablePullRequestAutoMerge":null},"errors":[{"message":"Pull request is in clean status"}]}"#.utf8)
        #expect(throws: DecodingFailure.noData(errors: ["Pull request is in clean status"])) { try parseMutationAck(refused, field: "enablePullRequestAutoMerge") }
    }

    @Test func enqueueArgumentsMatchTheGhCLI() {
        let args = GHClient.enqueueArguments(pullRequestID: "PR_1", expectedHeadOid: "abc")
        #expect(Array(args.prefix(3)) == ["api", "graphql", "-f"])
        #expect(args[3].hasPrefix("query=mutation"))
        #expect(args[3].contains("enqueuePullRequest"))
        #expect(Array(args.suffix(4)) == ["-f", "id=PR_1", "-f", "oid=abc"])
    }

    @Test func readsTheQueuePositionFromTheEnqueueResponse() throws {
        #expect(try parseEnqueueResponse(Data(#"{"data":{"enqueuePullRequest":{"mergeQueueEntry":{"position":2}}}}"#.utf8)) == 2)
        #expect(try parseEnqueueResponse(Data(#"{"data":{"enqueuePullRequest":{"mergeQueueEntry":null}}}"#.utf8)) == nil)
        let failed = Data(#"{"data":{"enqueuePullRequest":null},"errors":[{"message":"Pull request is already queued to merge"}]}"#.utf8)
        #expect(throws: DecodingFailure.noData(errors: ["Pull request is already queued to merge"])) { try parseEnqueueResponse(failed) }
        // A payload without an entry next to errors is not a success either.
        let partial = Data(#"{"data":{"enqueuePullRequest":{"mergeQueueEntry":null}},"errors":[{"message":"Something went wrong"}]}"#.utf8)
        #expect(throws: DecodingFailure.noData(errors: ["Something went wrong"])) { try parseEnqueueResponse(partial) }
    }

    @Test func defaultMethodOutsideTheAllowedSetIsReplaced() {
        let options = MergeOptions(allowed: [.rebase], defaultMethod: .squash, deleteBranchOnMerge: false)
        #expect(options.preselected == .rebase)
        #expect(MergeOptions(allowed: [.squash, .merge], defaultMethod: .squash, deleteBranchOnMerge: false).preselected == .squash)
    }

    @Test func mergeArgumentsMatchTheGhCLI() {
        let url = URL(string: "https://github.com/acme/web/pull/7")!
        #expect(GHClient.mergeArguments(url: url, method: .squash, deleteBranch: true, matchHeadCommit: "abc") ==
                ["pr", "merge", "https://github.com/acme/web/pull/7", "--squash", "--delete-branch", "--match-head-commit", "abc"])
        #expect(GHClient.mergeArguments(url: url, method: .merge, deleteBranch: false, matchHeadCommit: nil) ==
                ["pr", "merge", "https://github.com/acme/web/pull/7", "--merge"])
        #expect(GHClient.mergeArguments(url: url, method: .rebase, deleteBranch: false, matchHeadCommit: nil).contains("--rebase"))
        let lookup = GHClient.pullRequestArguments(owner: "acme", name: "web", number: 7, includeMergeState: true)
        #expect(Array(lookup.suffix(8)) == ["-f", "owner=acme", "-f", "name=web", "-F", "number=7", "-F", "withMerge=true"])
        #expect(lookup[3].hasPrefix("query=query($owner: String!"))
        #expect(GHClient.openPullRequestsArguments(repo: "acme/web", base: "feat/base") ==
                ["pr", "list", "--repo", "acme/web", "--base", "feat/base", "--state", "open", "--json", "number", "--limit", "100"])
    }

    @Test func countsOpenPullRequestsFromGhJSON() {
        #expect(parseOpenPullRequestCount(Data("[{\"number\":8},{\"number\":9}]".utf8)) == 2)
        #expect(parseOpenPullRequestCount(Data("[]".utf8)) == 0)
        #expect(parseOpenPullRequestCount(Data("nope".utf8)) == nil)
    }

    /// When the repository deletes merged branches itself, GitHub also retargets the pull requests stacked
    /// on them. Passing --delete-branch on top of that closes those pull requests instead (cli/cli#14223).
    @Test func neverAsksGhToDeleteWhenTheRepositoryAlreadyDoes() {
        let auto = MergeOptions(allowed: [.squash], defaultMethod: .squash, deleteBranchOnMerge: true)
        let manual = MergeOptions(allowed: [.squash], defaultMethod: .squash, deleteBranchOnMerge: false)
        #expect(requestedBranchDeletion(options: auto, toggle: true) == false)
        #expect(requestedBranchDeletion(options: manual, toggle: true) == true)
        #expect(requestedBranchDeletion(options: manual, toggle: false) == false)
    }

    @Test func commentArgumentsMatchTheGhCLI() {
        let url = URL(string: "https://github.com/acme/web/pull/7")!
        #expect(GHClient.commentArguments(url: url, body: "LGTM\nthanks") == ["pr", "comment", "https://github.com/acme/web/pull/7", "--body", "LGTM\nthanks"])
    }

    @Test func mergeWhenChecksPassReachesTheMenuOutsideReadyToMerge() {
        #expect(allActions(for: .waitingForReview, offersMerge: true) == [.merge, .comment, .snooze, .open, .copyLink, .refresh])
        #expect(allActions(for: .waitingForReview, autoMergeOn: true) == [.disableAutoMerge, .comment, .snooze, .open, .copyLink, .refresh])
        #expect(quickActions(for: .waitingForReview) == [.open, .comment], "swipe tiles do not change")
    }

    @Test func actionsPerSection() {
        #expect(quickActions(for: .readyToMerge) == [.merge, .comment])
        #expect(quickActions(for: .needsAction) == [.open, .comment])
        #expect(quickActions(for: .needsYourReview) == [.open, .comment])
        // A snoozed row leads with Wake, whatever its origin section.
        #expect(quickActions(for: .readyToMerge, dormant: true) == [.snooze, .open])
        #expect(quickActions(for: .needsAction, dormant: true) == [.snooze, .open])
        #expect(allActions(for: .readyToMerge) == [.merge, .comment, .snooze, .open, .copyLink, .refresh])
        #expect(allActions(for: .drafts).contains(.merge) == false)
        // A snoozed row leads with Wake in the menu too.
        #expect(allActions(for: .readyToMerge, dormant: true) == [.snooze, .merge, .comment, .open, .copyLink, .refresh])
        #expect(allActions(for: .needsAction, dormant: true) == [.snooze, .comment, .open, .copyLink, .refresh])
    }
}

@Suite struct DormancyTests {
    @Test func wakesOnNewCommitReviewDecisionOrCI() {
        let mark = DormantMark(headRefOid: "a", reviewDecision: .reviewRequired, ciState: .pending)
        #expect(mark.shouldWake(for: makePR(reviewDecision: .reviewRequired, ciState: .pending, headRefOid: "a")) == false)
        #expect(mark.shouldWake(for: makePR(reviewDecision: .reviewRequired, ciState: .pending, headRefOid: "b")) == true)
        #expect(mark.shouldWake(for: makePR(reviewDecision: .approved, ciState: .pending, headRefOid: "a")) == true)
        #expect(mark.shouldWake(for: makePR(reviewDecision: .reviewRequired, ciState: .failure, headRefOid: "a")) == true)
    }

    @Test func commentsAndThreadsAloneDoNotWake() {
        let mark = DormantMark(headRefOid: "a", reviewDecision: .approved, ciState: .success)
        #expect(mark.shouldWake(for: makePR(reviewDecision: .approved, ciState: .success, unresolvedThreads: 12, headRefOid: "a")) == false)
    }
}

@MainActor
@Suite struct ActionStoreTests {
    private func gh() async throws -> FakeGH {
        let gh = FakeGH()
        await gh.set(.success(try fixture("search-mine.json")), for: SearchQuery.mine)
        await gh.set(.success(try fixture("search-direct.json")), for: SearchQuery.direct)
        return gh
    }

    @Test func snoozedPRsLeaveTheBadgeAndPersist() async throws {
        let defaults = testDefaults()
        let store = PRStore(client: try await gh(), defaults: defaults, now: { Date() })
        await store.refresh()
        #expect(store.badgeCount == 6)
        let ready = store.mineGroups.readyToMerge
        #expect(ready.map(\.number) == [102, 103])
        store.snooze(ready[0])
        #expect(store.isDormant(ready[0]))
        #expect(store.badgeCount == 5)
        #expect(defaults.data(forKey: PRStore.dormantKey) != nil)
        store.wake(ready[0])
        #expect(store.isDormant(ready[0]) == false)
        #expect(store.badgeCount == 6)
    }

    @Test func snoozedPRWakesByItselfOnNewActivity() async throws {
        let gh = try await gh()
        let defaults = testDefaults()
        let store = PRStore(client: gh, defaults: defaults, now: { Date() })
        await store.refresh()
        let pr = store.mineGroups.readyToMerge[0]
        store.snooze(pr)
        let moved = try fixture("search-mine.json").replacingAll("\"number\":\(pr.number),\"title\":\"\(pr.title)\",\"url\":\"\(pr.url.absoluteString)\",\"isDraft\":false,\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"CLEAN\",\"baseRefName\":\"main\",\"headRefName\":\"feature\",\"headRefOid\":\"abc1234\"", with: "\"number\":\(pr.number),\"title\":\"\(pr.title)\",\"url\":\"\(pr.url.absoluteString)\",\"isDraft\":false,\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"CLEAN\",\"baseRefName\":\"main\",\"headRefName\":\"feature\",\"headRefOid\":\"newcommit\"")
        await gh.set(.success(moved), for: SearchQuery.mine)
        await store.refresh()
        #expect(store.isDormant(pr) == false)
        #expect(store.badgeCount == 6)
    }

    @Test func mergeCallsGhWithTheHeadCommitThenLingersAsMergedBeforeLeaving() async throws {
        let gh = try await gh()
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() }, successLinger: .milliseconds(150))
        await store.refresh()
        let pr = store.mineGroups.readyToMerge[0]
        await gh.setOpenPullRequests(.success(Data("[]".utf8)))
        let result = await store.merge(pr, method: .squash, deleteBranch: true)
        #expect(result == .success())
        let call = try #require(await gh.merges.first)
        #expect(call.url == pr.url)
        #expect(call.method == .squash)
        #expect(call.deleteBranch == true)
        #expect(await gh.dependentQueries.map(\.base) == [pr.headRefName])
        #expect(call.matchHeadCommit == pr.headRefOid)
        // Right after: shown as merged, still in the list, already out of the badge.
        #expect(store.actionState(for: pr) == .succeeded(.merge))
        #expect(store.mine.value.contains(pr))
        #expect(store.badgeCount == 5)
        try await Task.sleep(for: .milliseconds(300))
        #expect(store.mine.value.contains(pr) == false)
        #expect(store.actionState(for: pr) == nil)
    }

    /// A base that requires a merge queue refuses a strategy, and the repository may forbid auto-merge; the
    /// only thing that works everywhere is the queue's own mutation. Branch deletion is the queue's business.
    @Test func mergeOnAMergeQueueBaseEnqueuesInstead() async throws {
        let gh = FakeGH()
        let queued = node(number: 102, ci: "SUCCESS", decision: "APPROVED", headRefOid: "feedface", prExtra: "\"id\":\"PR_q\",\"isMergeQueueEnabled\":true,\"mergeQueueEntry\":null")
        await gh.set(.success(envelope(nodes: [queued])), for: SearchQuery.mine)
        await gh.set(.success(try fixture("search-direct.json")), for: SearchQuery.direct)
        await gh.setEnqueueOutcome(.success(Data(#"{"data":{"enqueuePullRequest":{"mergeQueueEntry":{"position":2}}}}"#.utf8)))
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() }, successLinger: .milliseconds(150))
        await store.refresh()
        let pr = try #require(store.mineGroups.readyToMerge.first)
        let result = await store.merge(pr, method: .squash, deleteBranch: true)
        guard case .success(let note?) = result else { Issue.record("expected a note, got \(result)"); return }
        #expect(note.contains("2"))
        #expect(await gh.merges.isEmpty)
        #expect(await gh.dependentQueries.isEmpty)
        let call = try #require(await gh.enqueues.first)
        #expect(call.id == "PR_q")
        #expect(call.oid == "feedface")
        #expect(store.actionState(for: pr) == .succeeded(.merge))
        // Queued is not merged: the row stays, and a lookup brings the queue entry in for the pill.
        let inQueue = node(number: 102, ci: "SUCCESS", decision: "APPROVED", headRefOid: "feedface", prExtra: "\"id\":\"PR_q\",\"isMergeQueueEnabled\":true,\"mergeQueueEntry\":{\"position\":2,\"state\":\"AWAITING_CHECKS\"}")
        await gh.setPullRequest(.success(pullRequestEnvelope(inQueue)), number: 102)
        try await Task.sleep(for: .milliseconds(400))
        #expect(store.actionState(for: pr) == nil)
        let kept = try #require(store.mine.value.first { $0.id == pr.id })
        #expect(kept.mergeQueuePosition == 2)
        #expect(await gh.lookups.map(\.includeMergeState) == [true])
    }

    /// Review requests are listed without merge fields, and the review window can merge them: the merge path
    /// looks the pull request up with those fields before choosing between the queue and a direct merge.
    @Test func mergingAPullRequestListedWithoutMergeStateLooksItUpFirst() async throws {
        let gh = FakeGH()
        await gh.set(.success(try fixture("search-mine.json")), for: SearchQuery.mine)
        await gh.set(.success(envelope(nodes: [node(number: 7, ci: "SUCCESS", decision: "APPROVED", mergeable: nil)])), for: SearchQuery.direct)
        let fresh = node(number: 7, ci: "SUCCESS", decision: "APPROVED", prExtra: "\"id\":\"PR_seven\",\"isMergeQueueEnabled\":true,\"mergeQueueEntry\":null")
        await gh.setPullRequest(.success(pullRequestEnvelope(fresh)), number: 7)
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() }, successLinger: .milliseconds(50))
        await store.refresh()
        let pr = try #require(store.directList.first { $0.number == 7 })
        #expect(pr.hasMergeState == false)
        guard case .success = await store.merge(pr, method: .squash, deleteBranch: false) else { Issue.record("expected success"); return }
        #expect(await gh.lookups.first?.includeMergeState == true)
        #expect(await gh.enqueues.first?.id == "PR_seven")
        #expect(await gh.merges.isEmpty)
    }

    @Test func enqueueErrorsStayOnTheRow() async throws {
        let gh = FakeGH()
        let queued = node(number: 102, ci: "SUCCESS", decision: "APPROVED", prExtra: "\"id\":\"PR_q\",\"isMergeQueueEnabled\":true,\"mergeQueueEntry\":null")
        await gh.set(.success(envelope(nodes: [queued])), for: SearchQuery.mine)
        await gh.set(.success(try fixture("search-direct.json")), for: SearchQuery.direct)
        await gh.setEnqueueOutcome(.success(Data(#"{"data":{"enqueuePullRequest":null},"errors":[{"message":"Pull request is already queued to merge"}]}"#.utf8)))
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        await store.refresh()
        let pr = try #require(store.mineGroups.readyToMerge.first)
        #expect(await store.merge(pr, method: .squash, deleteBranch: false) == .failure("Pull request is already queued to merge"))
        #expect(store.actionState(for: pr) == .failed(.merge, "Pull request is already queued to merge"))
    }

    /// The lookup settles the mechanism, never the commit: what gets merged is what the user saw listed.
    @Test func aLookupThatFindsANewerHeadRefusesInsteadOfMergingIt() async throws {
        let gh = FakeGH()
        await gh.set(.success(try fixture("search-mine.json")), for: SearchQuery.mine)
        await gh.set(.success(envelope(nodes: [node(number: 7, ci: "SUCCESS", decision: "APPROVED", mergeable: nil, headRefOid: "seen")])), for: SearchQuery.direct)
        let moved = node(number: 7, ci: "SUCCESS", decision: "APPROVED", headRefOid: "newer", prExtra: "\"id\":\"PR_seven\",\"isMergeQueueEnabled\":true,\"mergeQueueEntry\":null")
        await gh.setPullRequest(.success(pullRequestEnvelope(moved)), number: 7)
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        await store.refresh()
        let pr = try #require(store.directList.first { $0.number == 7 })
        let result = await store.merge(pr, method: .squash, deleteBranch: false)
        guard case .failure(let message) = result else { Issue.record("expected a failure, got \(result)"); return }
        #expect(MergeFailure(ghMessage: message) == .changedSinceShown)
        #expect(await gh.enqueues.isEmpty)
        #expect(await gh.merges.isEmpty)
        // The row now shows the newer head, so a retry merges what is on screen.
        #expect(store.directList.first { $0.number == 7 }?.headRefOid == "newer")
    }

    /// Blocked on requirements, auto-merge allowed: GitHub merges later, by itself. The app only asks.
    @Test func mergeWhenChecksPassEnablesAutoMergeAndKeepsTheRow() async throws {
        let gh = FakeGH()
        let blocked = node(number: 104, ci: "PENDING", decision: "APPROVED", mergeState: "BLOCKED", headRefOid: "cafe", prExtra: "\"id\":\"PR_b\",\"viewerCanEnableAutoMerge\":true,\"autoMergeRequest\":null")
        await gh.set(.success(envelope(nodes: [blocked])), for: SearchQuery.mine)
        await gh.set(.success(try fixture("search-direct.json")), for: SearchQuery.direct)
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() }, successLinger: .milliseconds(100))
        await store.refresh()
        let pr = try #require(store.mine.value.first { $0.number == 104 })
        #expect(pr.offersAutoMerge)
        let result = await store.merge(pr, method: .rebase, deleteBranch: true)
        guard case .success(let note?) = result else { Issue.record("expected a note, got \(result)"); return }
        #expect(note.isEmpty == false)
        let call = try #require(await gh.autoMergeEnables.first)
        #expect(call.id == "PR_b")
        #expect(call.method == .rebase)
        #expect(call.oid == "cafe")
        #expect(await gh.merges.isEmpty)
        #expect(await gh.dependentQueries.isEmpty, "the branch is GitHub's to delete, later")
        let scheduled = node(number: 104, ci: "PENDING", decision: "APPROVED", mergeState: "BLOCKED", headRefOid: "cafe", prExtra: "\"id\":\"PR_b\",\"viewerCanEnableAutoMerge\":false,\"autoMergeRequest\":{\"mergeMethod\":\"REBASE\"}")
        await gh.setPullRequest(.success(pullRequestEnvelope(scheduled)), number: 104)
        try await Task.sleep(for: .milliseconds(300))
        #expect(store.actionState(for: pr) == nil)
        #expect(store.mine.value.first { $0.number == 104 }?.autoMergeMethod == .rebase)
    }

    @Test func disablingAutoMergeCallsGitHubAndRefreshesTheRow() async throws {
        let gh = FakeGH()
        let scheduled = node(number: 104, ci: "PENDING", decision: "APPROVED", mergeState: "BLOCKED", prExtra: "\"id\":\"PR_b\",\"viewerCanEnableAutoMerge\":false,\"autoMergeRequest\":{\"mergeMethod\":\"SQUASH\"}")
        await gh.set(.success(envelope(nodes: [scheduled])), for: SearchQuery.mine)
        await gh.set(.success(try fixture("search-direct.json")), for: SearchQuery.direct)
        let off = node(number: 104, ci: "PENDING", decision: "APPROVED", mergeState: "BLOCKED", prExtra: "\"id\":\"PR_b\",\"viewerCanEnableAutoMerge\":true,\"autoMergeRequest\":null")
        await gh.setPullRequest(.success(pullRequestEnvelope(off)), number: 104)
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        await store.refresh()
        let pr = try #require(store.mine.value.first { $0.number == 104 })
        #expect(await store.disableAutoMerge(pr) == .success())
        #expect(await gh.autoMergeDisables == ["PR_b"])
        #expect(store.mine.value.first { $0.number == 104 }?.autoMergeMethod == nil)
        #expect(store.actionState(for: pr) == nil)
    }

    @Test func keepsTheBranchWhenOpenPullRequestsAreBasedOnIt() async throws {
        let gh = try await gh()
        await gh.setOpenPullRequests(.success(Data("[{\"number\":8},{\"number\":9}]".utf8)))
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() }, successLinger: .milliseconds(150))
        await store.refresh()
        let pr = store.mineGroups.readyToMerge[0]
        let result = await store.merge(pr, method: .squash, deleteBranch: true)
        guard case .success(let note?) = result else { Issue.record("expected a note, got \(result)"); return }
        #expect(note.contains("2"))
        #expect(await gh.merges.first?.deleteBranch == false)
    }

    @Test func keepsTheBranchWhenTheDependentsCheckFails() async throws {
        let gh = try await gh()
        await gh.setOpenPullRequests(.failure("boom"))
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() }, successLinger: .milliseconds(150))
        await store.refresh()
        let pr = store.mineGroups.readyToMerge[0]
        let result = await store.merge(pr, method: .squash, deleteBranch: true)
        guard case .success(let note?) = result else { Issue.record("expected a note, got \(result)"); return }
        #expect(note.isEmpty == false)
        #expect(await gh.merges.first?.deleteBranch == false)
    }

    @Test func mergingWithoutDeletionDoesNotLookForDependents() async throws {
        let gh = try await gh()
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() }, successLinger: .milliseconds(150))
        await store.refresh()
        let pr = store.mineGroups.readyToMerge[0]
        _ = await store.merge(pr, method: .squash, deleteBranch: false)
        #expect(await gh.dependentQueries.isEmpty)
    }

    @Test func mergeFailureStaysOnTheRowUntilDismissed() async throws {
        let gh = try await gh()
        await gh.setMergeOutcome(.failure("GraphQL: Head branch was modified. Review and try the merge again."))
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        await store.refresh()
        let pr = store.mineGroups.readyToMerge[0]
        let result = await store.merge(pr, method: .squash, deleteBranch: false)
        #expect(result == .failure("GraphQL: Head branch was modified. Review and try the merge again."))
        #expect(store.mine.value.contains(pr))
        #expect(store.actionState(for: pr) == .failed(.merge, "GraphQL: Head branch was modified. Review and try the merge again."))
        #expect(store.failureLog.isEmpty)
        store.clearActionState(for: pr)
        #expect(store.actionState(for: pr) == nil)
    }

    @Test func runningActionIsTrackedPerPR() async throws {
        let gh = try await gh()
        await gh.setDelay(.milliseconds(200))
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() }, successLinger: .zero)
        await store.refresh()
        let pr = store.mineGroups.readyToMerge[0]
        let task = Task { await store.merge(pr, method: .squash, deleteBranch: false) }
        try await Task.sleep(for: .milliseconds(30))
        #expect(store.actionState(for: pr) == .running(.merge))
        #expect(store.actionState(for: store.mineGroups.readyToMerge[1]) == nil)
        _ = await task.value
        try await Task.sleep(for: .milliseconds(30))
        #expect(store.actionState(for: pr) == nil)
    }

    @Test func snoozedPRsMoveToTheSnoozedSectionOfTheirTab() async throws {
        let store = PRStore(client: try await gh(), defaults: testDefaults(), now: { Date() })
        await store.refresh()
        let pr = store.mineGroups.readyToMerge[0]
        store.snooze(pr)
        #expect(store.mineGroups.readyToMerge.map(\.number) == [103])
        #expect(store.mineGroups[.snoozedMine].map(\.number) == [pr.number])
        #expect(store.originSection(of: pr) == .readyToMerge)
        #expect(store.mineTabCount == 4, "snoozed rows do not count")
        let direct = store.directList[0]
        store.snooze(direct)
        #expect(store.directList.contains(direct) == false)
        #expect(store.snoozedReviewList.map(\.number) == [direct.number])
        #expect(store.reviewTabCount == 27, "API total, unchanged by local snoozing")
    }

    @Test func commentCallsGh() async throws {
        let gh = try await gh()
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        await store.refresh()
        let pr = store.mineGroups.readyToMerge[0]
        #expect(await store.comment(pr, body: "Looks good") == ActionResult.success())
        #expect(await gh.comments.first?.body == "Looks good")
        #expect(await store.comment(pr, body: "   ") == .failure("Empty comment"))
    }
}

private extension Data {
    func replacingAll(_ target: String, with replacement: String) -> Data {
        Data(String(decoding: self, as: UTF8.self).replacingOccurrences(of: target, with: replacement).utf8)
    }
}

@Suite struct MergeFailureTests {
    @Test(arguments: [
        ("GraphQL: Pull Request is not mergeable: the pull request has merge conflicts", MergeFailure.conflicts),
        ("X Pull request #7 is not mergeable: the merge commit cannot be cleanly created.", .conflicts),
        ("GraphQL: Pull Request is not mergeable: required status check \"ci\" is failing (mergePullRequest)", .checksNotPassing),
        ("GraphQL: 2 of 2 required status checks are expected. (mergePullRequest)", .checksNotPassing),
        ("GraphQL: Pull Request is not mergeable: at least 1 approving review is required (mergePullRequest)", .reviewRequired),
        ("GraphQL: Head branch was modified. Review and try the merge again. (mergePullRequest)", .changedSinceShown),
        ("X Pull request #7 (feature) can't be merged right now; try again in a few seconds", .temporarilyUnavailable),
        ("GraphQL: Pull request Pull request is in clean status is already merged (mergePullRequest)", .alreadyMerged),
        ("X Pull request #7 was already merged", .alreadyMerged),
        ("GraphQL: Pull Request is not mergeable: the pull request is closed", .closed),
        ("GraphQL: Resource not accessible by integration (mergePullRequest)", .notAllowed),
        ("GraphQL: Base branch is protected and you do not have permission (mergePullRequest)", .notAllowed),
        ("GraphQL: Pull request is already queued to merge (enqueuePullRequest)", .alreadyQueued),
        ("something else entirely", .other("something else entirely")),
    ])
    func classifiesGhMergeErrors(message: String, expected: MergeFailure) {
        #expect(MergeFailure(ghMessage: message) == expected)
    }

    @Test func preflightBlocksWhatCannotMerge() {
        #expect(mergePreflight(makePR(reviewDecision: .approved, ciState: .success)) == nil)
        #expect(mergePreflight(makePR(isDraft: true, reviewDecision: .approved, ciState: .success)) == .draft)
        #expect(mergePreflight(makePR(reviewDecision: .approved, ciState: .success, hasConflicts: true)) == .conflicts)
        #expect(mergePreflight(makePR(reviewDecision: .approved, ciState: .failure)) == .checksNotPassing)
        #expect(mergePreflight(makePR(reviewDecision: .changesRequested, ciState: .success)) == .reviewRequired)
        // Pending checks and a missing review are warnings for the modal, not blocks: branch protection decides.
        #expect(mergePreflight(makePR(reviewDecision: .reviewRequired, ciState: .pending)) == nil)
        // Already in the queue, or already scheduled: nothing left to ask for.
        #expect(mergePreflight(makePR(reviewDecision: .approved, ciState: .success, usesMergeQueue: true, mergeQueuePosition: 1)) == .alreadyQueued)
        #expect(mergePreflight(makePR(reviewDecision: .approved, ciState: .pending, isBlocked: true, autoMergeMethod: .squash)) == .autoMergeOn)
        #expect(mergePreflight(makePR(reviewDecision: .approved, ciState: .success, usesMergeQueue: true)) == nil)
    }
}

@Suite struct PullRequestLookupTests {
    @Test func decodesAnOpenPullRequest() throws {
        let lookup = try parsePullRequestResponse(pullRequestEnvelope(node(number: 7, ci: "SUCCESS", decision: "APPROVED")))
        guard case .open(let pr) = lookup else { Issue.record("expected open"); return }
        #expect(pr.id == "acme/web#7")
        #expect(pr.ciState == .success)
    }

    @Test func mergedClosedAndMissingAreNotOpen() throws {
        #expect(try parsePullRequestResponse(pullRequestEnvelope(node(number: 7, ci: nil), state: "MERGED")) == .closed)
        #expect(try parsePullRequestResponse(pullRequestEnvelope(node(number: 7, ci: nil), state: "CLOSED")) == .closed)
        #expect(try parsePullRequestResponse(pullRequestEnvelope(nil)) == .notFound)
        let gone = Data(#"{"data":{"repository":null},"errors":[{"message":"Could not resolve to a Repository with the name 'acme/web'."}]}"#.utf8)
        #expect(try parsePullRequestResponse(gone) == .notFound)
    }

    @Test func errorsWithoutDataThrow() {
        let data = Data(#"{"data":null,"errors":[{"message":"rate limited"}]}"#.utf8)
        #expect(throws: DecodingFailure.noData(errors: ["rate limited"])) { try parsePullRequestResponse(data) }
    }
}

@MainActor
@Suite struct RefreshOneTests {
    private func store() async throws -> (PRStore, FakeGH) {
        let gh = FakeGH()
        await gh.set(.success(try fixture("search-mine.json")), for: SearchQuery.mine)
        await gh.set(.success(try fixture("search-direct.json")), for: SearchQuery.direct)
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        await store.refresh()
        return (store, gh)
    }

    @Test func aRefreshedPullRequestMovesToItsNewSection() async throws {
        let (store, gh) = try await store()
        let pr = try #require(store.mine.value.first { $0.repo == "acme/web" && mineSection(for: $0) != .readyToMerge })
        await gh.setPullRequest(.success(pullRequestEnvelope(node(number: pr.number, ci: "SUCCESS", decision: "APPROVED"))), number: pr.number)
        #expect(await store.refreshOne(pr) == .success())
        #expect(store.mineGroups.readyToMerge.contains { $0.id == pr.id })
        #expect(store.actionState(for: pr) == nil)
        let lookup = try #require(await gh.lookups.first)
        #expect(lookup.owner == "acme" && lookup.name == "web" && lookup.number == pr.number && lookup.includeMergeState)
        #expect(await gh.callCount(for: SearchQuery.mine) == 1, "no full refresh")
    }

    @Test func aMergedPullRequestLeavesTheList() async throws {
        let (store, gh) = try await store()
        let pr = store.mineGroups.readyToMerge[0]
        await gh.setPullRequest(.success(pullRequestEnvelope(node(number: pr.number, ci: nil), state: "MERGED")), number: pr.number)
        #expect(await store.refreshOne(pr) == .success())
        #expect(!store.mine.value.contains { $0.id == pr.id })
    }

    @Test func aFailedLookupStaysOnTheRow() async throws {
        let (store, gh) = try await store()
        let pr = store.mineGroups.readyToMerge[0]
        await gh.setPullRequest(.failure("boom"), number: pr.number)
        #expect(await store.refreshOne(pr) == .failure("boom"))
        #expect(store.actionState(for: pr) == .failed(.refresh, "boom"))
        #expect(store.mine.value.contains { $0.id == pr.id })
    }

    /// Regression: replacing a PR while the team list was loaded crashed on an exclusivity conflict.
    @Test func refreshingWithTheTeamListLoadedDoesNotTrap() async throws {
        let gh = FakeGH()
        await gh.set(.success(try fixture("search-mine.json")), for: SearchQuery.mine)
        await gh.set(.success(try fixture("search-direct.json")), for: SearchQuery.direct)
        await gh.set(.success(try fixture("search-team.json")), for: SearchQuery.viaTeam)
        let store = PRStore(client: gh, defaults: testDefaults(), now: { Date() })
        store.isViaTeamExpanded = true
        await store.refresh()
        #expect(store.viaTeam != nil)
        let pr = store.mineGroups.readyToMerge[0]
        await gh.setPullRequest(.success(pullRequestEnvelope(node(number: pr.number, ci: "SUCCESS", decision: "APPROVED"))), number: pr.number)
        #expect(await store.refreshOne(pr) == .success())
        let team = try #require(store.viaTeamList.first)
        await gh.setPullRequest(.success(pullRequestEnvelope(node(number: team.number, ci: "FAILURE"))), number: team.number)
        _ = await store.refreshOne(team)
    }

    /// One pull request is cheap to compute merge state for, and the review window merges review requests
    /// too, so the lookup it triggers must know about queues.
    @Test func reviewRequestsAreLookedUpWithMergeFieldsToo() async throws {
        let (store, gh) = try await store()
        let pr = store.directList[0]
        await gh.setPullRequest(.success(pullRequestEnvelope(node(number: pr.number, ci: "SUCCESS"))), number: pr.number)
        _ = await store.refreshOne(pr)
        #expect(await gh.lookups.first?.includeMergeState == true)
    }
}
