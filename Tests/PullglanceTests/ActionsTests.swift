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
        #expect(GHClient.commentArguments(url: url, body: "LGTM\nthanks") == ["pr", "comment", "https://github.com/acme/web/pull/7", "--body", "LGTM\nthanks"])
    }

    @Test func actionsPerSection() {
        #expect(quickActions(for: .readyToMerge) == [.merge, .comment])
        #expect(quickActions(for: .needsAction) == [.open, .comment])
        #expect(quickActions(for: .needsYourReview) == [.open, .comment])
        // A snoozed row leads with Wake, whatever its origin section.
        #expect(quickActions(for: .readyToMerge, dormant: true) == [.snooze, .open])
        #expect(quickActions(for: .needsAction, dormant: true) == [.snooze, .open])
        #expect(allActions(for: .readyToMerge) == [.merge, .comment, .snooze, .open, .copyLink])
        #expect(allActions(for: .drafts).contains(.merge) == false)
        // A snoozed row leads with Wake in the menu too.
        #expect(allActions(for: .readyToMerge, dormant: true) == [.snooze, .merge, .comment, .open, .copyLink])
        #expect(allActions(for: .needsAction, dormant: true) == [.snooze, .comment, .open, .copyLink])
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
        let result = await store.merge(pr, method: .squash, deleteBranch: true)
        #expect(result == .success)
        let call = try #require(await gh.merges.first)
        #expect(call.url == pr.url)
        #expect(call.method == .squash)
        #expect(call.deleteBranch == true)
        #expect(call.matchHeadCommit == pr.headRefOid)
        // Right after: shown as merged, still in the list, already out of the badge.
        #expect(store.actionState(for: pr) == .succeeded(.merge))
        #expect(store.mine.value.contains(pr))
        #expect(store.badgeCount == 5)
        try await Task.sleep(for: .milliseconds(300))
        #expect(store.mine.value.contains(pr) == false)
        #expect(store.actionState(for: pr) == nil)
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
        #expect(await store.comment(pr, body: "Looks good") == .success)
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
    }
}
