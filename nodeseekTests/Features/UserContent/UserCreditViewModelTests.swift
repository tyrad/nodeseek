import Foundation
import Testing
@testable import nodeseek

@MainActor
struct UserCreditViewModelTests {
    @Test func failedPageKeepsDataAndRetriesPageNumber() async {
        let client = CreditStub()
        client.results = [.success(page([record(10)], total: 21)), .failure(URLError(.timedOut)), .success(page([record(9)], total: 21))]
        let model = UserCreditViewModel(uid: 31037, client: client)
        await model.load(refresh: true)
        await model.load(refresh: false)
        #expect(model.records.map(\.balance) == [10])
        #expect(model.loadedPage == 1)
        #expect(model.errorMessage != nil)
        await model.load(refresh: false)
        #expect(client.pages == [1, 2, 2])
        #expect(model.records.map(\.balance) == [10, 9])
        #expect(!model.hasMore)
        await model.load(refresh: false)
        #expect(client.pages.count == 3)
    }

    @Test func refreshReplacesDataAndPreservesIdenticalTransactions() async {
        let client = CreditStub()
        client.results = [.success(page([record(10), record(10)], total: 21)), .success(page([record(9)], total: 21)), .success(page([record(11)], total: 1))]
        let model = UserCreditViewModel(uid: 31037, client: client)
        await model.load(refresh: true)
        #expect(model.records.count == 2)
        await model.load(refresh: false)
        #expect(model.records.map(\.balance) == [10, 10, 9])
        await model.load(refresh: true)
        #expect(model.records.map(\.balance) == [11])
        #expect(client.pages == [1, 2, 1])
    }

    @Test func emptyAccountDoesNotInventABalance() async {
        let client = CreditStub()
        client.results = [.success(page([], total: 0))]
        let model = UserCreditViewModel(uid: 31037, client: client)
        await model.load(refresh: true)
        await model.refreshProfile()
        #expect(model.hasLoaded)
        #expect(model.profile == nil)
        #expect(!model.hasMore)
        #expect(model.errorMessage == nil)
    }

    @Test func unexpectedEmptyPageCanBeRetried() async {
        let client = CreditStub()
        client.results = [.success(page([], total: 21))]
        let model = UserCreditViewModel(uid: 31037, client: client)
        await model.load(refresh: true)
        #expect(model.loadedPage == 0)
        #expect(model.failedRefresh)
        #expect(model.errorMessage != nil)
    }

    @Test func refreshFailureAfterEndPreservesDataAndRetryIntent() async {
        let client = CreditStub()
        client.results = [.success(page([record(10)], total: 1)), .failure(URLError(.timedOut)), .success(page([record(11)], total: 1))]
        let model = UserCreditViewModel(uid: 31037, client: client)
        await model.load(refresh: true)
        await model.load(refresh: true)
        #expect(model.failedRefresh)
        #expect(!model.hasMore)
        #expect(model.records.map(\.balance) == [10])
        await model.load(refresh: true)
        #expect(!model.failedRefresh)
        #expect(model.records.map(\.balance) == [11])
    }

    @Test func stalePageCannotOverwriteRefreshedData() async {
        let client = CreditStub()
        client.results = [.success(page([record(10)], total: 21))]
        let model = UserCreditViewModel(uid: 31037, client: client)
        await model.load(refresh: true)
        client.suspendNext = true
        let old = Task { await model.load(refresh: false) }
        while client.pending == nil { await Task.yield() }
        client.results = [.success(page([record(11)], total: 1))]
        await model.load(refresh: true)
        client.pending?.resume(returning: page([record(9)], total: 21))
        client.pending = nil
        await old.value
        #expect(model.records.map(\.balance) == [11])
        #expect(model.loadedPage == 1)
        #expect(!model.isLoading)
    }
}

@MainActor
private final class CreditStub: UserCreditLoading {
    var pages: [Int] = []
    var results: [Result<UserCreditPage, Error>] = []
    var suspendNext = false
    var pending: CheckedContinuation<UserCreditPage, Error>?
    func loadCredits(page: Int) async throws -> UserCreditPage {
        pages.append(page)
        if suspendNext {
            suspendNext = false
            return try await withCheckedThrowingContinuation { pending = $0 }
        }
        return try results.removeFirst().get()
    }
    func loadProfile(uid: Int) async throws -> UserProfileRecord { throw URLError(.notConnectedToInternet) }
}

private func record(_ balance: Int) -> UserCreditRecord {
    UserCreditRecord(diff: 1, balance: balance, reason: "回帖奖励", createdAt: "2026-10-30T01:06:08.000Z")
}
private func page(_ records: [UserCreditRecord], total: Int) -> UserCreditPage { UserCreditPage(records: records, total: total) }
