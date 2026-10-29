//
//  NewDiscussionContract.swift
//  nodeseek
//

import Foundation

enum NewDiscussionUserLevelState: Equatable {
    case loading
    case loaded(Int)
    case failed
}

/// 发新帖、编辑已发帖子（只能改标题、正文、阅读限制），或编辑自己的评论（只能改正文）。
enum NewDiscussionMode: Equatable {
    case create
    case edit(EditableDiscussion)
    case editComment(EditableComment)
}

enum NewDiscussionSaveStatus: Equatable {
    case empty
    /// 编辑模式下内容和原文一致。
    case unchanged
    case saved
    /// 旧草稿还没决定恢复还是丢弃，新内容暂不保存。
    case waitingForDraftDecision
}

/// 点关闭时该怎么处理。
enum NewDiscussionCloseDecision: Equatable {
    case close
    /// 发布中，不允许关闭。
    case blocked
    /// 有内容：保存草稿并关闭 / 放弃草稿 / 继续编辑。
    case askSaveOrDiscard
    /// 旧草稿没处理又写了新内容：替换旧草稿 / 保留旧草稿 / 继续编辑。
    case askReplaceOldDraft
    /// 编辑帖子有改动：保存修改 / 留着下次继续 / 放弃修改。
    case askSaveEdit
}

struct NewDiscussionViewState: Equatable {
    let isEditing: Bool
    /// 编辑评论时的楼层号：没有标题和发布设置。
    let editingCommentFloor: Int?
    let category: DiscussionCategory?
    let rank: DiscussionReadRank
    let userLevel: NewDiscussionUserLevelState
    let pendingDraft: NewDiscussionDraft?
    let saveStatus: NewDiscussionSaveStatus
    let canPublish: Bool
    let isSubmitting: Bool
}

protocol NewDiscussionViewProtocol: AnyObject {
    func render(_ state: NewDiscussionViewState)
    func fill(_ draft: NewDiscussionDraft)
    func showValidationMessage(_ message: String)
    func confirmChickenLegFee(_ fee: Int, onConfirm: @escaping () -> Void)
    /// 编辑时改成私有要收手续费。
    func confirmPrivateRankFee(_ fee: Int, onConfirm: @escaping () -> Void)
    func showSubmitFailure(title: String, message: String, allowsRetry: Bool)
}

protocol NewDiscussionPresenterProtocol: AnyObject {
    var state: NewDiscussionViewState { get }
    var rankOptions: [DiscussionReadRank] { get }

    func viewDidLoad()
    func retryLoadingUserLevel()
    func didChangeTitle(_ title: String)
    func didChangeContent(_ content: String)
    func didSelectCategory(_ category: DiscussionCategory)
    func didSelectRank(_ rank: DiscussionReadRank)
    /// 图片上传任务数变化：上传中不能发布。
    func didChangeUploadingImageCount(_ count: Int)
    func restorePendingDraft()
    func discardPendingDraft()
    func closeDecision() -> NewDiscussionCloseDecision
    func close(savingDraft: Bool)
    func closeKeepingPendingDraft()
    func didTapPublish()
    func didTapOpenWebFallback()
}

protocol NewDiscussionRouterProtocol: AnyObject {
    func dismiss()
    func finishPublishing(route: NodeSeekPostRoute?)
    func openWebFallback()
}
