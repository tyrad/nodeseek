import Foundation

protocol PostDetailPageFetching: Sendable {
    func fetchPostDetailPage(postID: String, page: Int) async throws -> NodeSeekResult<PostDetail>
}

extension NodeSeekService: PostDetailPageFetching {
    func fetchPostDetailPage(postID: String, page: Int) async throws -> NodeSeekResult<PostDetail> {
        try await loadPostDetail(postID: postID, page: page)
    }
}

/// 当前登录态与账号身份指纹：游客登录、退出登录或切换账号时都会变化，用于及时作废旧缓存。
struct ThreadedReplyAccountFingerprint: Equatable, Sendable {
    let sessionID: UUID?
    let isLoggedIn: Bool
    let displayName: String?
    let profileURL: URL?

    static func current(from store: CurrentAccountStore = .shared) async -> Self {
        let sessionID = await store.sessionID
        let account = await store.snapshot()?.account
        return Self(
            sessionID: sessionID,
            isLoggedIn: account?.isLoggedIn ?? false,
            displayName: account?.displayName,
            profileURL: account?.profileURL
        )
    }
}

enum ThreadedReplyScanState: Equatable, Sendable {
    case idle
    case scanning(currentPage: Int, totalPages: Int?)
    case pausedAtBatchLimit(scannedUpToPage: Int, totalPages: Int?)
    case failed(message: String, requiresLogin: Bool)
    case completed
}

struct ThreadedReplyPanelSnapshot: Equatable, Sendable {
    let postID: String
    let rootFloor: Int
    let rootComment: Comment
    let ancestors: [ThreadedAncestorNode]
    let rootDisplayedParentFloor: Int?
    let rootConnectsFromTop: Bool
    let nodes: [ThreadedReplyNode]
    let state: ThreadedReplyScanState
    let totalPages: Int?
    let completedPages: Set<Int>

    init(
        postID: String,
        rootFloor: Int,
        rootComment: Comment,
        ancestors: [ThreadedAncestorNode] = [],
        rootDisplayedParentFloor: Int? = nil,
        rootConnectsFromTop: Bool = false,
        nodes: [ThreadedReplyNode],
        state: ThreadedReplyScanState,
        totalPages: Int?,
        completedPages: Set<Int>
    ) {
        self.postID = postID
        self.rootFloor = rootFloor
        self.rootComment = rootComment
        self.ancestors = ancestors
        self.rootDisplayedParentFloor = rootDisplayedParentFloor
        self.rootConnectsFromTop = rootConnectsFromTop
        self.nodes = nodes
        self.state = state
        self.totalPages = totalPages
        self.completedPages = completedPages
    }

    var replyCount: Int { nodes.count }
}

/// 单篇帖子的「吃瓜」扫描与分页共享协调器。
/// 普通翻页与面板扫描共用按页合并的在途请求；账号切换只作废索引与面板扫描，绝不拦截主列表正常加载。
@MainActor
final class ThreadedReplyCoordinator {
    nonisolated struct Configuration: Sendable {
        var pagesPerBurst: Int
        var burstPauseNanoseconds: UInt64
        var maxPagesPerAutoRun: Int

        static let `default` = Configuration(
            pagesPerBurst: 3,
            burstPauseNanoseconds: 800_000_000,
            maxPagesPerAutoRun: 20
        )
    }

    typealias AccountFingerprintProvider = @Sendable () async -> ThreadedReplyAccountFingerprint
    typealias SleepClosure = @Sendable (UInt64) async throws -> Void

    private enum WaiterKind {
        case mainDetail
        case scan
    }

    private struct Waiter {
        let kind: WaiterKind
        let continuation: CheckedContinuation<NodeSeekResult<PostDetail>, Error>
    }

    private struct FetchedPagePayload: Sendable {
        let result: NodeSeekResult<PostDetail>
        let parsedRecord: ThreadedReplyIndex.PageRecord?
    }

    private final class InFlightPageLoad {
        let id = UUID()
        let task: Task<FetchedPagePayload, Error>
        var waiters: [UUID: Waiter] = [:]

        init(task: Task<FetchedPagePayload, Error>) {
            self.task = task
        }
    }

    private struct ActiveSubscription {
        let id: UUID
        let rootFloor: Int
        let fallbackRootComment: Comment
        let onUpdate: (ThreadedReplyPanelSnapshot) -> Void
    }

    let postID: String
    let baseURL: URL
    private let pageFetcher: any PostDetailPageFetching
    private let sessionStore: NodeSeekSessionStore
    private let accountFingerprintProvider: AccountFingerprintProvider
    private let sleep: SleepClosure
    private let configuration: Configuration

    private(set) var index: ThreadedReplyIndex
    private var sessionToken = UUID()
    private var lastAccountFingerprint: ThreadedReplyAccountFingerprint?
    private var inFlightLoads: [Int: InFlightPageLoad] = [:]
    private var activeSubscription: ActiveSubscription?
    private var scanState: ThreadedReplyScanState = .idle
    private var scanTask: Task<Void, Never>?
    private var lastCompletedScannedPage: Int = 1

    init(
        postID: String,
        baseURL: URL = NodeSeekSite.baseURL,
        pageFetcher: any PostDetailPageFetching,
        sessionStore: NodeSeekSessionStore = .shared,
        accountFingerprintProvider: @escaping AccountFingerprintProvider = {
            await ThreadedReplyAccountFingerprint.current()
        },
        sleep: @escaping SleepClosure = { try await Task.sleep(nanoseconds: $0) },
        configuration: Configuration = .default
    ) {
        self.postID = postID
        self.baseURL = baseURL
        self.pageFetcher = pageFetcher
        self.sessionStore = sessionStore
        self.accountFingerprintProvider = accountFingerprintProvider
        self.sleep = sleep
        self.configuration = configuration
        self.index = ThreadedReplyIndex(postID: postID, baseURL: baseURL)
    }

    deinit {
        scanTask?.cancel()
    }

    // MARK: - 主详情页共用加载入口

    /// 主详情页调用：与面板扫描共用按页合并的在途请求，成功页自动写入索引；账号变化只清索引不影响主列表本身的结果返回。
    func loadPageForMainDetail(page: Int) async throws -> NodeSeekResult<PostDetail> {
        await refreshSessionIfAccountChanged()
        return try await fetchSharedPage(page: max(1, page), kind: .mainDetail)
    }

    /// 本地回帖成功或外部获知回复增长时，将原末页标脏待复查。
    func markLastPageStaleForGrowth() {
        index.markLastPageStaleForGrowth()
    }

    /// 登录、退出、切换账号或受限状态变化时作废索引与面板扫描，保留主列表等待方不受打断。
    func invalidateSession(cancellingScanTask: Bool = true) {
        sessionToken = UUID()
        if cancellingScanTask {
            scanTask?.cancel()
            scanTask = nil
        }

        for (page, load) in Array(inFlightLoads) {
            var scanWaiters: [CheckedContinuation<NodeSeekResult<PostDetail>, Error>] = []
            for (waiterID, waiter) in load.waiters where waiter.kind == .scan {
                load.waiters.removeValue(forKey: waiterID)
                scanWaiters.append(waiter.continuation)
            }
            for continuation in scanWaiters {
                continuation.resume(throwing: CancellationError())
            }
            if load.waiters.isEmpty {
                inFlightLoads.removeValue(forKey: page)
                load.task.cancel()
            }
        }

        index.reset()
        scanState = .idle
        if let activeSubscription {
            emitSnapshot(to: activeSubscription)
        }
    }

    // MARK: - 面板订阅与扫描控制

    @discardableResult
    func startViewing(
        rootComment: Comment,
        onUpdate: @escaping (ThreadedReplyPanelSnapshot) -> Void
    ) -> UUID? {
        guard let rootFloor = CommentReplyRelationParser.floorNumber(for: rootComment),
              rootFloor > 0 else {
            return nil
        }
        scanTask?.cancel()
        scanTask = nil

        let subscriptionID = UUID()
        let subscription = ActiveSubscription(
            id: subscriptionID,
            rootFloor: rootFloor,
            fallbackRootComment: rootComment,
            onUpdate: onUpdate
        )
        activeSubscription = subscription
        lastCompletedScannedPage = CommentComposerContentBuilder.commentPage(forFloor: rootFloor)

        if index.isComplete(forRootFloor: rootFloor, fallbackRootComment: rootComment) {
            scanState = .completed
            emitSnapshot(to: subscription)
            // 仍在异步核对账号身份是否已变化；若无变化则零网络请求。
            scanTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let changed = await self.refreshSessionIfAccountChanged(cancellingScanTask: false)
                guard !Task.isCancelled, self.activeSubscription?.id == subscriptionID else { return }
                if changed {
                    self.runScanLoop(for: subscriptionID)
                }
            }
        } else {
            let firstMissing = index.nextPageToScan(forRootFloor: rootFloor, fallbackRootComment: rootComment)
                ?? lastCompletedScannedPage
            scanState = .scanning(currentPage: firstMissing, totalPages: index.totalPages)
            emitSnapshot(to: subscription)
            runScanLoop(for: subscriptionID)
        }

        return subscriptionID
    }

    func stopViewing(subscriptionID: UUID) {
        guard activeSubscription?.id == subscriptionID else { return }
        activeSubscription = nil
        scanTask?.cancel()
        scanTask = nil
        scanState = .idle
    }

    func continueScanning(subscriptionID: UUID) {
        guard activeSubscription?.id == subscriptionID else { return }
        scanTask?.cancel()
        scanTask = nil
        runScanLoop(for: subscriptionID)
    }

    func retry(subscriptionID: UUID) {
        guard activeSubscription?.id == subscriptionID else { return }
        scanTask?.cancel()
        scanTask = nil
        runScanLoop(for: subscriptionID)
    }

    // MARK: - 内部扫描循环与请求合并

    private func runScanLoop(for subscriptionID: UUID) {
        scanTask?.cancel()
        scanTask = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.refreshSessionIfAccountChanged(cancellingScanTask: false)
            guard !Task.isCancelled, let subscription = self.activeSubscription, subscription.id == subscriptionID else {
                return
            }

            let capturedToken = self.sessionToken
            var batchFetchedCount = 0

            while !Task.isCancelled {
                guard self.sessionToken == capturedToken,
                      let currentSubscription = self.activeSubscription,
                      currentSubscription.id == subscriptionID else {
                    return
                }

                guard let nextPage = self.index.nextPageToScan(
                    forRootFloor: currentSubscription.rootFloor,
                    fallbackRootComment: currentSubscription.fallbackRootComment
                ) else {
                    self.scanState = .completed
                    self.emitSnapshot(to: currentSubscription)
                    return
                }

                if self.configuration.maxPagesPerAutoRun > 0,
                   batchFetchedCount >= self.configuration.maxPagesPerAutoRun {
                    self.scanState = .pausedAtBatchLimit(
                        scannedUpToPage: self.lastCompletedScannedPage,
                        totalPages: self.index.totalPages
                    )
                    self.emitSnapshot(to: currentSubscription)
                    return
                }

                if batchFetchedCount > 0,
                   self.configuration.pagesPerBurst > 0,
                   batchFetchedCount % self.configuration.pagesPerBurst == 0,
                   self.configuration.burstPauseNanoseconds > 0 {
                    do {
                        try await self.sleep(self.configuration.burstPauseNanoseconds)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled,
                          self.sessionToken == capturedToken,
                          self.activeSubscription?.id == subscriptionID else {
                        return
                    }
                }

                self.scanState = .scanning(currentPage: nextPage, totalPages: self.index.totalPages)
                self.emitSnapshot(to: currentSubscription)

                do {
                    let result = try await self.fetchSharedPage(page: nextPage, kind: .scan)
                    guard !Task.isCancelled,
                          self.sessionToken == capturedToken,
                          let latestSubscription = self.activeSubscription,
                          latestSubscription.id == subscriptionID else {
                        return
                    }

                    switch result {
                    case .value(let detail):
                        if detail.isRestricted {
                            self.scanState = .failed(
                                message: DetailListStrings.text("thread-restricted"),
                                requiresLogin: false
                            )
                            self.emitSnapshot(to: latestSubscription)
                            return
                        }
                        batchFetchedCount += 1
                        // 仅向前更新已扫描的最大页码，避免先补查上游第 1 页时进度文案倒退。
                        self.lastCompletedScannedPage = max(self.lastCompletedScannedPage, detail.page)
                        if self.index.nextPageToScan(
                            forRootFloor: latestSubscription.rootFloor,
                            fallbackRootComment: latestSubscription.fallbackRootComment
                        ) == nil {
                            self.scanState = .completed
                            self.emitSnapshot(to: latestSubscription)
                            return
                        }
                        self.emitSnapshot(to: latestSubscription)

                    case .challenge(let challenge):
                        let message = await self.sessionStore.recordChallenge(challenge)
                        guard !Task.isCancelled,
                              self.sessionToken == capturedToken,
                              let latestSubscription = self.activeSubscription,
                              latestSubscription.id == subscriptionID else {
                            return
                        }
                        let requiresLogin: Bool
                        if case .loginRequired = challenge {
                            requiresLogin = true
                        } else {
                            requiresLogin = false
                        }
                        self.scanState = .failed(message: message, requiresLogin: requiresLogin)
                        self.emitSnapshot(to: latestSubscription)
                        return
                    }
                } catch {
                    if Self.isCancellation(error) || Task.isCancelled {
                        return
                    }
                    guard self.sessionToken == capturedToken,
                          let latestSubscription = self.activeSubscription,
                          latestSubscription.id == subscriptionID else {
                        return
                    }
                    let message = UserFacingError.message(
                        for: error,
                        fallback: DetailListStrings.text("thread-load-failed")
                    )
                    self.scanState = .failed(message: message, requiresLogin: false)
                    self.emitSnapshot(to: latestSubscription)
                    return
                }
            }
        }
    }

    private func fetchSharedPage(page: Int, kind: WaiterKind) async throws -> NodeSeekResult<PostDetail> {
        let capturedToken = sessionToken
        let requestFingerprint = lastAccountFingerprint
        let load: InFlightPageLoad
        if let existing = inFlightLoads[page] {
            load = existing
        } else {
            let fetcher = pageFetcher
            let targetPostID = postID
            let targetBaseURL = baseURL
            // 网络抓取与当页 Markdown 关系提取都在后台完成，避免阻塞主线程。
            let task = Task.detached(priority: .userInitiated) { () throws -> FetchedPagePayload in
                let result = try await fetcher.fetchPostDetailPage(postID: targetPostID, page: page)
                try Task.checkCancellation()
                let parsedRecord: ThreadedReplyIndex.PageRecord?
                if case .value(let detail) = result {
                    parsedRecord = ThreadedReplyIndex.parsePage(
                        detail,
                        postID: targetPostID,
                        baseURL: targetBaseURL
                    )
                } else {
                    parsedRecord = nil
                }
                return FetchedPagePayload(result: result, parsedRecord: parsedRecord)
            }
            let created = InFlightPageLoad(task: task)
            inFlightLoads[page] = created
            load = created

            Task { @MainActor [weak self, weak created] in
                guard let created else { return }
                let outcome: Result<FetchedPagePayload, Error>
                do {
                    outcome = .success(try await created.task.value)
                } catch {
                    outcome = .failure(error)
                }
                await self?.finishInFlightLoad(
                    created,
                    page: page,
                    capturedToken: capturedToken,
                    requestFingerprint: requestFingerprint,
                    outcome: outcome
                )
            }
        }

        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard inFlightLoads[page]?.id == load.id else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                load.waiters[waiterID] = Waiter(kind: kind, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor [weak self, weak load] in
                guard let self, let load else { return }
                self.cancelWaiter(waiterID, on: load, page: page)
            }
        }
    }

    private func cancelWaiter(_ waiterID: UUID, on load: InFlightPageLoad, page: Int) {
        guard let waiter = load.waiters.removeValue(forKey: waiterID) else { return }
        waiter.continuation.resume(throwing: CancellationError())
        if load.waiters.isEmpty, inFlightLoads[page]?.id == load.id {
            inFlightLoads.removeValue(forKey: page)
            load.task.cancel()
        }
    }

    private func finishInFlightLoad(
        _ load: InFlightPageLoad,
        page: Int,
        capturedToken: UUID,
        requestFingerprint: ThreadedReplyAccountFingerprint?,
        outcome: Result<FetchedPagePayload, Error>
    ) async {
        let latestFingerprint = await accountFingerprintProvider()
        let fingerprintChanged = requestFingerprint != nil && latestFingerprint != requestFingerprint
        if inFlightLoads[page]?.id == load.id {
            inFlightLoads.removeValue(forKey: page)
        }

        let waiters = load.waiters
        load.waiters.removeAll()

        let detailOutcome: Result<NodeSeekResult<PostDetail>, Error> = outcome.map(\.result)

        if fingerprintChanged {
            lastAccountFingerprint = latestFingerprint
            invalidateSession()
            for (_, waiter) in waiters {
                switch waiter.kind {
                case .mainDetail:
                    // 主详情页正常加载不受协调器会话重置影响，原样交付结果。
                    waiter.continuation.resume(with: detailOutcome)
                case .scan:
                    waiter.continuation.resume(throwing: CancellationError())
                }
            }
            return
        }

        guard sessionToken == capturedToken else {
            for (_, waiter) in waiters {
                switch waiter.kind {
                case .mainDetail:
                    waiter.continuation.resume(with: detailOutcome)
                case .scan:
                    waiter.continuation.resume(throwing: CancellationError())
                }
            }
            return
        }

        if case .success(let payload) = outcome, case .value(let detail) = payload.result {
            if detail.isRestricted {
                index.reset()
            } else if let record = payload.parsedRecord {
                index.ingest(record)
                if let activeSubscription {
                    emitSnapshot(to: activeSubscription)
                }
            }
        }

        for (_, waiter) in waiters {
            waiter.continuation.resume(with: detailOutcome)
        }
    }

    @discardableResult
    private func refreshSessionIfAccountChanged(cancellingScanTask: Bool = true) async -> Bool {
        let current = await accountFingerprintProvider()
        if let previous = lastAccountFingerprint, previous != current {
            lastAccountFingerprint = current
            invalidateSession(cancellingScanTask: cancellingScanTask)
            return true
        }
        lastAccountFingerprint = current
        return false
    }

    private func emitSnapshot(to subscription: ActiveSubscription) {
        let tree = index.tree(
            forRootFloor: subscription.rootFloor,
            fallbackRootComment: subscription.fallbackRootComment
        )
        let snapshot = ThreadedReplyPanelSnapshot(
            postID: postID,
            rootFloor: subscription.rootFloor,
            rootComment: tree.rootComment ?? subscription.fallbackRootComment,
            ancestors: tree.ancestors,
            rootDisplayedParentFloor: tree.rootDisplayedParentFloor,
            rootConnectsFromTop: tree.rootConnectsFromTop,
            nodes: tree.nodes,
            state: scanState,
            totalPages: tree.totalPages,
            completedPages: tree.completedPages
        )
        subscription.onUpdate(snapshot)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
