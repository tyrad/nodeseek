import Foundation
import Testing
@testable import nodeseek

@Suite(.serialized)
@MainActor
struct ThreadedReplyCoordinatorTests {
    private static let postID = "12000"

    @Test func closeCancelsPendingScanAndReopeningAnotherRootReusesCompletedPages() async throws {
        let fetcher = ControllablePageFetcher(pages: Self.makeThreePageMap())
        fetcher.pausesPages = [3]

        let coordinator = ThreadedReplyCoordinator(
            postID: Self.postID,
            pageFetcher: fetcher,
            sessionStore: NodeSeekSessionStore(),
            accountFingerprintProvider: { Self.guestFingerprint },
            sleep: { _ in },
            configuration: .init(pagesPerBurst: 3, burstPauseNanoseconds: 0, maxPagesPerAutoRun: 20)
        )

        // 正常阅读第 1 页
        _ = try await coordinator.loadPageForMainDetail(page: 1)
        #expect(await fetcher.recordedPages() == [1])

        // 打开 #3，第 2 页自动完成，第 3 页挂起
        var snapshotsFor3: [ThreadedReplyPanelSnapshot] = []
        let sub3 = try #require(coordinator.startViewing(rootComment: Self.comment(floor: 3)) {
            snapshotsFor3.append($0)
        })

        try await Self.waitUntil {
            await fetcher.isPaused(onPage: 3)
        }
        #expect(snapshotsFor3.last?.nodes.map(\.floor) == [8, 15, 18])

        // 第 3 页挂起时关闭面板：取消第 3 页，不再发后续页
        coordinator.stopViewing(subscriptionID: sub3)
        try await Self.waitUntil {
            await fetcher.cancelledPages().contains(3)
        }
        #expect(await fetcher.recordedPages() == [1, 2, 3])

        // 重新打开 #9：立即看到第 2 页已索引的 #19，仅补拉第 3 页
        fetcher.pausesPages = []
        var snapshotsFor9: [ThreadedReplyPanelSnapshot] = []
        let sub9 = try #require(coordinator.startViewing(rootComment: Self.comment(floor: 9)) {
            snapshotsFor9.append($0)
        })
        #expect(snapshotsFor9.first?.nodes.map(\.floor) == [19])

        try await Self.waitUntil {
            snapshotsFor9.last?.state == .completed
        }
        #expect(snapshotsFor9.last?.nodes.map(\.floor) == [19])
        #expect(await fetcher.recordedPages() == [1, 2, 3, 3])
        coordinator.stopViewing(subscriptionID: sub9)
    }

    @Test func deduplicatesConcurrentMainReadAndScanAndKeepsMainReadAliveOnClose() async throws {
        let fetcher = ControllablePageFetcher(pages: Self.makeThreePageMap())
        fetcher.pausesPages = [2]

        let coordinator = ThreadedReplyCoordinator(
            postID: Self.postID,
            pageFetcher: fetcher,
            sessionStore: NodeSeekSessionStore(),
            accountFingerprintProvider: { Self.guestFingerprint },
            sleep: { _ in },
            configuration: .init(pagesPerBurst: 3, burstPauseNanoseconds: 0, maxPagesPerAutoRun: 20)
        )

        _ = try await coordinator.loadPageForMainDetail(page: 1)

        var snapshots: [ThreadedReplyPanelSnapshot] = []
        let sub = try #require(coordinator.startViewing(rootComment: Self.comment(floor: 3)) {
            snapshots.append($0)
        })

        try await Self.waitUntil {
            await fetcher.isPaused(onPage: 2)
        }

        // 普通阅读同时请求第 2 页
        let mainReadTask = Task {
            try await coordinator.loadPageForMainDetail(page: 2)
        }
        try await Task.sleep(nanoseconds: 20_000_000)

        // 关闭面板，普通阅读仍在等待 -> 底层请求不取消且只发起过 1 次第 2 页
        coordinator.stopViewing(subscriptionID: sub)
        await fetcher.resume(page: 2)

        let mainResult = try await mainReadTask.value
        guard case .value(let page2) = mainResult else {
            Issue.record("普通阅读应收到共享的第 2 页结果")
            return
        }
        #expect(page2.page == 2)
        #expect(await fetcher.recordedPages() == [1, 2])
    }

    @Test func completedScanSwitchesRootsWithZeroAdditionalRequests() async throws {
        let fetcher = ControllablePageFetcher(pages: Self.makeThreePageMap())
        let coordinator = ThreadedReplyCoordinator(
            postID: Self.postID,
            pageFetcher: fetcher,
            sessionStore: NodeSeekSessionStore(),
            accountFingerprintProvider: { Self.guestFingerprint },
            sleep: { _ in },
            configuration: .init(pagesPerBurst: 3, burstPauseNanoseconds: 0, maxPagesPerAutoRun: 20)
        )

        var snap3: ThreadedReplyPanelSnapshot?
        let sub3 = try #require(coordinator.startViewing(rootComment: Self.comment(floor: 3)) { snap3 = $0 })
        try await Self.waitUntil { snap3?.state == .completed }
        #expect(snap3?.nodes.map(\.floor) == [8, 15, 18, 23, 27])
        #expect(snap3?.replyCount == 5)
        coordinator.stopViewing(subscriptionID: sub3)

        #expect(await fetcher.recordedPages() == [1, 2, 3])

        // 切换到 #8、#9、#27 均零新增请求
        for (floor, expected) in [(8, [15, 18]), (9, [19]), (27, [])] {
            var latest: ThreadedReplyPanelSnapshot?
            let sub = try #require(coordinator.startViewing(rootComment: Self.comment(floor: floor)) { latest = $0 })
            #expect(latest?.state == .completed)
            #expect(latest?.nodes.map(\.floor) == expected)
            try await Task.sleep(nanoseconds: 20_000_000)
            coordinator.stopViewing(subscriptionID: sub)
        }
        #expect(await fetcher.recordedPages() == [1, 2, 3])
    }

    @Test func enteringFromPageTwoFetchesMissingAncestorPageFirstAndSkipsItForIndependentFloor() async throws {
        // 1. 焦点楼 #15 本身回复第 1 页的 #8：先补查第 1 页展示上游 [3, 8]，再补第 2、3 页，之后切到 #3 零新增请求。
        let fetcher = ControllablePageFetcher(pages: Self.makeThreePageMap())
        let coordinator = ThreadedReplyCoordinator(
            postID: Self.postID,
            pageFetcher: fetcher,
            sessionStore: NodeSeekSessionStore(),
            accountFingerprintProvider: { Self.guestFingerprint },
            sleep: { _ in },
            configuration: .init(pagesPerBurst: 3, burstPauseNanoseconds: 0, maxPagesPerAutoRun: 20)
        )

        _ = try await coordinator.loadPageForMainDetail(page: 2)
        var snap15: ThreadedReplyPanelSnapshot?
        let sub15 = try #require(coordinator.startViewing(rootComment: Self.comment(floor: 15, author: "Kero", markdown: "@Alice [#8](/post-12000-1#8) 有延迟数据吗？")) { snap15 = $0 })
        try await Self.waitUntil { snap15?.state == .completed }
        #expect(snap15?.ancestors.map(\.floor) == [3, 8])
        #expect(snap15?.rootDisplayedParentFloor == 8)
        #expect(snap15?.nodes.map(\.floor) == [18])
        #expect(await fetcher.recordedPages() == [2, 1, 3])
        coordinator.stopViewing(subscriptionID: sub15)

        var snap3: ThreadedReplyPanelSnapshot?
        let sub3 = try #require(coordinator.startViewing(rootComment: Self.comment(floor: 3)) { snap3 = $0 })
        try await Self.waitUntil { snap3?.state == .completed }
        #expect(snap3?.nodes.map(\.floor) == [8, 15, 18, 23, 27])
        #expect(await fetcher.recordedPages() == [2, 1, 3])
        coordinator.stopViewing(subscriptionID: sub3)

        // 2. 从第 2 页点开没有上游父楼的 #12：仅扫 [2, 3]，不误查第 1 页。
        let fetcher2 = ControllablePageFetcher(pages: Self.makeThreePageMap())
        let coordinator2 = ThreadedReplyCoordinator(
            postID: Self.postID,
            pageFetcher: fetcher2,
            sessionStore: NodeSeekSessionStore(),
            accountFingerprintProvider: { Self.guestFingerprint },
            sleep: { _ in },
            configuration: .init(pagesPerBurst: 3, burstPauseNanoseconds: 0, maxPagesPerAutoRun: 20)
        )
        var snap12: ThreadedReplyPanelSnapshot?
        let sub12 = try #require(coordinator2.startViewing(rootComment: Self.comment(floor: 12, author: "Solo", markdown: "独立评论")) { snap12 = $0 })
        try await Self.waitUntil { snap12?.state == .completed }
        #expect(snap12?.ancestors.isEmpty == true)
        #expect(await fetcher2.recordedPages() == [2, 3])
        coordinator2.stopViewing(subscriptionID: sub12)
    }

    @Test func failureAndCloudflareChallengePauseAndRetryResumesFromMissingPage() async throws {
        let fetcher = ControllablePageFetcher(pages: Self.makeThreePageMap())
        fetcher.failOncePages = [2: .challenge(.cloudflare(URL(string: "https://www.nodeseek.com/post-12000-2")!))]

        let sessionStore = NodeSeekSessionStore()
        let coordinator = ThreadedReplyCoordinator(
            postID: Self.postID,
            pageFetcher: fetcher,
            sessionStore: sessionStore,
            accountFingerprintProvider: { Self.guestFingerprint },
            sleep: { _ in },
            configuration: .init(pagesPerBurst: 3, burstPauseNanoseconds: 0, maxPagesPerAutoRun: 20)
        )

        var latest: ThreadedReplyPanelSnapshot?
        let sub = try #require(coordinator.startViewing(rootComment: Self.comment(floor: 3)) { latest = $0 })
        try await Self.waitUntil {
            if case .failed = latest?.state { return true }
            return false
        }
        // 失败后保留已找到的 #8，不提前报完成或空态
        #expect(latest?.nodes.map(\.floor) == [8])
        #expect(await fetcher.recordedPages() == [1, 2])

        coordinator.retry(subscriptionID: sub)
        try await Self.waitUntil { latest?.state == .completed }
        #expect(latest?.nodes.map(\.floor) == [8, 15, 18, 23, 27])
        #expect(await fetcher.recordedPages() == [1, 2, 2, 3])
        coordinator.stopViewing(subscriptionID: sub)
    }

    @Test func throttlesInBurstsStopsAtBatchLimitAndCancelsDuringSleep() async throws {
        let pages = Self.makeMultiPageMap(totalPages: 7)
        let fetcher = ControllablePageFetcher(pages: pages)
        let sleepGate = ControllableSleepGate()

        let coordinator = ThreadedReplyCoordinator(
            postID: Self.postID,
            pageFetcher: fetcher,
            sessionStore: NodeSeekSessionStore(),
            accountFingerprintProvider: { Self.guestFingerprint },
            sleep: { ns in try await sleepGate.sleep(nanoseconds: ns) },
            configuration: .init(pagesPerBurst: 3, burstPauseNanoseconds: 800_000_000, maxPagesPerAutoRun: 5)
        )

        var latest: ThreadedReplyPanelSnapshot?
        let sub = try #require(coordinator.startViewing(rootComment: Self.comment(floor: 1)) { latest = $0 })

        // 连续拉取 3 页后应进入节流停顿
        try await Self.waitUntil { await sleepGate.isSleeping() }
        #expect(await fetcher.recordedPages() == [1, 2, 3])

        // 放行停顿，拉完第 4、5 页后命中单轮上限 5 页暂停
        await sleepGate.resumeNext()
        try await Self.waitUntil {
            if case .pausedAtBatchLimit = latest?.state { return true }
            return false
        }
        #expect(await fetcher.recordedPages() == [1, 2, 3, 4, 5])

        // 点击继续查找后完成剩余 6、7 页
        coordinator.continueScanning(subscriptionID: sub)
        try await Self.waitUntil { latest?.state == .completed }
        #expect(await fetcher.recordedPages() == [1, 2, 3, 4, 5, 6, 7])
        coordinator.stopViewing(subscriptionID: sub)

        // 另测在节流停顿期间关闭面板：不会偷发第 4 页
        let fetcher2 = ControllablePageFetcher(pages: pages)
        let sleepGate2 = ControllableSleepGate()
        let coordinator2 = ThreadedReplyCoordinator(
            postID: Self.postID,
            pageFetcher: fetcher2,
            sessionStore: NodeSeekSessionStore(),
            accountFingerprintProvider: { Self.guestFingerprint },
            sleep: { ns in try await sleepGate2.sleep(nanoseconds: ns) },
            configuration: .init(pagesPerBurst: 3, burstPauseNanoseconds: 800_000_000, maxPagesPerAutoRun: 20)
        )
        let sub2 = try #require(coordinator2.startViewing(rootComment: Self.comment(floor: 1)) { _ in })
        try await Self.waitUntil { await sleepGate2.isSleeping() }
        coordinator2.stopViewing(subscriptionID: sub2)
        await sleepGate2.resumeNext()
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(await fetcher2.recordedPages() == [1, 2, 3])
    }

    @Test func replyGrowthRechecksOldLastPageAndFetchesNewFourthPage() async throws {
        var pages = Self.makeThreePageMap()
        let fetcher = ControllablePageFetcher(pages: pages)
        let coordinator = ThreadedReplyCoordinator(
            postID: Self.postID,
            pageFetcher: fetcher,
            sessionStore: NodeSeekSessionStore(),
            accountFingerprintProvider: { Self.guestFingerprint },
            sleep: { _ in },
            configuration: .init(pagesPerBurst: 3, burstPauseNanoseconds: 0, maxPagesPerAutoRun: 20)
        )

        var latest: ThreadedReplyPanelSnapshot?
        let sub = try #require(coordinator.startViewing(rootComment: Self.comment(floor: 3)) { latest = $0 })
        try await Self.waitUntil { latest?.state == .completed }
        coordinator.stopViewing(subscriptionID: sub)
        #expect(await fetcher.recordedPages() == [1, 2, 3])

        // 模拟发评后末页增长且翻到第 4 页
        let page3WithNext = Self.makePage(
            page: 3,
            totalPages: 4,
            nextPage: 4,
            comments: (pages[3]?.comments ?? []) + [
                Self.comment(floor: 28, author: "New1", markdown: "@Mori [#3](/post-12000-1#3) 第 3 页新增")
            ]
        )
        let page4 = Self.makePage(
            page: 4,
            totalPages: 4,
            nextPage: nil,
            comments: [
                Self.comment(floor: 31, author: "New2", markdown: "@Mori [#3](/post-12000-1#3) 第 4 页新增")
            ]
        )
        pages[3] = page3WithNext
        pages[4] = page4
        await fetcher.updatePages(pages)

        coordinator.markLastPageStaleForGrowth()
        let subAgain = try #require(coordinator.startViewing(rootComment: Self.comment(floor: 3)) { latest = $0 })
        try await Self.waitUntil { latest?.state == .completed }
        #expect(latest?.nodes.map(\.floor) == [8, 15, 18, 23, 27, 28, 31])
        // 前两页不重取，仅复查第 3 页并拉第 4 页
        #expect(await fetcher.recordedPages() == [1, 2, 3, 3, 4])
        coordinator.stopViewing(subscriptionID: subAgain)
    }

    @Test func guestLoginInvalidatesCachedSessionEvenWhenSessionIDUnchanged() async throws {
        let sharedSessionID = UUID()
        let authState = MutableFingerprintBox(
            ThreadedReplyAccountFingerprint(sessionID: sharedSessionID, isLoggedIn: false, displayName: "游客", profileURL: nil)
        )
        let fetcher = ControllablePageFetcher(pages: Self.makeThreePageMap())
        let coordinator = ThreadedReplyCoordinator(
            postID: Self.postID,
            pageFetcher: fetcher,
            sessionStore: NodeSeekSessionStore(),
            accountFingerprintProvider: { await authState.value },
            sleep: { _ in },
            configuration: .init(pagesPerBurst: 3, burstPauseNanoseconds: 0, maxPagesPerAutoRun: 20)
        )

        var latest: ThreadedReplyPanelSnapshot?
        let sub1 = try #require(coordinator.startViewing(rootComment: Self.comment(floor: 3)) { latest = $0 })
        try await Self.waitUntil { latest?.state == .completed }
        coordinator.stopViewing(subscriptionID: sub1)
        #expect(await fetcher.recordedPages() == [1, 2, 3])

        // 模拟游客直接登录成功（sessionID 不变，但 isLoggedIn / displayName 改变）
        await authState.set(
            ThreadedReplyAccountFingerprint(
                sessionID: sharedSessionID,
                isLoggedIn: true,
                displayName: "mist",
                profileURL: URL(string: "https://www.nodeseek.com/space/100")
            )
        )

        var latestAfterLogin: ThreadedReplyPanelSnapshot?
        let sub2 = try #require(coordinator.startViewing(rootComment: Self.comment(floor: 3)) { latestAfterLogin = $0 })
        try await Self.waitUntil {
            await fetcher.recordedPages().count == 6 && latestAfterLogin?.state == .completed
        }
        #expect(await fetcher.recordedPages() == [1, 2, 3, 1, 2, 3])
        coordinator.stopViewing(subscriptionID: sub2)
    }

    @Test func accountChangeDuringMainDetailLoadStillDeliversResultToMainList() async throws {
        let sharedSessionID = UUID()
        let authState = MutableFingerprintBox(
            ThreadedReplyAccountFingerprint(sessionID: sharedSessionID, isLoggedIn: false, displayName: "游客", profileURL: nil)
        )
        let fetcher = ControllablePageFetcher(pages: Self.makeThreePageMap())
        fetcher.pausesPages = [1]

        let coordinator = ThreadedReplyCoordinator(
            postID: Self.postID,
            pageFetcher: fetcher,
            sessionStore: NodeSeekSessionStore(),
            accountFingerprintProvider: { await authState.value },
            sleep: { _ in },
            configuration: .init(pagesPerBurst: 3, burstPauseNanoseconds: 0, maxPagesPerAutoRun: 20)
        )

        let mainLoadTask = Task {
            try await coordinator.loadPageForMainDetail(page: 1)
        }
        try await Self.waitUntil { await fetcher.isPaused(onPage: 1) }

        // 模拟请求过程中 opportunistic account 更新了本地账号快照
        await authState.set(
            ThreadedReplyAccountFingerprint(
                sessionID: sharedSessionID,
                isLoggedIn: true,
                displayName: "mist",
                profileURL: URL(string: "https://www.nodeseek.com/space/100")
            )
        )
        await fetcher.resume(page: 1)

        // 主列表必须正常拿到第 1 页结果，绝不能变成 CancellationError
        let result = try await mainLoadTask.value
        guard case .value(let detail) = result else {
            Issue.record("账号变化期间主列表请求仍应正常返回页面")
            return
        }
        #expect(detail.page == 1)
        #expect(detail.comments.isEmpty == false)
        // 旧会话索引已清空，不混入旧会话数据
        #expect(coordinator.index.completedPages.isEmpty)
    }

    @Test func ancestorBackfillDoesNotMoveBatchLimitPageBackwards() async throws {
        let fetcher = ControllablePageFetcher(pages: Self.makeThreePageMap())
        let coordinator = ThreadedReplyCoordinator(
            postID: Self.postID,
            pageFetcher: fetcher,
            sessionStore: NodeSeekSessionStore(),
            accountFingerprintProvider: { Self.guestFingerprint },
            sleep: { _ in },
            // 单轮上限 1 页：从第 2 页打开 #15，先补查第 1 页后达到上限
            configuration: .init(pagesPerBurst: 3, burstPauseNanoseconds: 0, maxPagesPerAutoRun: 1)
        )

        _ = try await coordinator.loadPageForMainDetail(page: 2)
        var latest: ThreadedReplyPanelSnapshot?
        let sub = try #require(
            coordinator.startViewing(
                rootComment: Self.comment(floor: 15, author: "Kero", markdown: "@Alice [#8](/post-12000-1#8) 有延迟数据吗？")
            ) { latest = $0 }
        )
        try await Self.waitUntil {
            if case .pausedAtBatchLimit = latest?.state { return true }
            return false
        }
        #expect(latest?.state == .pausedAtBatchLimit(scannedUpToPage: 2, totalPages: 3))
        coordinator.stopViewing(subscriptionID: sub)
    }

    // MARK: - 辅助工具

    private static let guestFingerprint = ThreadedReplyAccountFingerprint(
        sessionID: UUID(),
        isLoggedIn: false,
        displayName: "游客",
        profileURL: nil
    )

    private static func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        Issue.record("等待异步条件超时")
    }

    private static func comment(floor: Int, author: String = "User", markdown: String? = "正文") -> nodeseek.Comment {
        nodeseek.Comment(
            id: "\(90000 + floor)",
            anchorID: "\(floor)",
            authorName: author,
            avatarURL: nil,
            floorText: "#\(floor)",
            createdAtText: "刚刚",
            contentHTML: "<p>html</p>",
            markdown: markdown,
            hasVisibleMarkdown: true
        )
    }

    private static func makePage(page: Int, totalPages: Int, nextPage: Int?, comments: [nodeseek.Comment]) -> PostDetail {
        let items = (1...totalPages).map { n in
            PostDetailPageItem(page: n, url: NodeSeekSite.postURL(id: postID, page: n), isCurrent: n == page)
        }
        return PostDetail(
            id: postID,
            title: "测试贴",
            authorName: "OP",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>主楼</p>",
            comments: comments,
            page: page,
            pagination: totalPages > 1
                ? PostDetailPagination(currentPage: page, items: items, previousPage: page > 1 ? page - 1 : nil, nextPage: nextPage)
                : nil,
            isLastPage: nextPage == nil,
            totalPages: totalPages
        )
    }

    private static func makeThreePageMap() -> [Int: PostDetail] {
        let page1Comments = [
            comment(floor: 3, author: "Mori", markdown: "杭州电信的节点有人测过吗？"),
            comment(floor: 8, author: "Alice", markdown: "@Mori [#3](/post-12000-1#3) 晚高峰测了几次，挺稳的。"),
            comment(floor: 9, author: "Liam", markdown: "另一段讨论")
        ]
        let page2Comments = [
            comment(floor: 15, author: "Kero", markdown: "@Alice [#8](/post-12000-1#8) 有延迟数据吗？"),
            comment(
                floor: 18,
                author: "Alice",
                markdown: "> @Kero [#15](/post-12000-2#15) 发布于2026-11-15 17:00:15\n> > @Alice [#8](/post-12000-1#8) 发布于2026-11-15 17:00:08\n> > 晚高峰\n>\n> 有延迟数据吗？\n\n刚测是 18ms。"
            ),
            comment(floor: 19, author: "Zoe", markdown: "@Liam [#9](/post-12000-1#9) 同意")
        ]
        let page3Comments = [
            comment(floor: 23, author: "Nova", markdown: "@Mori [#3](/post-12000-1#3) 我刚补了一个杭州节点。"),
            comment(floor: 27, author: "Mori", markdown: "@Nova [#23](/post-12000-3#23) 收到了，这个也通了。")
        ]
        return [
            1: makePage(page: 1, totalPages: 3, nextPage: 2, comments: page1Comments),
            2: makePage(page: 2, totalPages: 3, nextPage: 3, comments: page2Comments),
            3: makePage(page: 3, totalPages: 3, nextPage: nil, comments: page3Comments)
        ]
    }

    private static func makeMultiPageMap(totalPages: Int) -> [Int: PostDetail] {
        var result: [Int: PostDetail] = [:]
        for page in 1...totalPages {
            let floor = (page - 1) * 10 + 1
            let markdown = page == 1 ? "首楼" : "@User [#1](/post-12000-1#1) 第 \(page) 页回复"
            result[page] = makePage(
                page: page,
                totalPages: totalPages,
                nextPage: page < totalPages ? page + 1 : nil,
                comments: [comment(floor: floor, author: "User\(page)", markdown: markdown)]
            )
        }
        return result
    }
}

private actor MutableFingerprintBox {
    var value: ThreadedReplyAccountFingerprint

    init(_ value: ThreadedReplyAccountFingerprint) {
        self.value = value
    }

    func set(_ newValue: ThreadedReplyAccountFingerprint) {
        value = newValue
    }
}

private actor ControllableSleepGate {
    private var waiters: [CheckedContinuation<Void, Error>] = []

    func sleep(nanoseconds: UInt64) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(continuation)
            }
        } onCancel: {
            Task { await self.cancelAll() }
        }
    }

    func isSleeping() -> Bool {
        !waiters.isEmpty
    }

    func resumeNext() {
        guard !waiters.isEmpty else { return }
        let waiter = waiters.removeFirst()
        waiter.resume()
    }

    private func cancelAll() {
        let all = waiters
        waiters.removeAll()
        all.forEach { $0.resume(throwing: CancellationError()) }
    }
}

private final class ControllablePageFetcher: PostDetailPageFetching, @unchecked Sendable {
    private actor State {
        var pages: [Int: PostDetail]
        var pausesPages: Set<Int> = []
        var failOncePages: [Int: NodeSeekResult<PostDetail>] = [:]
        var recorded: [Int] = []
        var cancelled: [Int] = []
        var pausedContinuations: [Int: [CheckedContinuation<Void, Error>]] = [:]

        init(pages: [Int: PostDetail]) {
            self.pages = pages
        }

        func recordRequest(page: Int) -> (shouldPause: Bool, oneShotResult: NodeSeekResult<PostDetail>?, pageDetail: PostDetail?) {
            recorded.append(page)
            let oneShot = failOncePages.removeValue(forKey: page)
            return (pausesPages.contains(page), oneShot, pages[page])
        }

        func waitIfPaused(page: Int) async throws {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    pausedContinuations[page, default: []].append(continuation)
                }
            } onCancel: {
                Task { await self.cancel(page: page) }
            }
        }

        func isPaused(page: Int) -> Bool {
            pausedContinuations[page]?.isEmpty == false
        }

        func resume(page: Int) {
            let list = pausedContinuations.removeValue(forKey: page) ?? []
            list.forEach { $0.resume() }
        }

        func cancel(page: Int) {
            cancelled.append(page)
            let list = pausedContinuations.removeValue(forKey: page) ?? []
            list.forEach { $0.resume(throwing: CancellationError()) }
        }

        func setPauses(_ value: Set<Int>) { pausesPages = value }
        func setFailOnce(_ value: [Int: NodeSeekResult<PostDetail>]) { failOncePages = value }
        func updatePages(_ value: [Int: PostDetail]) { pages = value }
        func getRecorded() -> [Int] { recorded }
        func getCancelled() -> [Int] { cancelled }
    }

    private let state: State

    var pausesPages: Set<Int> {
        get { [] }
        set { Task { await state.setPauses(newValue) } }
    }

    var failOncePages: [Int: NodeSeekResult<PostDetail>] {
        get { [:] }
        set { Task { await state.setFailOnce(newValue) } }
    }

    init(pages: [Int: PostDetail]) {
        self.state = State(pages: pages)
    }

    func updatePages(_ pages: [Int: PostDetail]) async {
        await state.updatePages(pages)
    }

    func recordedPages() async -> [Int] {
        await state.getRecorded()
    }

    func cancelledPages() async -> [Int] {
        await state.getCancelled()
    }

    func isPaused(onPage page: Int) async -> Bool {
        await state.isPaused(page: page)
    }

    func resume(page: Int) async {
        await state.resume(page: page)
    }

    func fetchPostDetailPage(postID: String, page: Int) async throws -> NodeSeekResult<PostDetail> {
        let info = await state.recordRequest(page: page)
        if info.shouldPause {
            try await state.waitIfPaused(page: page)
        }
        try Task.checkCancellation()
        if let oneShot = info.oneShotResult {
            return oneShot
        }
        guard let detail = info.pageDetail else {
            throw NSError(domain: "Test", code: 404, userInfo: [NSLocalizedDescriptionKey: "缺少页面 \(page)"])
        }
        return .value(detail)
    }
}
