import XCTest
@testable import nodeseek

@MainActor
final class VoteViewModelTests: XCTestCase {
    func testSingleAndMultipleSelections() async {
        let service = VoteTestService()
        let model = VoteViewModel(id: 3108, service: service)
        await model.refresh()
        model.select(14131)
        model.select(14132)
        XCTAssertEqual(model.selected, [14132])
        XCTAssertTrue(model.canSubmit)
        model.select(999)
        XCTAssertEqual(model.selected, [14132])
        service.vote = VoteTestService.makeVote(multiple: true)
        await model.refresh()
        model.select(14131)
        XCTAssertEqual(model.selected, [14131, 14132])
        model.select(14131)
        XCTAssertEqual(model.selected, [14132])
    }

    func testSubmissionReloadsResultsAndPreventsSecondVote() async {
        let service = VoteTestService()
        let model = VoteViewModel(id: 3108, service: service)
        await model.refresh()
        model.select(14131)
        await model.submit()
        XCTAssertEqual(service.submitted, [[14131]])
        XCTAssertEqual(model.vote?.hasVoted, true)
        XCTAssertFalse(model.canSubmit)
        await model.submit()
        XCTAssertEqual(service.submitted.count, 1)
    }

    func testTimedOutSubmissionMayAlreadyHaveSucceeded() async {
        let service = VoteTestService()
        service.submitError = URLError(.timedOut)
        let model = VoteViewModel(id: 3108, service: service)
        await model.refresh()
        model.select(14131)
        await model.submit()
        XCTAssertEqual(model.message, "已投票")
        XCTAssertEqual(service.submitted.count, 1)
        XCTAssertFalse(model.canSubmit)
    }

    func testUncertainSubmissionBlocksRetryUntilSuccessfulRead() async {
        let service = VoteTestService()
        service.failsReloadAfterSubmit = true
        let model = VoteViewModel(id: 3108, service: service)
        await model.refresh()
        model.select(14131)
        await model.submit()
        XCTAssertTrue(model.requiresRefresh)
        XCTAssertFalse(model.canSubmit)
        await model.submit()
        XCTAssertEqual(service.submitted.count, 1)
        service.loadError = nil
        await model.refresh()
        XCTAssertEqual(model.vote?.hasVoted, true)
        XCTAssertFalse(model.requiresRefresh)
    }

    func testLockedAndFailedLoadsDisableSubmission() async {
        let service = VoteTestService()
        service.vote = VoteTestService.makeVote(locked: true)
        let model = VoteViewModel(id: 3108, service: service)
        await model.refresh()
        model.select(14131)
        XCTAssertFalse(model.canSubmit)
        service.vote = VoteTestService.makeVote()
        await model.refresh()
        model.select(14131)
        service.loadError = URLError(.notConnectedToInternet)
        await model.refresh()
        XCTAssertFalse(model.canSubmit)
    }

    func testVisibilityAndServiceIdentityControlAutomaticRefresh() async {
        let service = VoteTestService()
        let otherService = VoteTestService()
        let model = VoteViewModel(id: 3108, service: service)
        model.setVisible(true)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(service.loadCount, 1)
        NotificationCenter.default.post(name: .nodeSeekVoteDidChange, object: otherService, userInfo: ["voteID": 3108])
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(service.loadCount, 1)
        NotificationCenter.default.post(name: .nodeSeekVoteDidChange, object: service, userInfo: ["voteID": 3108])
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(service.loadCount, 2)
        model.setVisible(false)
        NotificationCenter.default.post(name: .nodeSeekVoteDidChange, object: service, userInfo: ["voteID": 3108])
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(service.loadCount, 2)
        model.setVisible(true)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(service.loadCount, 3)
    }

    func testAccountChangeDiscardsInFlightResult() async {
        let service = VoteTestService()
        let model = VoteViewModel(id: 3108, service: service)
        service.onLoad = { model.resetSession() }
        await model.refresh()
        XCTAssertNil(model.vote)
        XCTAssertFalse(model.canSubmit)
    }
}

@MainActor
final class VoteTestService: NodeSeekVoteServing {
    var vote = makeVote()
    var submitted: [Set<Int>] = []
    var loadError: Error?
    var submitError: Error?
    var failsReloadAfterSubmit = false
    var onLoad: (() -> Void)?
    var loadDelayNanoseconds: UInt64 = 0
    var loadCount = 0
    var notifiesChanges = false

    func load(id: Int) async throws -> NodeSeekVote {
        loadCount += 1
        if loadDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: loadDelayNanoseconds) }
        onLoad?()
        if let loadError { throw loadError }
        return vote
    }

    func submit(id: Int, ids: Set<Int>) async throws {
        submitted.append(ids)
        vote = Self.makeVote(voted: true)
        if notifiesChanges { NotificationCenter.default.post(name: .nodeSeekVoteDidChange, object: self, userInfo: ["voteID": id]) }
        if failsReloadAfterSubmit { loadError = URLError(.timedOut) }
        if let submitError { throw submitError }
    }

    static func makeVote(multiple: Bool = false, locked: Bool = false, voted: Bool = false) -> NodeSeekVote {
        NodeSeekVote(id: 3108, title: "大家订阅 codex 的哪种套餐", multiple: multiple, isPublic: true, locked: locked, items: [
            .init(vote_item_id: 14131, text: "plus", voted: voted, count: voted ? 12 : nil),
            .init(vote_item_id: 14132, text: "pro", voted: false, count: voted ? 8 : nil),
            .init(vote_item_id: 14133, text: "free", voted: false, count: voted ? 3 : nil),
            .init(vote_item_id: 14134, text: "中转", voted: false, count: voted ? 1 : nil)
        ])
    }
}
