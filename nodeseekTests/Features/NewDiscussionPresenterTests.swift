//
//  NewDiscussionPresenterTests.swift
//  nodeseekTests
//

import Foundation
import Testing
@testable import nodeseek

@MainActor
struct NewDiscussionPresenterTests {
    private let oldDraft = NewDiscussionDraft(
        title: "旧标题",
        content: "旧正文",
        category: .tech,
        rank: .level(3),
        updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )

    @Test func existingDraftWaitsForDecisionInsteadOfFillingEditor() {
        let (presenter, store, _, _, view) = makePresenter(saved: oldDraft)

        presenter.viewDidLoad()

        #expect(presenter.state.pendingDraft == oldDraft)
        #expect(view.filledDrafts.isEmpty)
        #expect(store.saved == oldDraft)
    }

    @Test func typingBeforeDecidingNeverOverwritesOldDraft() async throws {
        let (presenter, store, _, _, _) = makePresenter(saved: oldDraft)
        presenter.viewDidLoad()

        presenter.didChangeTitle("新标题")
        try await waitForAutosave()

        #expect(store.saved == oldDraft)
        #expect(presenter.state.saveStatus == .waitingForDraftDecision)
        #expect(presenter.closeDecision() == .askReplaceOldDraft)
    }

    @Test func restoreFillsEditorAndResumesAutosave() async throws {
        let (presenter, store, _, _, view) = makePresenter(saved: oldDraft)
        presenter.viewDidLoad()

        presenter.restorePendingDraft()
        presenter.didChangeContent("旧正文 补充")
        try await waitUntil { store.saved?.content == "旧正文 补充" }

        #expect(view.filledDrafts == [oldDraft])
        #expect(presenter.state.pendingDraft == nil)
        #expect(presenter.state.rank == .level(3))
        #expect(store.saved?.content == "旧正文 补充")
    }

    @Test func discardClearsOldDraftThenSavesNewContent() async throws {
        let (presenter, store, _, _, _) = makePresenter(saved: oldDraft)
        presenter.viewDidLoad()
        presenter.didChangeTitle("新标题")

        presenter.discardPendingDraft()

        #expect(store.saved?.title == "新标题")
        #expect(presenter.state.saveStatus == .saved)
    }

    @Test func keepingOldDraftOnCloseLeavesItUntouched() {
        let (presenter, store, router, _, _) = makePresenter(saved: oldDraft)
        presenter.viewDidLoad()
        presenter.didChangeTitle("新标题")

        presenter.closeKeepingPendingDraft()

        #expect(store.saved == oldDraft)
        #expect(router.dismissCount == 1)
    }

    @Test func replacingOldDraftOnCloseSavesNewContent() {
        let (presenter, store, _, _, _) = makePresenter(saved: oldDraft)
        presenter.viewDidLoad()
        presenter.didChangeTitle("新标题")

        presenter.close(savingDraft: true)

        #expect(store.saved?.title == "新标题")
    }

    @Test func closeDecisionDependsOnContent() {
        let (presenter, store, _, _, _) = makePresenter()
        presenter.viewDidLoad()
        #expect(presenter.closeDecision() == .close)

        presenter.didSelectCategory(.tech)
        #expect(presenter.closeDecision() == .close)

        presenter.didChangeContent("正文")
        #expect(presenter.closeDecision() == .askSaveOrDiscard)

        presenter.close(savingDraft: false)
        #expect(store.saved == nil)
    }

    @Test func rankOptionsStayEmptyWhenLevelFailsSoRankIsNotReset() async throws {
        let submitter = StubDiscussionSubmitter()
        submitter.levelResult = .failure(NodeSeekDiscussionSubmitError.notLoggedIn)
        let (presenter, _, _, _, _) = makePresenter(saved: oldDraft, submitter: submitter)
        presenter.viewDidLoad()
        presenter.restorePendingDraft()
        try await waitForAutosave()

        #expect(presenter.state.userLevel == .failed)
        #expect(presenter.rankOptions.isEmpty)
        #expect(presenter.state.rank == .level(3))
    }

    @Test func rankOptionsFollowLoadedLevel() async throws {
        let (presenter, _, _, _, _) = makePresenter()
        presenter.viewDidLoad()
        try await waitForAutosave()

        #expect(presenter.state.userLevel == .loaded(2))
        #expect(presenter.rankOptions.map(\.title) == ["公开", "Lv1", "Lv2", "私有"])
    }

    @Test func publishValidatesWithWebWording() {
        let (presenter, _, _, submitter, view) = makePresenter()
        presenter.viewDidLoad()
        presenter.didChangeTitle("标题")
        presenter.didChangeContent("正文")

        #expect(presenter.state.canPublish == false)
        presenter.didTapPublish()

        #expect(view.validationMessages == ["请选择正确的板块"])
        #expect(submitter.submissions.isEmpty)
    }

    @Test func publishTellsWhichRequiredFieldIsMissing() {
        let (presenter, _, _, submitter, view) = makePresenter()
        presenter.viewDidLoad()

        presenter.didTapPublish()
        presenter.didChangeTitle("标题")
        presenter.didSelectCategory(.tech)
        presenter.didTapPublish()

        #expect(view.validationMessages == ["标题不能为空", "正文不能为空"])
        #expect(submitter.submissions.isEmpty)
    }

    @Test func insideCategoryAsksForFeeBeforeSubmitting() async throws {
        let (presenter, _, _, submitter, view) = makePresenter()
        presenter.viewDidLoad()
        fillValidDraft(presenter, category: .inside)

        presenter.didTapPublish()
        #expect(view.feeConfirmations == [5])
        #expect(submitter.submissions.isEmpty)

        view.confirmFee()
        try await waitForAutosave()
        #expect(submitter.submissions.map(\.category) == [.inside])
    }

    @Test func successfulPublishClearsDraftAndOpensNewPost() async throws {
        let (presenter, store, router, submitter, _) = makePresenter()
        presenter.viewDidLoad()
        fillValidDraft(presenter, category: .tech)

        presenter.didTapPublish()
        try await waitForAutosave()

        #expect(submitter.submissions.first?.title == "求推荐小鸡")
        #expect(store.saved == nil)
        #expect(router.publishedRoutes.first??.postID == "512345")
    }

    @Test func publishingWithoutTouchingOldDraftKeepsIt() async throws {
        let (presenter, store, router, _, _) = makePresenter(saved: oldDraft)
        presenter.viewDidLoad()
        fillValidDraft(presenter, category: .tech)

        presenter.didTapPublish()
        try await waitUntil { !router.publishedRoutes.isEmpty }

        #expect(router.publishedRoutes.count == 1)
        #expect(store.saved == oldDraft)
    }

    @Test func restoredRankAboveCurrentLevelBlocksPublishing() async throws {
        let (presenter, _, _, submitter, view) = makePresenter(saved: oldDraft)
        presenter.viewDidLoad()
        presenter.restorePendingDraft()
        try await waitUntil { presenter.state.userLevel == .loaded(2) }

        presenter.didTapPublish()

        #expect(view.validationMessages == ["阅读限制超过了你当前的等级，请重新选择谁可以看"])
        #expect(submitter.submissions.isEmpty)
    }

    @Test func timeoutKeepsDraftAndDoesNotOfferRetry() async throws {
        let submitter = StubDiscussionSubmitter()
        submitter.submitResult = .failure(NodeSeekDiscussionSubmitError.resultUnknown)
        let (presenter, store, router, _, view) = makePresenter(submitter: submitter)
        presenter.viewDidLoad()
        fillValidDraft(presenter, category: .tech)

        presenter.didTapPublish()
        try await waitForAutosave()

        #expect(view.failures.first?.title == "发布结果未知")
        #expect(view.failures.first?.allowsRetry == false)
        #expect(store.saved?.title == "求推荐小鸡")
        #expect(router.publishedRoutes.isEmpty)
        #expect(presenter.state.isSubmitting == false)
    }

    @Test func serverMessageIsShownWithRetry() async throws {
        let submitter = StubDiscussionSubmitter()
        submitter.submitResult = .failure(NodeSeekDiscussionSubmitError.serverMessage("发帖过于频繁"))
        let (presenter, _, _, _, view) = makePresenter(submitter: submitter)
        presenter.viewDidLoad()
        fillValidDraft(presenter, category: .tech)

        presenter.didTapPublish()
        try await waitForAutosave()

        #expect(view.failures.first?.message == "发帖过于频繁")
        #expect(view.failures.first?.allowsRetry == true)
    }

    @Test func uploadingImagesBlocksPublishing() {
        let (presenter, _, _, submitter, view) = makePresenter()
        presenter.viewDidLoad()
        fillValidDraft(presenter, category: .tech)

        presenter.didChangeUploadingImageCount(2)
        #expect(presenter.state.canPublish == false)
        presenter.didTapPublish()

        #expect(view.validationMessages == ["图片还在上传，传完再发布"])
        #expect(submitter.submissions.isEmpty)

        presenter.didChangeUploadingImageCount(0)
        #expect(presenter.state.canPublish == true)
    }

    @Test func savedDraftDropsUploadPlaceholders() async throws {
        let (presenter, store, _, _, _) = makePresenter()
        presenter.viewDidLoad()

        presenter.didChangeContent("正文\n\(MarkdownImagePlaceholder.text(id: "a1"))\n结尾")
        try await waitUntil { store.saved != nil }

        #expect(store.saved?.content == "正文\n结尾")
    }

    // MARK: - Helpers

    private func fillValidDraft(_ presenter: NewDiscussionPresenter, category: DiscussionCategory) {
        presenter.didChangeTitle("求推荐小鸡")
        presenter.didChangeContent("预算 10 刀")
        presenter.didSelectCategory(category)
    }

    /// 测试里自动保存延迟设为 1ms，等一小段时间让异步任务跑完。
    private func waitForAutosave() async throws {
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    /// 正向断言用：轮询到条件成立，最多等 2 秒，避免并行跑测试时偶发超时。
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func makePresenter(
        saved: NewDiscussionDraft? = nil,
        submitter: StubDiscussionSubmitter = StubDiscussionSubmitter()
    ) -> (NewDiscussionPresenter, MemoryDraftStore, SpyNewDiscussionRouter, StubDiscussionSubmitter, SpyNewDiscussionView) {
        let store = MemoryDraftStore(saved: saved)
        let router = SpyNewDiscussionRouter()
        let view = SpyNewDiscussionView()
        let presenter = NewDiscussionPresenter(
            router: router,
            draftStore: store,
            submitter: submitter,
            autosaveDelayNanoseconds: 1_000_000
        )
        presenter.view = view
        return (presenter, store, router, submitter, view)
    }
}

private final class MemoryDraftStore: NewDiscussionDraftStoring {
    var saved: NewDiscussionDraft?

    init(saved: NewDiscussionDraft?) {
        self.saved = saved
    }

    func load() -> NewDiscussionDraft? { saved }
    func save(_ draft: NewDiscussionDraft) { saved = draft }
    func clear() { saved = nil }
}

private final class StubDiscussionSubmitter: NodeSeekDiscussionSubmitting {
    var levelResult: Result<Int, Error> = .success(2)
    var submitResult: Result<NewDiscussionResponse, Error> = .success(
        NewDiscussionResponse(success: true, message: nil, redirect: "/post-512345-1", redirectHash: nil)
    )
    private(set) var submissions: [NewDiscussionSubmission] = []

    func loadUserLevel() async throws -> Int {
        try levelResult.get()
    }

    func submit(_ submission: NewDiscussionSubmission) async throws -> NewDiscussionResponse {
        submissions.append(submission)
        return try submitResult.get()
    }
}

private final class SpyNewDiscussionRouter: NewDiscussionRouterProtocol {
    private(set) var dismissCount = 0
    private(set) var publishedRoutes: [NodeSeekPostRoute?] = []
    private(set) var webFallbackCount = 0

    func dismiss() { dismissCount += 1 }
    func finishPublishing(route: NodeSeekPostRoute?) { publishedRoutes.append(route) }
    func openWebFallback() { webFallbackCount += 1 }
}

private final class SpyNewDiscussionView: NewDiscussionViewProtocol {
    private(set) var filledDrafts: [NewDiscussionDraft] = []
    private(set) var validationMessages: [String] = []
    private(set) var feeConfirmations: [Int] = []
    private(set) var failures: [(title: String, message: String, allowsRetry: Bool)] = []
    private var pendingFeeConfirmation: (() -> Void)?

    func render(_ state: NewDiscussionViewState) {}
    func fill(_ draft: NewDiscussionDraft) { filledDrafts.append(draft) }
    func showValidationMessage(_ message: String) { validationMessages.append(message) }

    func confirmChickenLegFee(_ fee: Int, onConfirm: @escaping () -> Void) {
        feeConfirmations.append(fee)
        pendingFeeConfirmation = onConfirm
    }

    func showSubmitFailure(title: String, message: String, allowsRetry: Bool) {
        failures.append((title, message, allowsRetry))
    }

    func confirmFee() {
        pendingFeeConfirmation?()
    }
}
