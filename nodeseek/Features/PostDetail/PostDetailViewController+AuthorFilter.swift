//
//  PostDetailViewController+AuthorFilter.swift
//  nodeseek
//
//  Created by Codex on 2026/10/29.
//

import UIKit

extension PostDetailViewController {
    enum AuthorFilterAutoLoad {
        // 已显示的匹配回复少于该值时继续向后翻页，避免列表太短无法触发滚动分页。
        static let minimumVisibleMatches = 5
        // 连续自动翻页每满 3 页停顿一下，避免长帖短时间内连续请求。
        static let pagesPerBurst = 3
        static let pauseInterval: TimeInterval = 0.8
    }

    var authorFilterMatchedCount: Int {
        guard let authorFilter else { return comments.count }
        return comments.reduce(0) { $0 + (authorFilter.matches($1) ? 1 : 0) }
    }

    var authorFilterBannerText: String {
        guard let authorFilter else { return "" }
        if authorFilterMatchedCount == 0, pagination?.nextPage == nil {
            return "\(authorFilter.bannerText) · 暂无"
        }
        return authorFilter.bannerText
    }

    func authorFilterMenuTitle(defaultTitle: String) -> String {
        authorFilter == nil ? defaultTitle : "查看全部回复"
    }

    /// 已在筛选中时任何入口都视为「查看全部回复」。
    func toggleAuthorFilter(_ filter: PostDetailAuthorFilter?, focusingCommentID: String?) {
        let nextFilter = authorFilter == nil ? filter : nil
        guard nextFilter != authorFilter else { return }
        AppLog.info(.postDetail, "切换详情作者筛选: author=\(nextFilter?.authorName ?? "nil"), isPoster=\(nextFilter?.isPoster == true)")
        authorFilter = nextFilter
        resetAuthorFilterAutoLoad()
        reloadTableData()
        updateLoadMoreCommentsFooter()
        scrollAfterAuthorFilterChange(focusingCommentID: nextFilter == nil ? focusingCommentID : nil)
        scheduleAuthorFilterAutoLoadIfNeeded(newMatchCount: authorFilterMatchedCount)
    }

    func resetAuthorFilterAutoLoad() {
        if let workItem = authorFilterAutoLoadWorkItem, workItem.isCancelled == false {
            // 停顿期间已显示加载指示器，取消时一并收起。
            workItem.cancel()
            hideLoadingMoreComments()
        }
        authorFilterAutoLoadWorkItem = nil
        authorFilterAutoLoadStreak = 0
    }

    /// 筛选后可能连续多页都没有目标回复，此时没有可滚动内容触发分页，需要主动向后翻页。
    func scheduleAuthorFilterAutoLoadIfNeeded(newMatchCount: Int) {
        authorFilterAutoLoadWorkItem?.cancel()
        authorFilterAutoLoadWorkItem = nil
        guard let authorFilter,
              displayMode == .content,
              pagination?.nextPage != nil,
              newMatchCount == 0 || authorFilterMatchedCount < AuthorFilterAutoLoad.minimumVisibleMatches else {
            authorFilterAutoLoadStreak = 0
            return
        }

        authorFilterAutoLoadStreak += 1
        let streak = authorFilterAutoLoadStreak
        let shouldPause = streak > 1 && (streak - 1) % AuthorFilterAutoLoad.pagesPerBurst == 0
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.authorFilter == authorFilter else { return }
            self.authorFilterAutoLoadWorkItem = nil
            AppLog.info(.postDetail, "详情作者筛选自动加载下一页: streak=\(streak), matched=\(self.authorFilterMatchedCount)")
            self.presenter.didApproachCommentEnd()
        }
        authorFilterAutoLoadWorkItem = workItem
        // 回调发生在 presenter 更新下一页页码之前，必须异步发起，否则会重复请求刚加载的页。
        DispatchQueue.main.async { [weak self] in
            guard let self, workItem.isCancelled == false else { return }
            guard shouldPause else {
                workItem.perform()
                return
            }
            self.showLoadingMoreComments()
            DispatchQueue.main.asyncAfter(deadline: .now() + AuthorFilterAutoLoad.pauseInterval, execute: workItem)
        }
    }

    private func scrollAfterAuthorFilterChange(focusingCommentID: String?) {
        let rows = detailRows
        let targetRow: Int
        let position: UICollectionView.ScrollPosition
        if let focusingCommentID,
           let commentIndex = comments.firstIndex(where: { $0.id == focusingCommentID }),
           let row = rows.firstIndex(where: {
               if case .comment(let index) = $0 { return index == commentIndex }
               return false
           }) {
            targetRow = row
            position = .centeredVertically
        } else if let row = rows.firstIndex(where: { if case .authorFilterBanner = $0 { return true }; return false }) {
            targetRow = row
            position = .top
        } else {
            targetRow = pageCompletionScrollRow()
            position = .top
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isViewLoaded else { return }
            self.collectionList.scroll(to: targetRow, position: position)
        }
    }
}
