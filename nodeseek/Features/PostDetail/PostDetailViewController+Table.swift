//
//  PostDetailViewController+Table.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import AsyncDisplayKit
import UIKit

extension PostDetailViewController {
    var visiblePagination: PostDetailPagination? {
        guard let pagination, pagination.hasMultiplePages else { return nil }
        return pagination
    }

    var detailRows: [DetailRow] {
        var rows: [DetailRow] = []
        if currentHeaderContent != nil {
            rows.append(.header)
            if displayMode == .pageSkeleton || comments.isEmpty == false {
                rows.append(.postRepliesDivider)
            }
        }
        if displayMode == .pageSkeleton {
            rows.append(contentsOf: (0..<skeletonCommentRowCount).map(DetailRow.skeletonComment))
        } else {
            rows.append(contentsOf: comments.indices.map(DetailRow.comment))
        }
        return rows
    }

    func updatePageScrubber(isLoading: Bool, currentPageOverride: Int? = nil) {
        guard isViewLoaded else { return }
        guard let pagination = visiblePagination else {
            pageScrubberView.configure(currentPage: currentPage, totalPages: 1, isLoading: false)
            return
        }
        pageScrubberView.configure(
            currentPage: currentPageOverride ?? pagination.currentPage,
            totalPages: totalPageCount(from: pagination),
            isLoading: isLoading
        )
    }

    func totalPageCount(from pagination: PostDetailPagination) -> Int {
        let itemPages = pagination.items.map(\.page)
        let candidatePages = itemPages + [pagination.currentPage, pagination.previousPage, pagination.nextPage].compactMap { $0 }
        return max(candidatePages.max() ?? pagination.currentPage, pagination.currentPage)
    }

    func pageCompletionScrollRow() -> Int {
        let rows = detailRows
        if let commentRow = rows.firstIndex(where: { row in
            if case .comment = row {
                return true
            }
            return false
        }) {
            return commentRow
        }
        return rows.firstIndex(where: { if case .header = $0 { return true }; return false }) ?? 0
    }

    func fallbackPagination(from pagination: PostDetailPagination?, currentPage: Int) -> PostDetailPagination? {
        guard let pagination else { return nil }
        let normalizedPage = max(1, currentPage)
        let items = pagination.items.map { item in
            PostDetailPageItem(page: item.page, url: item.url, isCurrent: item.page == normalizedPage)
        }
        let pages = items.map(\.page).sorted()
        let previousPage = pages.last { $0 < normalizedPage }
        let nextPage = pages.first { $0 > normalizedPage }
        return PostDetailPagination(
            currentPage: normalizedPage,
            items: items,
            previousPage: previousPage,
            nextPage: nextPage
        )
    }
}

extension PostDetailViewController: ASTableDataSource, ASTableDelegate {
    func handlePostChickenLegTap(_ header: PostDetailHeaderContent) {
        guard header.isChickenLegClicked == false else {
            presenter.didTapPostChickenLeg()
            return
        }

        chickenLegConfirmationPresenter(self, .post) { [weak self] in
            self?.presenter.didTapPostChickenLeg()
        }
    }

    func handleCommentChickenLegTap(_ comment: Comment) {
        guard comment.isChickenLegClicked == false else {
            presenter.didTapCommentChickenLeg(comment)
            return
        }

        chickenLegConfirmationPresenter(self, .comment) { [weak self] in
            self?.presenter.didTapCommentChickenLeg(comment)
        }
    }

    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        if displayMode == .skeleton {
            return 1 + skeletonCommentRowCount
        }
        return detailRows.count
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        if displayMode == .skeleton {
            let kind: PostDetailSkeletonCellNode.Kind = indexPath.row == 0 ? .header : .comment
            return {
                PostDetailSkeletonCellNode(kind: kind)
            }
        }

        let rows = detailRows
        guard rows.indices.contains(indexPath.row) else {
            return { ASCellNode() }
        }

        switch rows[indexPath.row] {
        case .header:
            guard let header = currentHeaderContent else {
                return { ASCellNode() }
            }
            let renderedContent = headerRenderedContent
            let imageSizeProvider = makeCurrentImageSizeProvider()
            return { [weak self] in
                PostBodyCellNode(
                    content: header,
                    renderedContent: renderedContent,
                    onImageTapped: { imageURLs, initialIndex in
                        self?.presentPhotoBrowser(imageURLs: imageURLs, initialIndex: initialIndex)
                    },
                    onLinkTapped: { url in
                        self?.handleContentLinkTap(url)
                    },
                    onAuthorTapped: { url in
                        self?.openUserInfo(profileURL: url)
                    },
                    onLikeTapped: {
                        self?.presenter.didTapPostLike()
                    },
                    onChickenLegTapped: {
                        self?.handlePostChickenLegTap(header)
                    },
                    onOpposeTapped: {
                        self?.presenter.didTapPostOppose()
                    },
                    onFavoriteTapped: {
                        self?.presenter.didTapFavorite()
                    },
                    onReplyTapped: {
                        self?.handleReply(toPostHeader: header)
                    },
                    onCommentTapped: {
                        self?.presentReplyEditor(mode: .plain)
                    },
                    showsReplyActions: self?.showsReplyEntry == true,
                    onTextLayoutInvalidated: {
                        self?.scheduleAttachmentLayoutRefresh()
                    },
                    imageSizeProvider: imageSizeProvider,
                    onImageSizeResolved: { url, size in
                        self?.cacheDetailImageSize(size, for: url)
                    },
                    onImageHeightReduced: {
                        self?.scheduleHeaderReload()
                    }
                )
            }
        case .postRepliesDivider:
            return {
                PostRepliesDividerCellNode()
            }
        case .skeletonComment(_):
            return {
                PostDetailSkeletonCellNode(kind: .comment)
            }
        case .comment(let commentIndex):
            guard comments.indices.contains(commentIndex) else {
                return { ASCellNode() }
            }

            let comment = comments[commentIndex]
            let renderedBody = commentRenderedCache[comment.id]
            let imageSizeProvider = makeCurrentImageSizeProvider()
            return { [weak self] in
                CommentCellNode(
                    comment: comment,
                    renderedBody: renderedBody,
                    onImageTapped: { imageURLs, initialIndex in
                        self?.presentPhotoBrowser(imageURLs: imageURLs, initialIndex: initialIndex)
                    },
                    onLinkTapped: { url in
                        self?.handleContentLinkTap(url)
                    },
                    onAuthorTapped: { url in
                        self?.openUserInfo(profileURL: url)
                    },
                    onLikeTapped: { comment in
                        self?.presenter.didTapCommentLike(comment)
                    },
                    onChickenLegTapped: { comment in
                        self?.handleCommentChickenLegTap(comment)
                    },
                    onOpposeTapped: { comment in
                        self?.presenter.didTapCommentOppose(comment)
                    },
                    onReplyTapped: { comment in
                        self?.handleReply(to: comment)
                    },
                    onQuoteTapped: { comment in
                        self?.handleQuote(comment)
                    },
                    onTextLayoutInvalidated: {
                        self?.scheduleAttachmentLayoutRefresh()
                    },
                    imageSizeProvider: imageSizeProvider,
                    onImageSizeResolved: { url, size in
                        self?.cacheDetailImageSize(size, for: url)
                    },
                    onImageHeightReduced: {
                        self?.scheduleCommentReload(commentID: comment.id)
                    }
                )
            }
        }
    }

    private func makeCurrentImageSizeProvider() -> (URL) -> CGSize? {
        Self.makeImageSizeProvider(from: detailImageSizeCache)
    }

    private static func makeImageSizeProvider(from cache: [URL: CGSize]) -> (URL) -> CGSize? {
        { url in
            guard let resolvedURL = AvatarImageLoader.resolveImageURL(url),
                  let size = cache[resolvedURL],
                  size.width > 0,
                  size.height > 0 else {
                return nil
            }
            return size
        }
    }

    func tableNode(_ tableNode: ASTableNode, willDisplayRowWith node: ASCellNode) {
        guard displayMode == .content else { return }
        guard let indexPath = tableNode.indexPath(for: node) else { return }
        let rows = detailRows
        guard rows.indices.contains(indexPath.row),
              case .comment(let commentIndex) = rows[indexPath.row] else { return }
        guard comments.indices.contains(commentIndex) else { return }
        scheduleCommentRenderIfNeeded(for: comments[commentIndex])
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateNavigationAuthorVisibility(contentOffsetY: scrollView.contentOffset.y, animated: true)
    }
}
