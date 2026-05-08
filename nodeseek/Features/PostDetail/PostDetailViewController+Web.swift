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
            let webViewController = CookieSharedWebViewController(url: targetURL)
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

        UIPasteboard.general.string = targetURL.absoluteString
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
            let webViewController = CookieSharedWebViewController(url: url)
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
        #endif

        let previewController = LoadedCommentPreviewViewController(
            comment: comment,
            renderedContent: commentRenderedCache[comment.id],
            onReveal: { [weak self] in
                self?.dismiss(animated: true) {
                    self?.scrollToCurrentPageAnchor(anchorID)
                }
            }
        )
        previewController.modalPresentationStyle = .popover
        previewController.preferredContentSize = CGSize(
            width: min(max(view.bounds.width - 32, 320), 420),
            height: 360
        )
        if let popover = previewController.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(previewController, animated: true)
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
            return NodeSeekSite.postURL(id: postID, page: currentPage)
        }

        return sourcePostURL
    }

    func isNodeSeekHost(_ url: URL) -> Bool {
        NodeSeekSite.isNodeSeekHost(url)
    }

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
    private let comment: Comment
    private let renderedContent: [RenderedContentBlock]?
    private let onReveal: () -> Void

    init(
        comment: Comment,
        renderedContent: [RenderedContentBlock]?,
        onReveal: @escaping () -> Void
    ) {
        self.comment = comment
        self.renderedContent = renderedContent
        self.onReveal = onReveal
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 12
        view.layer.cornerCurve = .continuous
        configureContent()
    }

    private func configureContent() {
        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.text = AuthorDisplayPolicy.displayName(from: comment.authorName) ?? comment.authorName

        let metadataLabel = UILabel()
        metadataLabel.font = .preferredFont(forTextStyle: .footnote)
        metadataLabel.textColor = .secondaryLabel
        metadataLabel.numberOfLines = 1
        metadataLabel.text = [comment.floorText, comment.createdAtText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: " · ")

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.accessibilityLabel = "关闭"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, closeButton])
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.spacing = 8

        let bodyStack = UIStackView()
        bodyStack.axis = .vertical
        bodyStack.alignment = .fill
        bodyStack.spacing = 10
        bodyStack.addArrangedSubview(headerStack)
        bodyStack.addArrangedSubview(metadataLabel)
        bodyStack.addArrangedSubview(makeSeparator())
        addRenderedContent(to: bodyStack)

        let revealButton = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = "查看原楼"
        configuration.baseBackgroundColor = .label
        configuration.baseForegroundColor = .systemBackground
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        revealButton.configuration = configuration
        revealButton.addTarget(self, action: #selector(revealTapped), for: .touchUpInside)
        bodyStack.addArrangedSubview(revealButton)

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        bodyStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(bodyStack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            bodyStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            bodyStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            bodyStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 14),
            bodyStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -14),
            bodyStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),

            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    private func addRenderedContent(to stackView: UIStackView) {
        let textBlocks = renderedContent?.compactMap { block -> NSAttributedString? in
            guard case .text(let text) = block else { return nil }
            return text
        } ?? []

        if textBlocks.isEmpty {
            stackView.addArrangedSubview(makeTextLabel(text: strippedHTML(comment.contentHTML)))
            return
        }

        for text in textBlocks {
            let label = UILabel()
            label.attributedText = text
            label.numberOfLines = 0
            stackView.addArrangedSubview(label)
        }
    }

    private func makeTextLabel(text: String) -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        label.numberOfLines = 0
        label.text = text
        return label
    }

    private func makeSeparator() -> UIView {
        let view = UIView()
        view.backgroundColor = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        return view
    }

    private func strippedHTML(_ html: String) -> String {
        let data = Data(html.utf8)
        let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        )
        let text = attributed?.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text! : html
    }

    @objc
    private func closeTapped() {
        dismiss(animated: true)
    }

    @objc
    private func revealTapped() {
        onReveal()
    }
}
