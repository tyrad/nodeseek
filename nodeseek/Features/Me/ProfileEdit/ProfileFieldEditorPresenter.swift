//
//  ProfileFieldEditorPresenter.swift
//  nodeseek
//

import UIKit

/// 签名和 Readme 复用发帖编辑器：没有标题和发布设置，不存本机草稿，保存直接提交到站点。
final class ProfileFieldEditorPresenter: NewDiscussionPresenterProtocol {
    enum Field {
        case signature
        case readme
    }

    weak var view: NewDiscussionViewProtocol?
    weak var viewController: UIViewController?

    private let field: Field
    private let original: ProfileIntroduction
    private let client: ProfileEditClienting
    private let onSaved: (ProfileIntroduction) -> Void
    private var content: String
    private var isSubmitting = false
    private var uploadingImageCount = 0

    init(
        field: Field,
        original: ProfileIntroduction,
        client: ProfileEditClienting,
        onSaved: @escaping (ProfileIntroduction) -> Void
    ) {
        self.field = field
        self.original = original
        self.client = client
        self.onSaved = onSaved
        content = field == .signature ? original.signature : original.readme
    }

    /// 返回包好导航栏的编辑页，由调用方全屏弹出。
    static func createModule(
        field: Field,
        original: ProfileIntroduction,
        client: ProfileEditClienting,
        onSaved: @escaping (ProfileIntroduction) -> Void
    ) -> UINavigationController {
        let presenter = ProfileFieldEditorPresenter(field: field, original: original, client: client, onSaved: onSaved)
        let view = NewDiscussionViewController(presenter: presenter)
        presenter.view = view
        presenter.viewController = view
        let navigationController = UINavigationController(rootViewController: view)
        navigationController.modalPresentationStyle = .fullScreen
        return navigationController
    }

    private var originalContent: String {
        field == .signature ? original.signature : original.readme
    }

    private var hasChanges: Bool {
        content != originalContent
    }

    var state: NewDiscussionViewState {
        var state = NewDiscussionViewState(
            isEditing: true,
            editingCommentFloor: nil,
            category: nil,
            rank: .everyone,
            userLevel: .loading,
            pendingDraft: nil,
            // 不存本机草稿，有改动时不显示「已存本机」。
            saveStatus: hasChanges ? .empty : .unchanged,
            canPublish: hasChanges,
            isSubmitting: isSubmitting
        )
        switch field {
        case .signature:
            state.fieldTitle = NSLocalizedString("签名", tableName: "Me", comment: "")
            state.bodyPlaceholder = NSLocalizedString("显示在帖子内容下方，支持 Markdown，不支持图片和引用", tableName: "Me", comment: "")
            state.hiddenToolbarItems = [.photo, .sticker]
            state.allowsQuote = false
        case .readme:
            state.fieldTitle = "Readme"
            state.bodyPlaceholder = NSLocalizedString("显示在个人主页，支持 Markdown", tableName: "Me", comment: "")
        }
        return state
    }

    var rankOptions: [DiscussionReadRank] { [] }

    func viewDidLoad() {
        view?.fill(NewDiscussionDraft(content: content))
        render()
    }

    func didChangeContent(_ content: String) {
        self.content = content
        render()
    }

    func didChangeUploadingImageCount(_ count: Int) {
        uploadingImageCount = count
        render()
    }

    func closeDecision() -> NewDiscussionCloseDecision {
        if isSubmitting { return .blocked }
        return hasChanges ? .askSaveOrDiscardEdit : .close
    }

    func close(savingDraft: Bool) {
        viewController?.dismiss(animated: true)
    }

    func didTapPublish() {
        guard !isSubmitting, hasChanges else { return }
        guard uploadingImageCount == 0 else {
            view?.showValidationMessage("图片还在上传，传完再保存")
            return
        }
        if field == .signature, let message = ProfileSignatureValidator.validationMessage(for: content) {
            view?.showValidationMessage(message)
            return
        }
        var updated = original
        switch field {
        case .signature: updated.signature = content
        case .readme: updated.readme = content
        }
        isSubmitting = true
        render()
        Task { @MainActor [weak self, client] in
            do {
                try await client.saveIntroduction(updated)
                guard let self else { return }
                isSubmitting = false
                let onSaved = onSaved
                viewController?.dismiss(animated: true) { onSaved(updated) }
            } catch {
                guard let self else { return }
                isSubmitting = false
                render()
                view?.showSubmitFailure(
                    title: NSLocalizedString("保存失败", tableName: "Me", comment: ""),
                    message: error.localizedDescription,
                    allowsRetry: true
                )
            }
        }
    }

    private func render() {
        view?.render(state)
    }

    // 资料字段没有标题、板块、阅读限制和本机草稿。
    func retryLoadingUserLevel() {}
    func didChangeTitle(_ title: String) {}
    func didSelectCategory(_ category: DiscussionCategory) {}
    func didSelectRank(_ rank: DiscussionReadRank) {}
    func restorePendingDraft() {}
    func discardPendingDraft() {}
    func closeKeepingPendingDraft() {}
    func didTapOpenWebFallback() {}
}
