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
    private let editor: NodeSeekDiscussionEditing?
    private let mode: NewDiscussionMode
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
        mode: NewDiscussionMode = .create,
        editor: NodeSeekDiscussionEditing? = nil,
        autosaveDelayNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.router = router
        self.draftStore = draftStore
        self.submitter = submitter
        self.mode = mode
        self.editor = editor
        self.autosaveDelayNanoseconds = autosaveDelayNanoseconds
    }

    /// 编辑模式下的原文。
    private var original: EditableDiscussion? {
        if case .edit(let original) = mode { return original }
        return nil
    }

    /// 编辑评论时的原文。
    private var originalComment: EditableComment? {
        if case .editComment(let original) = mode { return original }
        return nil
    }

    private var isEditing: Bool {
        mode != .create
    }

    /// 编辑时和原文比有没有改动；发新帖返回 nil。
    private func differsFromOriginal(_ draft: NewDiscussionDraft) -> Bool? {
        switch mode {
        case .create: return nil
        case .edit(let original): return original.isModified(by: draft)
        case .editComment(let original): return draft.content != original.content
        }
    }

    /// 发帖看有没有内容，编辑看和原文比有没有改动。
    private var hasChanges: Bool {
        differsFromOriginal(draft) ?? draft.hasContent
    }

    var state: NewDiscussionViewState {
        NewDiscussionViewState(
            isEditing: isEditing,
            editingCommentFloor: originalComment?.floorIndex,
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
        if pendingDraft != nil && hasChanges { return .waitingForDraftDecision }
        if isEditing { return hasChanges ? .saved : .unchanged }
        return draft.hasContent ? .saved : .empty
    }

    private var canPublish: Bool {
        guard !isSubmitting, uploadingImageCount == 0 else { return false }
        switch mode {
        case .create:
            return (try? draft.validatedSubmission()) != nil
        case .edit(let original):
            return hasChanges && (try? draft.validatedEditSubmission(postID: original.postID)) != nil
        case .editComment(let original):
            return hasChanges && (try? EditCommentSubmission(commentID: original.commentID, content: draft.content)) != nil
        }
    }

    // MARK: - 生命周期

    func viewDidLoad() {
        if isEditing {
            // 原文已经读好：直接填进编辑器；编辑帖子时等级也一并拿到了，评论用不到等级。
            switch mode {
            case .edit(let original):
                draft = original.draft
                userLevel = .loaded(original.userLevel)
            case .editComment(let original):
                draft = original.draft
            case .create:
                break
            }
            if let saved = draftStore.load() {
                if differsFromOriginal(saved) == true {
                    pendingDraft = saved
                } else {
                    draftStore.clear()
                }
            }
            view?.fill(draft)
            render()
            return
        }
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
        // 编辑时和原文一样就没必要留草稿。
        if differsFromOriginal(savable) ?? savable.hasContent {
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
        guard var pendingDraft else { return }
        self.pendingDraft = nil
        // 编辑时板块不能改，以帖子当前板块为准。
        if let original { pendingDraft.category = original.category }
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
        if isEditing { return hasChanges ? .askSaveEdit : .close }
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
            view?.showValidationMessage(isEditing ? "图片还在上传，传完再保存" : "图片还在上传，传完再发布")
            return
        }
        switch mode {
        case .create:
            break
        case .edit(let original):
            publishEdit(original: original)
            return
        case .editComment(let original):
            publishCommentEdit(original: original)
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

    // MARK: - 保存修改

    private func publishEdit(original: EditableDiscussion) {
        guard hasChanges else { return }
        let submission: EditDiscussionSubmission
        do {
            submission = try draft.validatedEditSubmission(postID: original.postID)
        } catch {
            view?.showValidationMessage(error.localizedDescription)
            return
        }
        // 只拦截这次新选的、超过当前等级的阅读限制；没改动的原设置交给站点判断。
        if submission.rank != original.rank, !rankOptions.contains(submission.rank) {
            view?.showValidationMessage("阅读限制超过了你当前的等级，请重新选择谁可以看")
            return
        }
        let save: (NodeSeekDiscussionEditing) async throws -> Void = { try await $0.submitEdit(submission) }
        if original.requiresPrivateFee(for: submission.rank) {
            view?.confirmPrivateRankFee(EditableDiscussion.privateFee) { [weak self] in
                self?.submitEdit(save)
            }
            return
        }
        submitEdit(save)
    }

    private func publishCommentEdit(original: EditableComment) {
        guard hasChanges else { return }
        let submission: EditCommentSubmission
        do {
            submission = try EditCommentSubmission(commentID: original.commentID, content: draft.content)
        } catch {
            view?.showValidationMessage(error.localizedDescription)
            return
        }
        submitEdit { try await $0.submitEditComment(submission, postID: original.postID) }
    }

    private func submitEdit(_ save: @escaping (NodeSeekDiscussionEditing) async throws -> Void) {
        guard let editor else { return }
        isSubmitting = true
        autosaveTask?.cancel()
        // 先把修改落盘：万一 App 在保存中被杀，下次编辑还能恢复。
        if pendingDraft == nil { draftStore.save(draftForStorage) }
        render()

        Task { [weak self] in
            guard let self else { return }
            do {
                try await save(editor)
                // 修改已经生效，这份编辑草稿过时了。
                draftStore.clear()
                isSubmitting = false
                router.finishPublishing(route: nil)
            } catch {
                isSubmitting = false
                render()
                // 重复保存同样的内容没有副作用，结果未知时也可以直接重试。
                let isUnknown = (error as? NodeSeekDiscussionSubmitError) == .resultUnknown
                view?.showSubmitFailure(
                    title: isUnknown ? "保存结果未知" : "保存失败",
                    message: Self.editFailureMessage(for: error),
                    allowsRetry: true
                )
            }
        }
    }

    private static func editFailureMessage(for error: Error) -> String {
        switch error as? NodeSeekDiscussionSubmitError {
        case .notLoggedIn:
            return "登录状态已失效，请重新登录后再保存。"
        case .resultUnknown:
            return "可能已经保存，可以直接重试，重复保存同样的内容没有影响。"
        case .network(let message):
            return "网络异常，修改没有保存：\(message)"
        case .unexpected(let message):
            return "保存失败：\(message)"
        default:
            return error.localizedDescription
        }
    }

    func didTapOpenWebFallback() {
        router.openWebFallback()
    }

    private func render() {
        view?.render(state)
    }
}
