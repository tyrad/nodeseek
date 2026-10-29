//
//  NewDiscussionPresenter.swift
//  nodeseek
//

import Foundation

final class NewDiscussionPresenter: NewDiscussionPresenterProtocol {
    weak var view: NewDiscussionViewProtocol?

    private let router: NewDiscussionRouterProtocol
    private let draftStore: NewDiscussionDraftStoring
    private let submitter: NodeSeekDiscussionSubmitting
    private let autosaveDelayNanoseconds: UInt64

    private(set) var draft = NewDiscussionDraft()
    private(set) var pendingDraft: NewDiscussionDraft?
    private(set) var userLevel: NewDiscussionUserLevelState = .loading
    private(set) var isSubmitting = false
    private(set) var uploadingImageCount = 0
    private var autosaveTask: Task<Void, Never>?

    init(
        router: NewDiscussionRouterProtocol,
        draftStore: NewDiscussionDraftStoring,
        submitter: NodeSeekDiscussionSubmitting,
        autosaveDelayNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.router = router
        self.draftStore = draftStore
        self.submitter = submitter
        self.autosaveDelayNanoseconds = autosaveDelayNanoseconds
    }

    var state: NewDiscussionViewState {
        NewDiscussionViewState(
            category: draft.category,
            rank: draft.rank,
            userLevel: userLevel,
            pendingDraft: pendingDraft,
            saveStatus: saveStatus,
            canPublish: canPublish,
            isSubmitting: isSubmitting
        )
    }

    /// 等级没读到时不给选项，避免把草稿里的受限等级悄悄改成公开。
    var rankOptions: [DiscussionReadRank] {
        guard case .loaded(let level) = userLevel else { return [] }
        return DiscussionReadRank.options(userLevel: level)
    }

    private var saveStatus: NewDiscussionSaveStatus {
        if pendingDraft != nil && draft.hasContent { return .waitingForDraftDecision }
        return draft.hasContent ? .saved : .empty
    }

    private var canPublish: Bool {
        guard !isSubmitting, uploadingImageCount == 0 else { return false }
        return (try? draft.validatedSubmission()) != nil
    }

    // MARK: - 生命周期

    func viewDidLoad() {
        if let saved = draftStore.load(), saved.hasContent {
            pendingDraft = saved
        }
        render()
        loadUserLevel()
    }

    func retryLoadingUserLevel() {
        loadUserLevel()
    }

    private func loadUserLevel() {
        userLevel = .loading
        render()
        Task { [weak self] in
            guard let self else { return }
            do {
                let level = try await submitter.loadUserLevel()
                userLevel = .loaded(level)
            } catch {
                AppLog.warning(.postList, "发帖页读取用户等级失败: error=\(error.localizedDescription)")
                userLevel = .failed
            }
            render()
        }
    }

    // MARK: - 编辑

    func didChangeTitle(_ title: String) {
        draft.title = title
        draftDidChange()
    }

    func didChangeContent(_ content: String) {
        draft.content = content
        draftDidChange()
    }

    func didSelectCategory(_ category: DiscussionCategory) {
        draft.category = category
        draftDidChange()
    }

    func didSelectRank(_ rank: DiscussionReadRank) {
        draft.rank = rank
        draftDidChange()
    }

    func didChangeUploadingImageCount(_ count: Int) {
        uploadingImageCount = max(0, count)
        render()
    }

    private func draftDidChange() {
        draft.updatedAt = Date()
        scheduleAutosave()
        render()
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let delay = autosaveDelayNanoseconds
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.persistDraftIfAllowed()
        }
    }

    /// 旧草稿没处理之前不写入，保证旧草稿原样保留。
    private func persistDraftIfAllowed() {
        guard pendingDraft == nil, !isSubmitting else { return }
        let savable = draftForStorage
        if savable.hasContent {
            draftStore.save(savable)
        } else {
            draftStore.clear()
        }
    }

    /// 上传中的占位不进草稿，恢复后不会留下永远传不完的图片。
    private var draftForStorage: NewDiscussionDraft {
        var savable = draft
        savable.content = MarkdownImagePlaceholder.strippingAll(in: draft.content)
        return savable
    }

    // MARK: - 旧草稿

    func restorePendingDraft() {
        guard let pendingDraft else { return }
        self.pendingDraft = nil
        draft = pendingDraft
        view?.fill(draft)
        render()
    }

    func discardPendingDraft() {
        pendingDraft = nil
        draftStore.clear()
        persistDraftIfAllowed()
        render()
    }

    // MARK: - 关闭

    func closeDecision() -> NewDiscussionCloseDecision {
        if isSubmitting { return .blocked }
        guard draft.hasContent else { return .close }
        return pendingDraft == nil ? .askSaveOrDiscard : .askReplaceOldDraft
    }

    func close(savingDraft: Bool) {
        autosaveTask?.cancel()
        if savingDraft {
            pendingDraft = nil
            persistDraftIfAllowed()
        } else if pendingDraft == nil {
            draftStore.clear()
        }
        router.dismiss()
    }

    func closeKeepingPendingDraft() {
        autosaveTask?.cancel()
        router.dismiss()
    }

    // MARK: - 发布

    func didTapPublish() {
        guard !isSubmitting else { return }
        guard uploadingImageCount == 0 else {
            view?.showValidationMessage("图片还在上传，传完再发布")
            return
        }
        let submission: NewDiscussionSubmission
        do {
            submission = try draft.validatedSubmission()
        } catch {
            view?.showValidationMessage(error.localizedDescription)
            return
        }
        // 恢复的旧草稿可能带着比当前等级更高的阅读限制，站点不接受。
        if case .loaded = userLevel, !rankOptions.contains(submission.rank) {
            view?.showValidationMessage("阅读限制超过了你当前的等级，请重新选择谁可以看")
            return
        }

        if let fee = submission.category.chickenLegFee {
            view?.confirmChickenLegFee(fee) { [weak self] in
                self?.submit(submission)
            }
            return
        }
        submit(submission)
    }

    private func submit(_ submission: NewDiscussionSubmission) {
        isSubmitting = true
        autosaveTask?.cancel()
        // 先把当前内容落盘：万一 App 在提交中被杀，下次还能恢复。
        if pendingDraft == nil { draftStore.save(draftForStorage) }
        render()

        Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await submitter.submit(submission)
                // 存储里是还没处理的旧草稿时保留，只清掉本次发出去的内容。
                if pendingDraft == nil { draftStore.clear() }
                isSubmitting = false
                router.finishPublishing(route: response.postRoute())
            } catch let error as NodeSeekDiscussionSubmitError {
                isSubmitting = false
                render()
                let title = error == .resultUnknown ? "发布结果未知" : "发布失败"
                view?.showSubmitFailure(
                    title: title,
                    message: error.localizedDescription,
                    allowsRetry: error != .resultUnknown
                )
            } catch {
                isSubmitting = false
                render()
                view?.showSubmitFailure(title: "发布失败", message: error.localizedDescription, allowsRetry: true)
            }
        }
    }

    func didTapOpenWebFallback() {
        router.openWebFallback()
    }

    private func render() {
        view?.render(state)
    }
}
