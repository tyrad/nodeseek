//
//  PostDetailViewController+PageJump.swift
//  nodeseek
//

import AsyncDisplayKit
import UIKit

extension PostDetailViewController {
    private enum PageIndicatorLayout {
        static let trailingInset: CGFloat = 16
        static let bottomInset: CGFloat = 16
        static let hideDelay: TimeInterval = 1.5
    }

    func configurePageIndicator() {
        pageIndicatorButton.addTarget(self, action: #selector(pageIndicatorTapped), for: .touchUpInside)
        view.addSubview(pageIndicatorButton)
        NSLayoutConstraint.activate([
            pageIndicatorButton.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -PageIndicatorLayout.trailingInset
            ),
            pageIndicatorButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -PageIndicatorLayout.bottomInset
            )
        ])
    }

    /// 总页数取分页条里最大的页码；站点分页条会省略中间页，但总会给出最后一页。
    var totalCommentPages: Int {
        guard let pagination = visiblePagination else { return 1 }
        let maxItemPage = pagination.items.map(\.page).max() ?? 1
        return max(maxItemPage, pagination.nextPage ?? 1, currentPage)
    }

    /// 平时按首条可见评论定位，滚到底部时按末条可见评论定位。
    var visibleCommentPage: Int {
        let firstLoadedPage = loadedCommentPageRanges.keys.min() ?? currentPage
        guard isViewLoaded else { return firstLoadedPage }
        let rows = detailRows
        let table = tableNode.view
        let atBottom = table.contentSize.height > 0
            && table.bounds.maxY - table.adjustedContentInset.bottom >= table.contentSize.height - 1
        let visibleRows = tableNode.indexPathsForVisibleRows().map(\.row).sorted(by: atBottom ? (>) : (<))
        for row in visibleRows where row < rows.count {
            guard case .comment(let commentIndex) = rows[row] else { continue }
            if let page = loadedCommentPageRanges.first(where: { $0.value.contains(commentIndex) })?.key {
                return page
            }
        }
        return firstLoadedPage
    }

    private var canShowPageIndicator: Bool {
        displayMode == .content
            && totalCommentPages > 1
            && replyEditorContainer.isHidden
            && presentedViewController == nil
    }

    func showPageIndicatorWhileScrolling() {
        pageIndicatorHideWorkItem?.cancel()
        guard canShowPageIndicator else {
            setPageIndicatorVisible(false)
            return
        }
        let page = visibleCommentPage
        let total = totalCommentPages
        let title = "\(page) / \(total)"
        if pageIndicatorButton.configuration?.title != title {
            pageIndicatorButton.configuration?.title = title
            pageIndicatorButton.accessibilityLabel = "第 \(page) 页，共 \(total) 页"
            pageIndicatorButton.accessibilityHint = "打开页码面板跳页"
        }
        setPageIndicatorVisible(true)
    }

    func schedulePageIndicatorHide() {
        pageIndicatorHideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.setPageIndicatorVisible(false)
        }
        pageIndicatorHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + PageIndicatorLayout.hideDelay, execute: workItem)
    }

    private func setPageIndicatorVisible(_ isVisible: Bool) {
        let isShowing = pageIndicatorButton.isHidden == false && pageIndicatorButton.alpha > 0
        guard isShowing != isVisible else { return }
        if isVisible {
            view.bringSubviewToFront(pageIndicatorButton)
            pageIndicatorButton.isHidden = false
        }
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.pageIndicatorButton.alpha = isVisible ? 1 : 0
        } completion: { _ in
            if self.pageIndicatorButton.alpha == 0 {
                self.pageIndicatorButton.isHidden = true
            }
        }
    }

    @objc
    func pageIndicatorTapped() {
        pageIndicatorHideWorkItem?.cancel()
        setPageIndicatorVisible(false)
        presentPagePicker()
    }

    func presentPagePicker() {
        guard totalCommentPages > 1 else { return }
        let picker = PostDetailPagePickerViewController(
            totalPages: totalCommentPages,
            currentPage: visibleCommentPage,
            loadedPages: Set(loadedCommentPageRanges.keys),
            exitsAuthorFilter: authorFilter != nil
        ) { [weak self] page in
            self?.jumpToCommentPage(page)
        }
        present(picker, animated: true)
    }

    func jumpToCommentPage(_ page: Int) {
        AppLog.info(.postDetail, "页码面板选中: page=\(page), visiblePage=\(visibleCommentPage), total=\(totalCommentPages)")
        let oldRowCount = detailRows.count
        let clearsAuthorFilter = authorFilter != nil
        // 筛选结果只覆盖已加载的页，跳页后已加载范围被清空，直接退出只看楼主更直观。
        if clearsAuthorFilter {
            authorFilter = nil
            resetAuthorFilterAutoLoad()
        }
        hasJumpedCommentPage = true
        // 行变了要立刻刷新，否则跳页结果回来前表格和数据源对不上。
        if clearsAuthorFilter || detailRows.count != oldRowCount {
            reloadTableData()
        }
        pendingPageJumpScroll = true
        presenter.didSelectCommentPage(page)
    }
}
