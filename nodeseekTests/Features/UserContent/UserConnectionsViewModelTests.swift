import Foundation
import Testing
@testable import nodeseek

@MainActor
struct UserConnectionsViewModelTests {
    @Test func tabsLoadAndCacheIndependently() async {
        let client = ConnectionsStub()
        client.responses[.following] = [.success([person(9)])]
        client.responses[.followers] = [.success([person(14496)])]
        let model = UserConnectionsViewModel(client: client)
        await model.load(.following)
        await model.load(.followers)
        await model.load(.following)
        #expect(client.calls == [.following, .followers])
        #expect(model.state(for: .following).records.first?.uid == 9)
        #expect(model.state(for: .followers).records.first?.uid == 14496)
    }

    @Test func failureAndRefreshPreserveOtherTabAndCachedMembers() async {
        let client = ConnectionsStub()
        client.responses[.following] = [.success([person(9)]), .failure(URLError(.timedOut)), .success([person(10)])]
        client.responses[.followers] = [.failure(URLError(.notConnectedToInternet)), .success([])]
        let model = UserConnectionsViewModel(client: client)
        await model.load(.following)
        await model.load(.followers)
        #expect(model.state(for: .followers).errorMessage != nil)
        #expect(!model.state(for: .followers).showsSkeleton)
        await model.load(.following, refresh: true)
        #expect(model.state(for: .following).records.first?.uid == 9)
        #expect(model.state(for: .following).errorMessage != nil)
        await model.load(.followers, refresh: true)
        #expect(model.state(for: .followers).hasLoaded)
        #expect(model.state(for: .followers).records.isEmpty)
        await model.load(.following, refresh: true)
        #expect(model.state(for: .following).records.first?.uid == 10)
        #expect(model.state(for: .following).errorMessage == nil)
    }

    @Test func simultaneousTabsDoNotOverwriteEachOtherOrDuplicateRequests() async {
        let client = ConnectionsStub()
        client.suspend = [.following, .followers]
        let model = UserConnectionsViewModel(client: client)
        let following = Task { await model.load(.following) }
        let followers = Task { await model.load(.followers) }
        while client.pending.count < 2 { await Task.yield() }
        await model.load(.following)
        #expect(client.calls.count == 2)
        client.pending.removeValue(forKey: .followers)?.resume(returning: [person(11)])
        await followers.value
        #expect(model.state(for: .following).isLoading)
        client.pending.removeValue(forKey: .following)?.resume(returning: [person(9)])
        await following.value
        #expect(model.state(for: .followers).records.first?.uid == 11)
        #expect(model.state(for: .following).records.first?.uid == 9)
    }

    @Test func unfollowKeepsRowAndUpdatesSamePersonInBothLists() async {
        let client = ConnectionsStub()
        client.responses[.following] = [.success([person(9, followed: true)])]
        client.responses[.followers] = [.success([person(9, followed: true), person(11, followed: false)])]
        let model = UserConnectionsViewModel(client: client)
        await model.load(.following)
        await model.load(.followers)
        #expect(await model.toggleFollow(uid: 9) == nil)
        #expect(client.followCalls.first?.0 == false)
        #expect(model.state(for: .following).records.map(\.uid) == [9])
        #expect(model.state(for: .following).records.first?.followed == false)
        #expect(model.state(for: .followers).records.first?.followed == false)
        #expect(model.pendingUIDs.isEmpty)
    }

    @Test func followingBackMarksFollowingListStaleAndFailureKeepsState() async {
        let client = ConnectionsStub()
        client.responses[.following] = [.success([person(9, followed: true)]), .success([person(9, followed: true), person(11, followed: true)])]
        client.responses[.followers] = [.success([person(11, followed: false)])]
        let model = UserConnectionsViewModel(client: client)
        await model.load(.following)
        await model.load(.followers)
        client.followError = UserContentClientError.rejected("操作太频繁")
        #expect(await model.toggleFollow(uid: 11) == "操作太频繁")
        #expect(model.state(for: .followers).records.first?.followed == false)
        #expect(!model.state(for: .following).isStale)
        client.followError = nil
        #expect(await model.toggleFollow(uid: 11) == nil)
        #expect(client.followCalls.last?.0 == true)
        #expect(model.state(for: .followers).records.first?.followed == true)
        #expect(model.state(for: .following).isStale)
        await model.load(.following)
        #expect(model.state(for: .following).records.map(\.uid) == [9, 11])
        #expect(!model.state(for: .following).isStale)
    }

    @Test func oldResponseCannotUndoRefresh() async {
        let client = ConnectionsStub()
        client.suspend = [.following]
        let model = UserConnectionsViewModel(client: client)
        let old = Task { await model.load(.following) }
        while client.pending[.following] == nil { await Task.yield() }
        client.responses[.following] = [.success([person(10)])]
        await model.load(.following, refresh: true)
        client.pending.removeValue(forKey: .following)?.resume(returning: [person(9)])
        await old.value
        #expect(model.state(for: .following).records.first?.uid == 10)
        #expect(!model.state(for: .following).isLoading)
    }
}

@MainActor
private final class ConnectionsStub: UserConnectionsLoading {
    var responses: [UserConnectionKind: [Result<[UserConnectionRecord], Error>]] = [:]
    var calls: [UserConnectionKind] = []
    var suspend: Set<UserConnectionKind> = []
    var pending: [UserConnectionKind: CheckedContinuation<[UserConnectionRecord], Error>] = [:]
    func loadConnections(kind: UserConnectionKind) async throws -> [UserConnectionRecord] {
        calls.append(kind)
        if suspend.remove(kind) != nil { return try await withCheckedThrowingContinuation { pending[kind] = $0 } }
        return try responses[kind]!.removeFirst().get()
    }
    var followCalls: [(Bool, Int)] = []
    var followError: Error?
    func setFollowing(_ follow: Bool, uid: Int) async throws {
        followCalls.append((follow, uid))
        if let followError { throw followError }
    }
}

private func person(_ uid: Int, followed: Bool? = nil) -> UserConnectionRecord {
    UserConnectionRecord(uid: uid, name: "用户\(uid)", rank: 4, coin: 1758, stardust: 11, bio: nil, postCount: 19, commentCount: 550, fans: 2, followed: followed)
}
