//
//  PostDetailViewController+Web.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import AsyncDisplayKit
import SafariServices
import UIKit

extension PostDetailViewController {
    @objc
    func openInBrowserTapped() {
        guard let targetURL = resolvedDetailURL() else {
            showError(message: "当前帖子链接无效，暂时无法打开。")
            return
        }

        if isNodeSeekHost(targetURL) {
            let webViewController = NodeSeekWebViewController(url: targetURL)
            if let navigationController {
                navigationController.pushViewController(webViewController, animated: true)
            } else {
                let navigationWrapper = UINavigationController(rootViewController: webViewController)
                present(navigationWrapper, animated: true)
            }
            return
        }

        let safariViewController = SFSafariViewController(url: targetURL)
        present(safariViewController, animated: true)
    }

    func shareCurrentPost(sourceItem: UIBarButtonItem?) {
        guard let targetURL = resolvedDetailURL() else {
            showError(message: "当前帖子链接无效，暂时无法分享。")
            return
        }

        let activityViewController = UIActivityViewController(activityItems: [targetURL], applicationActivities: nil)
        activityViewController.popoverPresentationController?.barButtonItem = sourceItem
        present(activityViewController, animated: true)
    }

    func copyCurrentPostLink() {
        guard let targetURL = resolvedDetailURL() else {
            showError(message: "当前帖子链接无效，暂时无法复制。")
            return
        }

        pasteboardStringWriter(targetURL.absoluteString)
        showToast(message: "已复制链接")
    }

    func handleContentLinkTap(_ url: URL) {
        if handleLoadedCommentAnchorIfNeeded(for: url) {
            return
        }

        guard let destination = PostDetailLinkResolver.destination(
            for: url,
            baseURL: baseURL,
            currentPostID: currentHeaderContent?.postID,
            currentPage: currentPage
        ) else { return }

        switch destination {
        case .currentPageAnchor(let anchorID):
            scrollToCurrentPageAnchor(anchorID)
        case .nativePost(let postID, let page, let url):
            let post = PostSummary(
                id: postID,
                title: "帖子 #\(postID)",
                url: url,
                authorName: "",
                nodeName: nil,
                replyCount: 0,
                lastActivityText: nil
            )
            let viewController = PostDetailRouter.createModule(
                post: post,
                page: page,
                initialAnchorID: NodeSeekPostRouteResolver.route(for: url, baseURL: baseURL)?.anchorID
            )
            showDetailDestination(viewController)
        case .userProfile(let url):
            openUserInfo(profileURL: url)
        case .web(let url):
            let webViewController = NodeSeekWebViewController(url: url)
            showDetailDestination(webViewController)
        case .safari(let url):
            present(SFSafariViewController(url: url), animated: true)
        }
    }

    func handleLoadedCommentAnchorIfNeeded(for url: URL) -> Bool {
        guard let anchorID = currentPostCommentAnchorID(from: url),
              anchorID != "0",
              let comment = loadedComment(matchingAnchorID: anchorID),
              let indexPath = indexPathForLoadedComment(comment) else {
            return false
        }

        if isLoadedCommentVisible(anchorID: anchorID, indexPath: indexPath) {
            scrollToCurrentPageAnchor(anchorID)
            return true
        }

        presentLoadedCommentPreview(comment: comment, anchorID: anchorID)
        return true
    }

    private func currentPostCommentAnchorID(from url: URL) -> String? {
        guard let resolvedURL = URL(string: url.relativeString, relativeTo: baseURL)?.absoluteURL,
              isNodeSeekHost(resolvedURL),
              let anchorID = normalizedAnchorID(from: resolvedURL),
              anchorID.isEmpty == false else {
            return nil
        }

        if resolvedURL.path.isEmpty || resolvedURL.path == "/" {
            return anchorID
        }

        guard let currentPostID = currentHeaderContent?.postID,
              let route = NodeSeekPostRouteResolver.route(for: resolvedURL, baseURL: baseURL),
              route.postID == currentPostID else {
            return nil
        }
        return route.anchorID
    }

    private func loadedComment(matchingAnchorID anchorID: String) -> Comment? {
        let normalizedTarget = normalizedAnchorText(anchorID)
        guard normalizedTarget.isEmpty == false else { return nil }
        return comments.first { comment in
            normalizedAnchorText(comment.anchorID) == normalizedTarget
                || normalizedAnchorText(comment.floorText) == normalizedTarget
        }
    }

    private func indexPathForLoadedComment(_ comment: Comment) -> IndexPath? {
        guard let commentIndex = comments.firstIndex(where: { $0.id == comment.id }),
              let row = detailRows.firstIndex(where: {
                  if case .comment(let index) = $0 {
                      return index == commentIndex
                  }
                  return false
              }) else {
            return nil
        }
        return IndexPath(row: row, section: 0)
    }

    private func isLoadedCommentVisible(anchorID: String, indexPath: IndexPath) -> Bool {
        #if DEBUG
        if let testVisibleAnchorIDs {
            return testVisibleAnchorIDs.contains(normalizedAnchorText(anchorID))
        }
        #endif
        return tableNode.indexPathsForVisibleRows().contains(indexPath)
    }

    private func presentLoadedCommentPreview(comment: Comment, anchorID: String) {
        #if DEBUG
        testPresentedLoadedCommentID = comment.id
        testHighlightedAnchorID = nil
        testPresentedPreviewUsesCommentCellRendering = true
        testPresentedPreviewKeepsCloseButtonOutsideContent = true
        testPresentedPreviewUsesBottomSheet = true
        testPresentedPreviewShowsFullPostButton = wasOpenedFromInitialAnchor
        #endif
        let renderedContent = commentRenderedCache[comment.id] ?? Self.makeRenderedContent(
            html: comment.contentHTML,
            baseURL: baseURL,
            maxImageWidth: availableCommentContentWidth
        )

        let previewController = LoadedCommentPreviewViewController(
            comment: comment,
            renderedContent: renderedContent,
            showsFullPostButton: wasOpenedFromInitialAnchor,
            onOpenFullPost: { [weak self] in
                self?.openFullPostFromFloorPreview()
            },
            onReveal: { [weak self] in
                self?.dismiss(animated: true) {
                    self?.scrollToCurrentPageAnchor(anchorID)
                }
            }
        )
        let preferredSize = LoadedCommentPreviewViewController.preferredSize(
            comment: comment,
            renderedContent: renderedContent,
            containerSize: view.bounds.size
        )
        previewController.overrideUserInterfaceStyle = traitCollection.userInterfaceStyle
        previewController.modalPresentationStyle = .pageSheet
        previewController.preferredContentSize = preferredSize
        #if DEBUG
        testPresentedPreviewPreferredHeight = preferredSize.height
        #endif
        if let sheet = previewController.sheetPresentationController {
            let detentID = UISheetPresentationController.Detent.Identifier("floor-preview")
            if #available(iOS 16.0, *) {
                sheet.detents = [
                    .custom(identifier: detentID) { _ in
                        preferredSize.height
                    }
                ]
                sheet.selectedDetentIdentifier = detentID
            } else {
                sheet.detents = [.medium(), .large()]
                sheet.selectedDetentIdentifier = .medium
            }
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            sheet.preferredCornerRadius = 18
        }
        present(previewController, animated: true)
    }

    private func openFullPostFromBeginning() {
        guard let header = currentHeaderContent else { return }
        let page = 1
        #if DEBUG
        testOpenedFullPostPage = page
        testOpenedFullPostAnchorWasNil = true
        #endif
        let post = PostSummary(
            id: header.postID,
            title: header.title,
            url: NodeSeekSite.postURL(id: header.postID, page: page),
            authorName: header.authorName,
            nodeName: nil,
            replyCount: 0,
            lastActivityText: header.metadataText,
            avatarURL: header.avatarURL
        )
        let viewController = PostDetailRouter.createModule(
            post: post,
            page: page,
            initialAnchorID: nil
        )
        if presentedViewController != nil {
            dismiss(animated: true) { [weak self] in
                self?.showDetailDestination(viewController)
            }
        } else {
            showDetailDestination(viewController)
        }
    }

    private func openFullPostFromFloorPreview() {
        guard wasOpenedFromInitialAnchor else { return }
        openFullPostFromBeginning()
    }

    var shouldShowInitialPageHint: Bool {
        initialPage > 1
    }

    func openFullPostFromEntryHint() {
        guard shouldShowInitialPageHint else { return }
        openFullPostFromBeginning()
    }

    func openUserInfo(profileURL: URL) {
        let viewController = UserInfoWebViewController(profileURL: profileURL)
        showDetailDestination(viewController)
    }

    func consumeInitialAnchorIfNeeded() {
        guard let anchorID = pendingInitialAnchorID else { return }
        pendingInitialAnchorID = nil
        DispatchQueue.main.async { [weak self] in
            self?.scrollToCurrentPageAnchor(anchorID)
        }
    }

    func scrollToCurrentPageAnchor(_ anchorID: String) {
        guard displayMode == .content else { return }
        guard let indexPath = indexPathForCurrentPageAnchor(anchorID) else { return }

        #if DEBUG
        testHighlightedAnchorID = normalizedAnchorText(anchorID)
        testPresentedLoadedCommentID = nil
        #endif
        tableNode.scrollToRow(at: indexPath, at: .middle, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            switch self.tableNode.nodeForRow(at: indexPath) {
            case let node as PostBodyCellNode:
                node.flashAnchorHighlight()
            case let node as CommentCellNode:
                node.flashAnchorHighlight()
            default:
                break
            }
        }
    }

    func indexPathForCurrentPageAnchor(_ anchorID: String) -> IndexPath? {
        if let commentIndex = comments.firstIndex(where: { comment in
            comment.anchorID == anchorID || comment.floorText == "#\(anchorID)"
        }), let row = detailRows.firstIndex(where: {
            if case .comment(let index) = $0 {
                return index == commentIndex
            }
            return false
        }) {
            return IndexPath(row: row, section: 0)
        }

        guard anchorID == "0", currentHeaderContent != nil,
              let row = detailRows.firstIndex(where: { if case .header = $0 { return true }; return false }) else {
            return nil
        }
        return IndexPath(row: row, section: 0)
    }

    #if DEBUG
    func testCurrentPageAnchorRow(for anchorID: String) -> Int? {
        indexPathForCurrentPageAnchor(anchorID)?.row
    }
    #endif

    func showDetailDestination(_ viewController: UIViewController) {
        if let navigationController {
            navigationController.pushViewController(viewController, animated: true)
        } else {
            present(UINavigationController(rootViewController: viewController), animated: true)
        }
    }

    func resolvedDetailURL() -> URL? {
        if let postID = currentHeaderContent?.postID, postID.isEmpty == false {
            return NodeSeekSite.postURL(id: postID, page: initialPage)
        }

        return sourcePostURL
    }

    func isNodeSeekHost(_ url: URL) -> Bool {
        NodeSeekSite.isNodeSeekHost(url)
    }

    #if DEBUG
    func testOpenFullPostFromFloorPreview() {
        openFullPostFromFloorPreview()
    }
    #endif

    private func normalizedAnchorID(from url: URL) -> String? {
        guard let fragment = url.fragment?.removingPercentEncoding else { return nil }
        return normalizedAnchorText(fragment)
    }

    private func normalizedAnchorText(_ text: String?) -> String {
        guard var text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.isEmpty == false else {
            return ""
        }
        while text.hasPrefix("#") {
            text.removeFirst()
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
