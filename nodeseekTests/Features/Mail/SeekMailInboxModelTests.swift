import Foundation
import Testing
@testable import nodeseek

/// 地址都是假值。
@MainActor
struct SeekMailInboxModelTests {
    @Test func identicalUnreadSnapshotDoesNotRenderAgain() {
        let model = makeModel(SeekMailRouteTransport())
        var updates = 0
        model.onChange = { updates += 1 }
        let counts = SeekMailUnreadCounts(byMailbox: [1: 3], total: 3)
        model.applyUnreadCounts(counts)
        model.applyUnreadCounts(counts)
        #expect(updates == 1)
        model.applyUnreadCounts(SeekMailUnreadCounts(byMailbox: [1: 2], total: 2))
        #expect(updates == 2)
    }

    // MARK: - 显示名

    @Test func displayNamesUseLocalPartUnlessAliasOrCollision() throws {
        let mailboxes = try decodeMailboxes(#"""
        [{"id":1,"address":"me@seek.li"},{"id":2,"address":"me@nodeseek.org"},
         {"id":3,"address":"github-alt@seek.li"},{"id":4,"address":"billing@seek.li","alias":"  VMISS 账单 "},
         {"id":5,"address":"ME@example.com","alias":""}]
        """#)
        let names = SeekMailboxNaming.displays(for: mailboxes)

        // 不同域名下 @ 前相同（不分大小写），补上完整地址
        #expect(names[1] == SeekMailboxDisplay(title: "me@seek.li", domainSuffix: nil, address: "me@seek.li", hasAlias: false))
        #expect(names[2]?.title == "me@nodeseek.org")
        #expect(names[5]?.title == "ME@example.com")
        #expect(names[3] == SeekMailboxDisplay(title: "github-alt", domainSuffix: "@seek.li", address: "github-alt@seek.li", hasAlias: false))
        #expect(names[4] == SeekMailboxDisplay(title: "VMISS 账单", domainSuffix: nil, address: "billing@seek.li", hasAlias: true))
    }

    @Test func pickerGroupsPinnedThenUnreadThenOthers() throws {
        let mailboxes = try decodeMailboxes(#"""
        [{"id":1,"address":"zeta@seek.li"},{"id":2,"address":"alpha@seek.li"},
         {"id":3,"address":"pin@seek.li","isPinned":true},{"id":4,"address":"news@seek.li"},
         {"id":5,"address":"ordered@seek.li","sortOrder":1},{"id":6,"address":"bill@seek.li","alias":"Bills"}]
        """#)
        let names = SeekMailboxNaming.displays(for: mailboxes)
        let sections = SeekMailboxPickerSections.make(
            mailboxes: mailboxes, names: names, counts: [4: 3, 1: 0],
            recentIDs: [6, 99, 2, 1, 3], query: ""
        )
        #expect(sections.recents.map(\.mailboxID) == [6, 2, 1])
        #expect(sections.pinned.map(\.mailboxID) == [3])
        #expect(sections.unread == [.init(mailboxID: 4, unreadCount: 3)])
        // 有 sortOrder 的排在前面，其余按显示名字母排
        #expect(sections.others.map(\.mailboxID) == [5, 2, 6, 1])
        #expect(sections.isSearching == false)

        let search = SeekMailboxPickerSections.make(
            mailboxes: mailboxes, names: names, counts: [:], recentIDs: [6], query: " BILL "
        )
        #expect(search.isSearching)
        #expect(search.recents.isEmpty)
        #expect(search.others.map(\.mailboxID) == [6])
    }

    // MARK: - 选择记忆

    @Test func selectionStoreRemembersScopeAndRecents() {
        let store = makeSelectionStore()
        #expect(store.scope == .inbox)
        store.scope = .custom(42)
        [1, 2, 3, 1, 4].forEach(store.recordRecent)
        #expect(store.scope == .custom(42))
        #expect(store.recentMailboxIDs == [4, 1, 3])
        store.clear()
        #expect(store.scope == .inbox)
        #expect(store.recentMailboxIDs.isEmpty)
        #expect(SeekMailFolderScope(storageValue: "folder:x") == nil)
    }

    // MARK: - 加载

    @Test func loadsFirstPageWithRememberedFolderAndPaginates() async throws {
        let transport = SeekMailRouteTransport()
        transport.mailPages = [
            Self.page(ids: Array(1...20), total: 25, offset: 0),
            Self.page(ids: Array(21...25), total: 25, offset: 20)
        ]
        let selection = makeSelectionStore()
        selection.scope = .spam
        let model = makeModel(transport, selection: selection)

        model.start()
        await mailWaitUntil { model.phase == .loaded }
        #expect(model.mails.count == 20)
        #expect(model.hasMore)
        #expect(model.selectionTitle == "全部邮箱")
        let first = try #require(transport.requests.last { $0.url?.path.hasSuffix("/mails") == true })
        #expect(first.url?.query == "folder=spam&limit=20&offset=0")

        model.loadMoreIfNeeded()
        await mailWaitUntil { model.mails.count == 25 }
        #expect(model.hasMore == false)
        let second = try #require(transport.requests.last)
        #expect(second.url?.query == "folder=spam&limit=20&offset=20")
    }

    @Test func refreshDuringPaginationAllowsLoadingMoreAgain() async throws {
        let transport = SeekMailRouteTransport()
        transport.mailPages = [
            Self.page(ids: Array(1...20), total: 25, offset: 0),
            Self.page(ids: Array(1...20), total: 25, offset: 0),
            Self.page(ids: Array(21...25), total: 25, offset: 20)
        ]
        let model = makeModel(transport)
        model.start()
        await mailWaitUntil { model.phase == .loaded }
        transport.delayNanoseconds = 50_000_000
        model.loadMoreIfNeeded()
        await mailWaitUntil { transport.requests.filter { $0.url?.path.hasSuffix("/mails") == true }.count == 2 }
        #expect(model.isLoadingMore)
        transport.mailPages = [Self.page(ids: Array(1...20), total: 25, offset: 0)]
        // 分页仍在等待时刷新，新首页接管状态。
        model.reload()
        #expect(model.isLoadingMore == false)
        await mailWaitUntil {
            transport.requests.filter { $0.url?.path.hasSuffix("/mails") == true }.count >= 3
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        transport.mailPages = [Self.page(ids: Array(21...25), total: 25, offset: 20)]
        model.loadMoreIfNeeded()
        await mailWaitUntil { model.mails.count == 25 }
        #expect(model.isLoadingMore == false)
    }

    @Test func failedMoveDoesNotInsertMailIntoAnotherMailbox() async throws {
        let transport = SeekMailRouteTransport()
        var pendingMove: CheckedContinuation<Void, Error>?
        var failureReported = false
        let provider = SeekMailProvider<SeekMailAPI>(apiKey: { "sk_live_test" }, plugins: [], transport: { request in
            if request.httpMethod == "PUT", request.url?.path.hasSuffix("/folder") == true {
                try await withCheckedThrowingContinuation { pendingMove = $0 }
            }
            return try await transport.load(request)
        })
        let model = SeekMailInboxModel(provider: provider, selectionStore: makeSelectionStore())
        model.onMessage = { _ in failureReported = true }
        model.start()
        await mailWaitUntil { model.phase == .loaded }
        model.move(11, toFolderID: 42)
        await mailWaitUntil { pendingMove != nil }
        transport.mailPages = [Self.page(ids: [99], total: 1, offset: 0)]
        model.selectMailbox(2)
        await mailWaitUntil { model.mails.map(\.id) == [99] }
        pendingMove?.resume(throwing: URLError(.notConnectedToInternet))
        await mailWaitUntil { failureReported }
        #expect(model.mails.map(\.id) == [99])
    }

    @Test func reenteringStartsFromAllMailboxesAndForgetsMissingFolder() async {
        let selection = makeSelectionStore()
        selection.scope = .custom(5)
        let first = makeModel(SeekMailRouteTransport(), selection: selection)
        first.start()
        await mailWaitUntil { first.phase == .loaded }
        #expect(first.scope == .inbox)
        first.selectMailbox(2)
        #expect(first.selectedMailboxID == 2)

        // 重新进入时不记住上次的邮箱，默认「全部」
        let second = makeModel(SeekMailRouteTransport(), selection: selection)
        #expect(second.selectedMailboxID == nil)
        second.start()
        await mailWaitUntil { second.phase == .loaded }
        #expect(second.selectedMailboxID == nil)
        #expect(second.showsRecipientMailbox)
    }

    @Test func autoRefreshReloadsOnlyWhenCountsChangeAndRespectsQuota() async throws {
        let transport = SeekMailRouteTransport()
        transport.details["/openapi/v1/mails/counts"] = #"{"data":{"mailboxes":{"1":1},"total":1}}"#
        let selection = makeSelectionStore()
        #expect(selection.autoRefreshSeconds == 20)
        let model = makeModel(transport, selection: selection)
        model.start()
        await mailWaitUntil { model.phase == .loaded && model.unreadTotal == 1 }
        func count(_ suffix: String) -> Int { transport.requests.filter { $0.url?.path.hasSuffix(suffix) == true }.count }

        // 未读数没变：只查一次 counts，不拉列表
        let mailsBefore = count("/mails")
        let countsBefore = count("/counts")
        model.autoRefresh()
        await mailWaitUntil { count("/counts") == countsBefore + 1 }
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(count("/mails") == mailsBefore)

        // 有新邮件：未读数变了才刷新列表
        transport.details["/openapi/v1/mails/counts"] = #"{"data":{"mailboxes":{"1":2},"total":2}}"#
        model.autoRefresh()
        await mailWaitUntil { count("/mails") == mailsBefore + 1 }
        #expect(model.unreadTotal == 2)

        // 剩余额度不够时不自动刷新
        await mailWaitUntil { model.phase == .loaded }
        transport.headers = ["x-ratelimit-limit": "60", "x-ratelimit-remaining": "10"]
        model.reload()
        await mailWaitUntil { model.phase == .loaded && model.provider.rateLimit?.remaining == 10 }
        let countsLow = count("/counts")
        model.autoRefresh()
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(count("/counts") == countsLow)
    }

    @Test func unreadCountsDriveTagsAndFollowLocalReadChanges() async throws {
        let transport = SeekMailRouteTransport()
        transport.details["/openapi/v1/mails/counts"] = #"{"data":{"mailboxes":{"1":3},"total":3}}"#
        let model = SeekMailInboxModel(
            provider: SeekMailProvider(apiKey: { "sk_live_ok" }, transport: transport.load),
            selectionStore: makeSelectionStore()
        )
        model.start()
        await mailWaitUntil { model.phase == .loaded && model.unreadTotal == 3 }

        // 账单（2 号）有别名但没有未读，排在有未读的 1 号后面
        #expect(model.mailboxTags.map(\.id) == [nil, 1, 2])
        #expect(model.mailboxTags.map(\.countText) == [" (3)", " (3)", nil])

        // 本地标已读就地减一，不重排，也不再请求未读数
        let countRequests = transport.requests.filter { $0.url?.path.hasSuffix("/counts") == true }.count
        model.setRead(11, read: true)
        #expect(model.unreadTotal == 2)
        #expect(model.unreadByMailbox[1] == 2)
        #expect(model.mailboxTags.map(\.id) == [nil, 1, 2])
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(transport.requests.filter { $0.url?.path.hasSuffix("/counts") == true }.count == countRequests)
        #expect(SeekMailMailboxTag(id: 1, title: "a", unread: 120).countText == " (99+)")
    }

    @Test func searchAndScopeChangesQueryCurrentRange() async throws {
        let transport = SeekMailRouteTransport()
        let model = makeModel(transport)
        model.start()
        await mailWaitUntil { model.phase == .loaded }

        model.selectMailbox(1)
        model.selectScope(.trash)
        model.setSearchText("  invoice ")
        await mailWaitUntil { transport.requests.last?.url?.query?.contains("search") == true }
        await mailWaitUntil { model.phase == .loaded }
        let request = try #require(transport.requests.last)
        #expect(request.url?.query == "folder=trash&limit=20&mailbox_id=1&offset=0&search=invoice")
        #expect(model.isTrash)
        #expect(model.isSearching)
    }

    @Test func failureWithoutContentShowsRetryState() async {
        let transport = SeekMailRouteTransport()
        transport.status = 500
        transport.override = #"{"error":{"code":"SERVER","message":"服务异常"}}"#
        let model = makeModel(transport)
        model.start()
        await mailWaitUntil { model.phase != .loading }
        #expect(model.phase == .failed("服务异常"))
    }

    @Test func rateLimitKeepsListAndRecordsResetTime() async {
        let transport = SeekMailRouteTransport()
        let model = makeModel(transport)
        var messages: [String] = []
        model.onMessage = { messages.append($0) }
        model.start()
        await mailWaitUntil { model.phase == .loaded }

        transport.status = 429
        transport.override = #"{"error":{"code":"RATE_LIMITED","message":"太快了"}}"#
        model.reload()
        await mailWaitUntil { model.rateLimitedUntil != nil }
        #expect(model.phase == .loaded)
        #expect(model.mails.count == 2)
        // 限流用顶部倒计时条提示，不再弹 toast
        #expect(messages.isEmpty)
    }

    @Test func unauthorizedCallsBack() async {
        let transport = SeekMailRouteTransport()
        transport.status = 401
        transport.override = #"{"error":{"code":"UNAUTHORIZED","message":"无效"}}"#
        let model = makeModel(transport)
        var unauthorized = 0
        model.onUnauthorized = { unauthorized += 1 }
        model.start()
        await mailWaitUntil { unauthorized == 1 }
        #expect(unauthorized == 1)
    }

    // MARK: - 验证码

    @Test func codeCardShowsNewestFreshCodeOnly() async throws {
        let now = Date()
        let transport = SeekMailRouteTransport()
        transport.mailPages = [Self.list([
            Self.mail(id: 1, code: "111111", receivedAt: now.addingTimeInterval(-60)),
            Self.mail(id: 2, code: "222222", receivedAt: now.addingTimeInterval(-30)),
            Self.mail(id: 3, code: "333333", receivedAt: now.addingTimeInterval(-20 * 60)),
            Self.mail(id: 4, code: nil, receivedAt: now)
        ])]
        let model = makeModel(transport)
        model.start()
        await mailWaitUntil { model.phase == .loaded }
        #expect(model.latestCodeMail(now: now)?.id == 2)
        #expect(model.latestCodeMail(now: now.addingTimeInterval(30 * 60)) == nil)

        // 搜索时不显示卡片
        model.setSearchText("x")
        #expect(model.latestCodeMail(now: now) == nil)
    }

    // MARK: - 延迟删除

    @Test func deleteIsDelayedAndCanBeUndone() async throws {
        let transport = SeekMailRouteTransport()
        let model = makeModel(transport, deleteDelay: 0.3)
        model.start()
        await mailWaitUntil { model.phase == .loaded }

        model.scheduleDelete(11)
        #expect(model.mails.map(\.id) == [12])
        model.undoDelete(11)
        #expect(model.mails.map(\.id) == [11, 12])
        try await Task.sleep(nanoseconds: 450_000_000)
        #expect(transport.requests.contains { $0.httpMethod == "DELETE" } == false)

        model.scheduleDelete(12)
        await mailWaitUntil { transport.requests.contains { $0.httpMethod == "DELETE" } }
        await mailWaitUntil { model.hasPendingDeletes == false }
        #expect(transport.requests.last?.url?.path == "/openapi/v1/mails/12")
        #expect(model.mails.map(\.id) == [11])
    }

    @Test func commitDeletesImmediatelyAndRestoresOnFailure() async throws {
        let transport = SeekMailRouteTransport()
        let model = makeModel(transport, deleteDelay: 60)
        var messages: [String] = []
        model.onMessage = { messages.append($0) }
        model.start()
        await mailWaitUntil { model.phase == .loaded }

        transport.status = 404
        transport.override = #"{"error":"邮件不存在"}"#
        model.scheduleDelete(11)
        model.commitPendingDeletes()
        await mailWaitUntil { model.hasPendingDeletes == false }
        #expect(transport.requests.last?.httpMethod == "DELETE")
        // 删除失败，邮件重新出现
        #expect(model.mails.map(\.id) == [11, 12])
        #expect(messages == ["邮件不存在"])
    }

    @Test func trashIsReadOnly() async {
        let selection = makeSelectionStore()
        selection.scope = .trash
        let model = makeModel(SeekMailRouteTransport(), selection: selection)
        model.start()
        await mailWaitUntil { model.phase == .loaded }
        model.scheduleDelete(11)
        #expect(model.hasPendingDeletes == false)
        #expect(model.latestCodeMail() == nil)
    }

    @Test func markReadIsOptimisticAndRollsBack() async throws {
        let transport = SeekMailRouteTransport()
        let model = makeModel(transport)
        model.start()
        await mailWaitUntil { model.phase == .loaded }

        transport.status = 500
        transport.override = #"{"error":"失败"}"#
        model.setRead(11, read: true)
        #expect(model.mail(id: 11)?.isRead == true)
        await mailWaitUntil { model.mail(id: 11)?.isRead == false }
        #expect(model.mail(id: 11)?.isRead == false)
        let request = try #require(transport.requests.last)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/openapi/v1/mails/11/read")
    }

    // MARK: - 辅助

    private func makeModel(_ transport: SeekMailRouteTransport,
                           selection: SeekMailSelectionStore? = nil,
                           deleteDelay: TimeInterval = 4) -> SeekMailInboxModel {
        let provider = SeekMailProvider<SeekMailAPI>(apiKey: { "sk_live_test" }, plugins: [], transport: transport.load)
        return SeekMailInboxModel(provider: provider, selectionStore: selection ?? makeSelectionStore(), deleteDelay: deleteDelay)
    }

    private func decodeMailboxes(_ json: String) throws -> [SeekMailbox] {
        try SeekMailJSON.decoder.decode([SeekMailbox].self, from: Data(json.utf8))
    }

    private static func mail(id: Int, code: String?, receivedAt: Date) -> String {
        let formatter = ISO8601DateFormatter()
        let codeField = code.map { #","verificationCode":"\#($0)""# } ?? ""
        return #"{"id":\#(id),"mailboxId":1,"fromAddress":"a@example.com","subject":"s","bodyText":"b","receivedAt":"\#(formatter.string(from: receivedAt))"\#(codeField)}"#
    }

    private static func list(_ mails: [String]) -> String {
        #"{"data":[\#(mails.joined(separator: ","))],"pagination":{"total":\#(mails.count),"limit":20,"offset":0}}"#
    }

    private static func page(ids: [Int], total: Int, offset: Int) -> String {
        let mails = ids.map { #"{"id":\#($0),"mailboxId":1,"fromAddress":"a@example.com","subject":"s","bodyText":"b"}"# }
        return #"{"data":[\#(mails.joined(separator: ","))],"pagination":{"total":\#(total),"limit":20,"offset":\#(offset)}}"#
    }
}
