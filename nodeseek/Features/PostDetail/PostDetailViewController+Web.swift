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
            sheet.detents = [
                .custom(identifier: detentID) { _ in
                    preferredSize.height
                }
            ]
            sheet.selectedDetentIdentifier = detentID
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

private final class LoadedCommentPreviewViewController: UIViewController {
    private enum Layout {
        static let minimumWidth: CGFloat = 320
        static let maximumWidth: CGFloat = 420
        static let minimumHeight: CGFloat = 220
        static let maximumHeightRatio: CGFloat = 0.72
        static let fallbackContainerWidth: CGFloat = 390
        static let fallbackContainerHeight: CGFloat = 844
        static let headerHeight: CGFloat = 56
        static let footerHeight: CGFloat = 86
        static let verticalChrome: CGFloat = 54
        static let estimatedNonTextBlockHeight: CGFloat = 120
    }

    private let comment: Comment
    private let renderedContent: [RenderedContentBlock]?
    private let showsFullPostButton: Bool
    private let onOpenFullPost: () -> Void
    private let onReveal: () -> Void
    private let tableNode = ASTableNode(style: .plain)
    private let headerView = UIView()
    private let headerSeparator = UIView()
    private let footerStack = UIStackView()
    private let fullPostButton = UIButton(type: .system)
    private let revealButton = UIButton(type: .system)

    init(
        comment: Comment,
        renderedContent: [RenderedContentBlock]?,
        showsFullPostButton: Bool,
        onOpenFullPost: @escaping () -> Void,
        onReveal: @escaping () -> Void
    ) {
        self.comment = comment
        self.renderedContent = renderedContent
        self.showsFullPostButton = showsFullPostButton
        self.onOpenFullPost = onOpenFullPost
        self.onReveal = onReveal
        super.init(nibName: nil, bundle: nil)
    }

    static func preferredSize(
        comment: Comment,
        renderedContent: [RenderedContentBlock]?,
        containerSize: CGSize
    ) -> CGSize {
        let containerWidth = containerSize.width > 0 ? containerSize.width : Layout.fallbackContainerWidth
        let containerHeight = containerSize.height > 0 ? containerSize.height : Layout.fallbackContainerHeight
        let width = min(max(containerWidth - 32, Layout.minimumWidth), Layout.maximumWidth)
        let textWidth = max(
            width
                - PostDetailContentLayout.horizontalInset * 2
                - PostDetailContentLayout.avatarSize
                - PostDetailContentLayout.avatarSpacing,
            1
        )
        let bodyHeight = estimatedBodyHeight(
            comment: comment,
            renderedContent: renderedContent,
            width: textWidth
        )
        let rawHeight = Layout.headerHeight + Layout.footerHeight + Layout.verticalChrome + bodyHeight
        let maximumHeight = max(Layout.minimumHeight, floor(containerHeight * Layout.maximumHeightRatio))
        return CGSize(
            width: width,
            height: min(max(ceil(rawHeight), Layout.minimumHeight), maximumHeight)
        )
    }

    private static func estimatedBodyHeight(
        comment: Comment,
        renderedContent: [RenderedContentBlock]?,
        width: CGFloat
    ) -> CGFloat {
        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        var textHeight: CGFloat = 0
        var extraBlockHeight: CGFloat = 0
        if let renderedContent, renderedContent.isEmpty == false {
            for block in renderedContent {
                switch block {
                case .text(let attributedText):
                    textHeight += estimatedTextHeight(attributedText.string, width: width, font: bodyFont)
                case .image, .iframeLink, .imagePlaceholder, .table, .codeBlock, .unsupported, .quote:
                    extraBlockHeight += Layout.estimatedNonTextBlockHeight
                }
            }
        } else {
            textHeight = estimatedTextHeight(comment.contentHTML, width: width, font: bodyFont)
        }

        return max(
            PostDetailContentLayout.avatarSize,
            textHeight + extraBlockHeight + 96
        )
    }

    private static func estimatedTextHeight(_ text: String, width: CGFloat, font: UIFont) -> CGFloat {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedText.isEmpty == false else {
            return font.lineHeight
        }
        let rect = (normalizedText as NSString).boundingRect(
            with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(rect.height)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.layer.cornerRadius = 12
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        tableNode.dataSource = self
        tableNode.delegate = self
        configureContent()
        applyCurrentTheme()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        applyCurrentTheme()
    }

    private func applyCurrentTheme() {
        view.backgroundColor = .systemBackground
        headerView.backgroundColor = .systemBackground
        tableNode.view.backgroundColor = .systemBackground
        headerSeparator.backgroundColor = .separator
    }

    private func configureContent() {
        headerView.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.accessibilityLabel = "关闭"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        headerSeparator.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(closeButton)
        headerView.addSubview(headerSeparator)

        var fullPostConfiguration = UIButton.Configuration.bordered()
        fullPostConfiguration.title = "查看完整帖子"
        fullPostConfiguration.baseForegroundColor = .label
        fullPostConfiguration.cornerStyle = .medium
        fullPostConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        fullPostButton.configuration = fullPostConfiguration
        fullPostButton.addTarget(self, action: #selector(fullPostTapped), for: .touchUpInside)
        fullPostButton.titleLabel?.adjustsFontSizeToFitWidth = true
        fullPostButton.titleLabel?.minimumScaleFactor = 0.85

        var revealConfiguration = UIButton.Configuration.filled()
        revealConfiguration.title = "查看原楼"
        revealConfiguration.baseBackgroundColor = .secondarySystemBackground
        revealConfiguration.baseForegroundColor = .label
        revealConfiguration.cornerStyle = .medium
        revealConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        revealButton.configuration = revealConfiguration
        revealButton.addTarget(self, action: #selector(revealTapped), for: .touchUpInside)
        revealButton.titleLabel?.adjustsFontSizeToFitWidth = true
        revealButton.titleLabel?.minimumScaleFactor = 0.85

        footerStack.axis = .horizontal
        footerStack.alignment = .fill
        footerStack.distribution = .fillEqually
        footerStack.spacing = 10
        footerStack.translatesAutoresizingMaskIntoConstraints = false
        if showsFullPostButton {
            footerStack.addArrangedSubview(fullPostButton)
        }
        footerStack.addArrangedSubview(revealButton)

        tableNode.view.separatorStyle = .none
        tableNode.view.alwaysBounceVertical = false
        tableNode.contentInset = UIEdgeInsets(top: 12, left: 0, bottom: 14, right: 0)
        tableNode.view.verticalScrollIndicatorInsets = tableNode.contentInset
        tableNode.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableNode.view)
        view.addSubview(headerView)
        view.addSubview(footerStack)

        NSLayoutConstraint.activate([
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.heightAnchor.constraint(equalToConstant: Layout.headerHeight),

            headerSeparator.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            headerSeparator.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            headerSeparator.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            headerSeparator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            tableNode.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableNode.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableNode.view.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tableNode.view.bottomAnchor.constraint(equalTo: footerStack.topAnchor, constant: -12),

            footerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            footerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            footerStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            footerStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),

            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    @objc
    private func closeTapped() {
        dismiss(animated: true)
    }

    @objc
    private func fullPostTapped() {
        onOpenFullPost()
    }

    @objc
    private func revealTapped() {
        onReveal()
    }
}

extension LoadedCommentPreviewViewController: ASTableDataSource, ASTableDelegate {
    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        1
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        let comment = comment
        let renderedContent = renderedContent
        return { [weak self] in
            CommentCellNode(
                comment: comment,
                renderedBody: renderedContent,
                onImageTapped: { _, _ in },
                onLinkTapped: { _ in },
                onAuthorTapped: { _ in },
                onLikeTapped: { _ in },
                onChickenLegTapped: { _ in },
                onOpposeTapped: { _ in },
                onReplyTapped: { _ in },
                onQuoteTapped: { _ in },
                onTextLayoutInvalidated: {
                    self?.tableNode.relayoutItems()
                }
            )
        }
    }
}
