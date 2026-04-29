//
//  PostDetailViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit
import AsyncDisplayKit
import DTCoreText
import OSLog
import SafariServices
import WebKit
import JXPhotoBrowser

enum PostDetailLinkDestination {
    case currentPageAnchor(String)
    case nativePost(postID: String, page: Int, url: URL)
    case web(URL)
    case safari(URL)
}

enum PostDetailLinkResolver {
    private static let postPathRegex = try! NSRegularExpression(
        pattern: "^/post-([0-9]+)-([0-9]+)/?$",
        options: []
    )

    static func destination(
        for url: URL,
        baseURL: URL,
        currentPostID: String? = nil,
        currentPage: Int = 1
    ) -> PostDetailLinkDestination? {
        guard let resolvedURL = URL(string: url.relativeString, relativeTo: baseURL)?.absoluteURL else {
            return nil
        }

        guard isNodeSeekHost(resolvedURL) else {
            return .safari(resolvedURL)
        }

        if let anchorID = normalizedAnchorID(from: resolvedURL),
           resolvedURL.path.isEmpty || resolvedURL.path == "/" {
            return .currentPageAnchor(anchorID)
        }

        let path = resolvedURL.path
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        if let match = postPathRegex.firstMatch(in: path, options: [], range: range),
           match.numberOfRanges >= 3,
           let postIDRange = Range(match.range(at: 1), in: path),
           let pageRange = Range(match.range(at: 2), in: path) {
            let postID = String(path[postIDRange])
            let page = Int(path[pageRange]) ?? 1
            let normalizedPage = max(page, 1)
            if let anchorID = normalizedAnchorID(from: resolvedURL),
               postID == currentPostID,
               normalizedPage == max(currentPage, 1) {
                return .currentPageAnchor(anchorID)
            }
            // TODO: 支持当前帖子跨页锚点在目标页加载完成后自动定位。
            return .nativePost(postID: postID, page: normalizedPage, url: resolvedURL)
        }

        return .web(resolvedURL)
    }

    private static func normalizedAnchorID(from url: URL) -> String? {
        guard let fragment = url.fragment?.removingPercentEncoding?.trimmingCharacters(in: .whitespacesAndNewlines),
              fragment.isEmpty == false else {
            return nil
        }
        return fragment.hasPrefix("#") ? String(fragment.dropFirst()) : fragment
    }

    private static func isNodeSeekHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "nodeseek.com" || host.hasSuffix(".nodeseek.com")
    }
}

class PostDetailViewController: UIViewController {
    private static let detailRenderLogger = Logger(subsystem: "com.nodeseek.app", category: "DetailRenderPipeline")

    private enum DisplayMode {
        case content
        case skeleton
    }

    private enum Layout {
        static let horizontalInset: CGFloat = PostDetailContentLayout.horizontalInset
    }

    private let presenter: PostDetailPresenterProtocol
    private let baseURL = URL(string: "https://www.nodeseek.com")!
    private let currentPage: Int
    private var currentHeaderContent: PostDetailHeaderContent?
    private var headerRenderedContent: [RenderedContentBlock]?
    private var comments: [Comment] = []
    private var commentRenderedCache: [String: [RenderedContentBlock]] = [:]
    private var renderedCommentIDs: Set<String> = []
    private var commentRenderInFlight: Set<String> = []
    private var renderGeneration: Int = 0
    private let sourcePostURL: URL?
    private var photoBrowserPresenter: DetailPhotoBrowserPresenter?
    private var attachmentLayoutRefreshWorkItem: DispatchWorkItem?
    private var tableReloadWorkItem: DispatchWorkItem?
    private var pendingReloadIndexPaths: Set<IndexPath> = []
    private var displayMode: DisplayMode = .skeleton
    private var hasRenderedDetailContent = false
    private let skeletonCommentRowCount = 4
    private let renderQueue = DispatchQueue(
        label: "com.nodeseek.app.postdetail.render",
        qos: .userInitiated
    )

    private let tableNode = ASTableNode(style: .plain)

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    init(
        presenter: PostDetailPresenterProtocol,
        initialHeader: PostDetailHeaderContent? = nil,
        sourcePostURL: URL? = nil,
        currentPage: Int = 1
    ) {
        self.presenter = presenter
        self.sourcePostURL = sourcePostURL
        self.currentPage = max(currentPage, 1)
        super.init(nibName: nil, bundle: nil)

        if let initialHeader {
            currentHeaderContent = initialHeader
            headerRenderedContent = nil
            scheduleHeaderRender(for: initialHeader)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        attachmentLayoutRefreshWorkItem?.cancel()
        tableReloadWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItems()
        setupUI()
        presenter.viewDidLoad()
    }

    private func configureNavigationItems() {
        let refreshButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshTapped)
        )
        refreshButton.accessibilityLabel = "刷新"

        let browserButton = UIBarButtonItem(
            image: UIImage(systemName: "safari"),
            style: .plain,
            target: self,
            action: #selector(openInBrowserTapped)
        )
        browserButton.accessibilityLabel = "在浏览器打开"
        navigationItem.rightBarButtonItems = [refreshButton, browserButton]
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground
        tableNode.dataSource = self
        tableNode.delegate = self
        tableNode.view.backgroundColor = .systemBackground
        tableNode.view.separatorStyle = .none
        tableNode.view.showsVerticalScrollIndicator = true
        tableNode.view.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tableNode.view)
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            tableNode.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableNode.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableNode.view.topAnchor.constraint(equalTo: view.topAnchor),
            tableNode.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        reloadTableData()
    }

    private func configureHeader(_ content: PostDetailHeaderContent, renderedContent: [RenderedContentBlock]?) {
        currentHeaderContent = content
        headerRenderedContent = renderedContent
    }

    private func reloadTableData() {
        tableReloadWorkItem?.cancel()
        pendingReloadIndexPaths.removeAll()
        guard isViewLoaded else { return }
        tableNode.reloadData()
    }

    private func scheduleHeaderReload() {
        guard currentHeaderContent != nil else { return }
        guard displayMode == .content else { return }
        scheduleRowsReload([IndexPath(row: 0, section: 0)])
    }

    private func scheduleCommentReload(commentID: String) {
        let headerRowCount = currentHeaderContent == nil ? 0 : 1
        guard let commentIndex = comments.firstIndex(where: { $0.id == commentID }) else { return }
        scheduleRowsReload([IndexPath(row: headerRowCount + commentIndex, section: 0)])
    }

    private func scheduleRowsReload(_ indexPaths: [IndexPath]) {
        guard isViewLoaded else { return }
        let rowCount = tableNode(self.tableNode, numberOfRowsInSection: 0)
        let validIndexPaths = indexPaths.filter { $0.section == 0 && $0.row >= 0 && $0.row < rowCount }
        guard validIndexPaths.isEmpty == false else { return }

        pendingReloadIndexPaths.formUnion(validIndexPaths)
        tableReloadWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isViewLoaded else { return }
            let reloadIndexPaths = self.pendingReloadIndexPaths.sorted {
                $0.section == $1.section ? $0.row < $1.row : $0.section < $1.section
            }
            self.pendingReloadIndexPaths.removeAll()
            guard reloadIndexPaths.isEmpty == false else { return }
            self.tableNode.reloadRows(at: reloadIndexPaths, with: .none)
        }
        tableReloadWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func showLoadingSkeletonIfNeeded() {
        guard hasRenderedDetailContent == false else { return }
        guard displayMode != .skeleton else { return }
        displayMode = .skeleton
        reloadTableData()
    }

    private func hideLoadingSkeleton() {
        guard displayMode == .skeleton else { return }
        displayMode = .content
        reloadTableData()
    }

    private func scheduleHeaderRender(for content: PostDetailHeaderContent) {
        let generation = renderGeneration
        let html = content.contentHTML
        let width = availableHeaderContentWidth
        let baseURL = baseURL
        renderQueue.async { [weak self] in
            let renderedContent = Self.makeRenderedContent(
                html: html,
                baseURL: baseURL,
                maxImageWidth: width
            )
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.renderGeneration == generation else { return }
                guard self.currentHeaderContent?.postID == content.postID else { return }
                self.configureHeader(content, renderedContent: renderedContent)
                self.scheduleHeaderReload()
            }
        }
    }

    private static func makeRenderedContent(
        html: String,
        baseURL: URL,
        maxImageWidth: CGFloat
    ) -> [RenderedContentBlock]? {
        let blocks = DTCoreTextHTMLContentRenderer().render(fragment: html, baseURL: baseURL, maxImageWidth: maxImageWidth)
        return blocks.isEmpty ? nil : blocks
    }

    private var availableHeaderContentWidth: CGFloat {
        let width = tableNode.view.bounds.width > 0 ? tableNode.view.bounds.width : view.bounds.width
        return max((width > 0 ? width : 320) - Layout.horizontalInset * 2, 1)
    }

    private var availableCommentContentWidth: CGFloat {
        let width = tableNode.view.bounds.width > 0 ? tableNode.view.bounds.width : view.bounds.width
        let contentWidth = (width > 0 ? width : 320)
            - PostDetailContentLayout.horizontalInset * 2
            - PostDetailContentLayout.avatarSize
            - PostDetailContentLayout.avatarSpacing
        return max(contentWidth, 1)
    }

    private func scheduleAttachmentLayoutRefresh() {
        attachmentLayoutRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isViewLoaded else { return }
            if NodeSeekDebugConfig.enableDetailRenderDiagnostics {
                let visibleRows = self.tableNode.indexPathsForVisibleRows().map { "\($0.section):\($0.row)" }.joined(separator: ",")
                Self.detailRenderLogger.info(
                    "scheduleAttachmentLayoutRefresh fire visible=\(visibleRows, privacy: .public) rows=\(self.tableNode(self.tableNode, numberOfRowsInSection: 0), privacy: .public)"
                )
            }
            self.tableNode.relayoutItems()
            self.tableNode.performBatch(animated: false, updates: {})
        }
        attachmentLayoutRefreshWorkItem = workItem
        if NodeSeekDebugConfig.enableDetailRenderDiagnostics {
            Self.detailRenderLogger.info("scheduleAttachmentLayoutRefresh queued")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    @objc
    private func refreshTapped() {
        presenter.viewDidLoad()
    }

    @objc
    private func openInBrowserTapped() {
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

    private func handleContentLinkTap(_ url: URL) {
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
            let viewController = PostDetailRouter.createModule(post: post, page: page)
            showDetailDestination(viewController)
        case .web(let url):
            let webViewController = CookieSharedWebViewController(url: url)
            showDetailDestination(webViewController)
        case .safari(let url):
            present(SFSafariViewController(url: url), animated: true)
        }
    }

    private func scrollToCurrentPageAnchor(_ anchorID: String) {
        guard displayMode == .content else { return }

        let headerRowCount = currentHeaderContent == nil ? 0 : 1
        let indexPath: IndexPath
        if (anchorID == "0" || anchorID == "1"), currentHeaderContent != nil {
            indexPath = IndexPath(row: 0, section: 0)
        } else if let commentIndex = comments.firstIndex(where: { comment in
            comment.anchorID == anchorID || comment.floorText == "#\(anchorID)"
        }) {
            indexPath = IndexPath(row: headerRowCount + commentIndex, section: 0)
        } else {
            return
        }

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

    private func showDetailDestination(_ viewController: UIViewController) {
        if let navigationController {
            navigationController.pushViewController(viewController, animated: true)
        } else {
            present(UINavigationController(rootViewController: viewController), animated: true)
        }
    }

    private func resolvedDetailURL() -> URL? {
        if let sourcePostURL {
            return sourcePostURL
        }

        guard let postID = currentHeaderContent?.postID, postID.isEmpty == false else { return nil }
        return URL(string: "https://www.nodeseek.com/post-\(postID)-1")
    }

    private func isNodeSeekHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "nodeseek.com" || host.hasSuffix(".nodeseek.com")
    }

    private func presentPhotoBrowser(imageURLs: [URL], initialIndex: Int) {
        guard imageURLs.isEmpty == false else { return }
        let presenter = DetailPhotoBrowserPresenter(imageURLs: imageURLs)
        photoBrowserPresenter = presenter
        presenter.present(from: self, initialIndex: initialIndex)
    }

    private func preheatCommentRender(for comments: [Comment]) {
        for comment in comments {
            scheduleCommentRenderIfNeeded(for: comment)
        }
    }

    private func scheduleCommentRenderIfNeeded(for comment: Comment) {
        let commentID = comment.id
        guard renderedCommentIDs.contains(commentID) == false else { return }
        guard commentRenderInFlight.insert(commentID).inserted else { return }

        let generation = renderGeneration
        let html = comment.contentHTML
        let width = availableCommentContentWidth
        let baseURL = baseURL
        renderQueue.async { [weak self] in
            let renderedContent = Self.makeRenderedContent(
                html: html,
                baseURL: baseURL,
                maxImageWidth: width
            )
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.renderGeneration == generation else { return }
                self.commentRenderInFlight.remove(commentID)
                self.renderedCommentIDs.insert(commentID)
                if let renderedContent {
                    self.commentRenderedCache[commentID] = renderedContent
                } else {
                    self.commentRenderedCache.removeValue(forKey: commentID)
                }
                self.scheduleCommentReload(commentID: commentID)
            }
        }
    }
}

extension PostDetailViewController: PostDetailViewProtocol {
    func showLoading() {
        if hasRenderedDetailContent {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
            showLoadingSkeletonIfNeeded()
        }
    }

    func hideLoading() {
        loadingIndicator.stopAnimating()
    }

    func showError(message: String) {
        hideLoadingSkeleton()
        let alert = UIAlertController(title: "错误", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    func render(detail: PostDetail) {
        title = "详情"
        renderGeneration += 1
        hasRenderedDetailContent = true
        displayMode = .content
        let headerContent = PostDetailHeaderContent(detail: detail)
        configureHeader(headerContent, renderedContent: nil)
        comments = detail.comments
        commentRenderedCache.removeAll(keepingCapacity: true)
        renderedCommentIDs.removeAll(keepingCapacity: true)
        commentRenderInFlight.removeAll(keepingCapacity: true)
        reloadTableData()
        scheduleHeaderRender(for: headerContent)
        preheatCommentRender(for: comments)
    }

    func renderLoginRequired(message: String) {
        title = "详情"
        renderGeneration += 1
        hasRenderedDetailContent = true
        displayMode = .content
        let existing = currentHeaderContent
        headerRenderedContent = nil
        let headerContent = PostDetailHeaderContent(
            postID: existing?.postID ?? "login-required",
            title: existing?.title ?? "需要登录",
            authorName: existing?.authorName ?? "NodeSeek",
            avatarURL: existing?.avatarURL,
            metadataText: existing?.metadataText,
            contentHTML: message
        )
        configureHeader(headerContent, renderedContent: nil)
        comments = []
        commentRenderedCache.removeAll(keepingCapacity: true)
        renderedCommentIDs.removeAll(keepingCapacity: true)
        commentRenderInFlight.removeAll(keepingCapacity: true)
        reloadTableData()
        scheduleHeaderRender(for: headerContent)
    }
}

private final class CookieSharedWebViewController: UIViewController, WKNavigationDelegate {
    private let url: URL
    private let webView: WKWebView
    private let cookieBridge: CookieBridge
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    init(url: URL) {
        self.url = url
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.cookieBridge = CookieBridge(
            webCookieStore: WKWebCookieStoreAdapter(
                store: configuration.websiteDataStore.httpCookieStore
            )
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "网页"
        configureNavigationItems()

        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingIndicator)
        loadingIndicator.startAnimating()

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        Task { @MainActor [weak self] in
            guard let self else { return }
            await cookieBridge.syncURLSessionCookiesToWebView()

            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadRevalidatingCacheData
            WebRequestFingerprint.applyHTMLHeaders(to: &request)
            webView.load(request)
        }
    }

    private func configureNavigationItems() {
        let copyAction = UIAction(
            title: "复制链接",
            image: UIImage(systemName: "doc.on.doc")
        ) { [weak self] _ in
            self?.copyCurrentPageURL()
        }
        let openAction = UIAction(
            title: "系统浏览器打开",
            image: UIImage(systemName: "safari")
        ) { [weak self] _ in
            self?.openInSystemBrowser()
        }

        let menu = UIMenu(children: [copyAction, openAction])
        let moreButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            primaryAction: nil,
            menu: menu
        )
        moreButton.accessibilityLabel = "网页更多操作"
        navigationItem.rightBarButtonItem = moreButton
    }

    private func currentPageURL() -> URL {
        webView.url ?? url
    }

    private func copyCurrentPageURL() {
        UIPasteboard.general.url = currentPageURL()
    }

    private func openInSystemBrowser() {
        UIApplication.shared.open(currentPageURL(), options: [:], completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingIndicator.stopAnimating()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        loadingIndicator.stopAnimating()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        loadingIndicator.stopAnimating()
    }
}

extension PostDetailViewController: ASTableDataSource, ASTableDelegate {
    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        if displayMode == .skeleton {
            return 1 + skeletonCommentRowCount
        }
        return (currentHeaderContent == nil ? 0 : 1) + comments.count
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        if displayMode == .skeleton {
            let kind: PostDetailSkeletonCellNode.Kind = indexPath.row == 0 ? .header : .comment
            return {
                PostDetailSkeletonCellNode(kind: kind)
            }
        }

        let headerRowCount = currentHeaderContent == nil ? 0 : 1
        if indexPath.row == 0, let header = currentHeaderContent {
            let renderedContent = headerRenderedContent
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
                    onTextLayoutInvalidated: {
                        self?.scheduleAttachmentLayoutRefresh()
                    }
                )
            }
        }

        let commentIndex = indexPath.row - headerRowCount
        guard comments.indices.contains(commentIndex) else {
            return { ASCellNode() }
        }

        let comment = comments[commentIndex]
        let renderedBody = commentRenderedCache[comment.id]
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
                onTextLayoutInvalidated: {
                    self?.scheduleAttachmentLayoutRefresh()
                }
            )
        }
    }

    func tableNode(_ tableNode: ASTableNode, willDisplayRowWith node: ASCellNode) {
        guard displayMode == .content else { return }
        let headerRowCount = currentHeaderContent == nil ? 0 : 1
        guard let indexPath = tableNode.indexPath(for: node), indexPath.row >= headerRowCount else { return }
        let commentIndex = indexPath.row - headerRowCount
        guard comments.indices.contains(commentIndex) else { return }
        scheduleCommentRenderIfNeeded(for: comments[commentIndex])
    }
}

private final class PostDetailHeaderView: UIView {
    private enum Layout {
        static let horizontalInset: CGFloat = 20
        static let topInset: CGFloat = 20
        static let bottomInset: CGFloat = 20
        static let avatarSize: CGFloat = 40
        static let avatarCornerRadius: CGFloat = 8
        static let avatarSpacing: CGFloat = 12
    }

    private let avatarLoader = AvatarImageLoader.shared

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .title2)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let authorRowView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .systemGray5
        imageView.layer.cornerRadius = Layout.avatarCornerRadius
        imageView.layer.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let contentView: DetailRichTextView = {
        let view = DetailRichTextView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private var contentTopConstraint: NSLayoutConstraint?
    var onImageTapped: (([URL], Int) -> Void)?
    var onTextLayoutInvalidated: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ content: PostDetailHeaderContent, attributedContent: NSAttributedString?) {
        titleLabel.text = content.title
        subtitleLabel.text = [content.authorName, content.metadataText].compactMap(\.self).joined(separator: " · ")
        contentView.configure(
            attributedContent,
            onImageTapped: onImageTapped,
            onLayoutInvalidated: onTextLayoutInvalidated
        )
        contentView.isHidden = attributedContent == nil
        contentTopConstraint?.constant = attributedContent == nil ? 0 : 16
        avatarLoader.loadAvatar(into: avatarImageView, postID: content.postID, avatarURL: content.avatarURL)
    }

    private func setupUI() {
        backgroundColor = .systemBackground
        addSubview(titleLabel)
        addSubview(authorRowView)
        addSubview(contentView)
        authorRowView.addSubview(avatarImageView)
        authorRowView.addSubview(subtitleLabel)

        let contentTopConstraint = contentView.topAnchor.constraint(equalTo: authorRowView.bottomAnchor, constant: 16)
        self.contentTopConstraint = contentTopConstraint

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.horizontalInset),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.horizontalInset),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: Layout.topInset),

            authorRowView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.horizontalInset),
            authorRowView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.horizontalInset),
            authorRowView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),

            avatarImageView.leadingAnchor.constraint(equalTo: authorRowView.leadingAnchor),
            avatarImageView.topAnchor.constraint(equalTo: authorRowView.topAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: authorRowView.bottomAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: Layout.avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: Layout.avatarSize),

            subtitleLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: Layout.avatarSpacing),
            subtitleLabel.trailingAnchor.constraint(equalTo: authorRowView.trailingAnchor),
            subtitleLabel.centerYAnchor.constraint(equalTo: authorRowView.centerYAnchor),
            subtitleLabel.topAnchor.constraint(greaterThanOrEqualTo: authorRowView.topAnchor),
            subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: authorRowView.bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.horizontalInset),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.horizontalInset),
            contentTopConstraint,
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Layout.bottomInset)
        ])
    }
}

private final class PostDetailCommentCell: UITableViewCell {
    static let reuseIdentifier = "PostDetailCommentCell"

    private enum Layout {
        static let horizontalInset: CGFloat = 12
        static let verticalInset: CGFloat = 6
        static let cardInset: CGFloat = 12
        static let avatarSize: CGFloat = 40
        static let avatarCornerRadius: CGFloat = 8
        static let avatarSpacing: CGFloat = 12
    }

    private let avatarLoader = AvatarImageLoader.shared

    private let cardView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .systemGray5
        imageView.layer.cornerRadius = Layout.avatarCornerRadius
        imageView.layer.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let metaLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let bodyView: DetailRichTextView = {
        let view = DetailRichTextView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    var onImageTapped: (([URL], Int) -> Void)?
    var onTextLayoutInvalidated: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarLoader.cancel(on: avatarImageView)
        avatarImageView.image = nil
        metaLabel.text = nil
        bodyView.configure(nil, onImageTapped: nil, onLayoutInvalidated: nil)
        onImageTapped = nil
        onTextLayoutInvalidated = nil
    }

    func configure(comment: Comment, attributedBody: NSAttributedString?) {
        metaLabel.text = [
            comment.floorText,
            comment.authorName,
            comment.createdAtText
        ].compactMap(\.self).joined(separator: " · ")
        bodyView.configure(
            attributedBody,
            onImageTapped: onImageTapped,
            onLayoutInvalidated: onTextLayoutInvalidated
        )
        avatarLoader.loadAvatar(into: avatarImageView, postID: comment.id, avatarURL: comment.avatarURL)
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .systemBackground
        contentView.backgroundColor = .systemBackground
        contentView.addSubview(cardView)
        cardView.addSubview(avatarImageView)
        cardView.addSubview(metaLabel)
        cardView.addSubview(bodyView)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Layout.horizontalInset),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Layout.horizontalInset),
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Layout.verticalInset),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Layout.verticalInset),

            avatarImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Layout.cardInset),
            avatarImageView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: Layout.cardInset),
            avatarImageView.widthAnchor.constraint(equalToConstant: Layout.avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: Layout.avatarSize),

            metaLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: Layout.avatarSpacing),
            metaLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Layout.cardInset),
            metaLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: Layout.cardInset),

            bodyView.leadingAnchor.constraint(equalTo: metaLabel.leadingAnchor),
            bodyView.trailingAnchor.constraint(equalTo: metaLabel.trailingAnchor),
            bodyView.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 8),
            bodyView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -Layout.cardInset),
            bodyView.bottomAnchor.constraint(greaterThanOrEqualTo: avatarImageView.bottomAnchor)
        ])
    }

}

final class DetailRichTextView: DTAttributedTextContentView, DTAttributedTextContentViewDelegate {
    private enum QuoteStyle {
        static let borderWidth: CGFloat = 3
        static let borderColor = UIColor(red: 208 / 255, green: 215 / 255, blue: 222 / 255, alpha: 1)
        static let cornerRadius: CGFloat = 4
    }

    private static let logger = Logger(subsystem: "com.nodeseek.app", category: "DetailRichTextView")

    private var imageTapHandler: (([URL], Int) -> Void)?
    private var linkTapHandler: ((URL) -> Void)?
    private var layoutInvalidatedHandler: (() -> Void)?
    private var attachmentLayoutUpdatedHandler: ((URL, CGSize, CGSize) -> Void)?
    private var lastLayoutWidth: CGFloat = 0
    private let diagnosticID = String(UUID().uuidString.prefix(8))

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        delegate = self
        shouldDrawImages = false
        shouldDrawLinks = true
        shouldLayoutCustomSubviews = true
        layoutFrameHeightIsConstrainedByBounds = false
        isUserInteractionEnabled = true
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        _ attributedText: NSAttributedString?,
        onImageTapped: (([URL], Int) -> Void)?,
        onLinkTapped: ((URL) -> Void)? = nil,
        onLayoutInvalidated: (() -> Void)?,
        onAttachmentLayoutUpdated: ((URL, CGSize, CGSize) -> Void)? = nil
    ) {
        imageTapHandler = onImageTapped
        linkTapHandler = onLinkTapped
        layoutInvalidatedHandler = onLayoutInvalidated
        attachmentLayoutUpdatedHandler = onAttachmentLayoutUpdated
        attributedString = attributedText ?? NSAttributedString()
        logDiagnostics(
            "configure length=\(attributedString.length) bounds=\(Self.string(from: bounds.size)) attachments=\(attachmentDiagnostics())"
        )
        removeAllCustomViews()
        removeAllCustomViewsForLinks()
        layouter = nil
        relayoutText()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        let width = bounds.width
        if width > 0, abs(width - lastLayoutWidth) > 0.5 {
            lastLayoutWidth = width
            logDiagnostics("layoutSubviews widthChanged width=\(Self.numberString(width)) bounds=\(Self.string(from: bounds.size))")
            layouter = nil
            relayoutText()
            invalidateIntrinsicContentSize()
        }
        super.layoutSubviews()
    }

    override var intrinsicContentSize: CGSize {
        richTextSize(constrainedToWidth: bounds.width)
    }

    override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
        let width = targetSize.width > 0 ? targetSize.width : bounds.width
        return richTextSize(constrainedToWidth: width)
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        let width = targetSize.width > 0 ? targetSize.width : bounds.width
        return richTextSize(constrainedToWidth: width)
    }

    func attributedTextContentView(
        _ attributedTextContentView: DTAttributedTextContentView,
        viewFor attachment: DTTextAttachment,
        frame: CGRect
    ) -> UIView? {
        guard attachment is DTImageTextAttachment,
              let contentURL = attachment.contentURL else {
            logDiagnostics("viewForAttachment skipped type=\(String(describing: type(of: attachment))) contentURL=\(String(describing: attachment.contentURL)) frame=\(Self.string(from: frame))")
            return nil
        }

        logDiagnostics(
            "viewForAttachment url=\(contentURL.absoluteString) frame=\(Self.string(from: frame)) original=\(Self.string(from: attachment.originalSize)) display=\(Self.string(from: attachment.displaySize)) bounds=\(Self.string(from: bounds.size))"
        )
        let imageView = DetailInlineImageView(
            frame: frame,
            imageURL: contentURL,
            targetPixelWidth: targetImagePointSide(
                for: contentURL,
                originalSize: attachment.originalSize
            ) * displayScale,
            displayScale: displayScale,
            onImageLoaded: { [weak self] loadedURL, imageSize in
                self?.handleLoadedImage(loadedURL, imageSize: imageSize)
            },
            onImageTapped: { [weak self] tappedURL in
                self?.handleImageTap(tappedURL)
            }
        )
        imageView.contentMode = contentMode(for: contentURL, originalSize: attachment.originalSize)
        imageView.clipsToBounds = true
        imageView.image = (attachment as? DTImageTextAttachment)?.image

        return imageView
    }

    func attributedTextContentView(
        _ attributedTextContentView: DTAttributedTextContentView,
        viewForLink url: URL,
        identifier: String,
        frame: CGRect
    ) -> UIView? {
        DetailLinkOverlayButton(frame: frame, url: url) { [weak self] tappedURL in
            self?.linkTapHandler?(tappedURL)
        }
    }

    func attributedTextContentView(
        _ attributedTextContentView: DTAttributedTextContentView,
        shouldDrawBackgroundFor textBlock: DTTextBlock,
        frame: CGRect,
        context: CGContext,
        for layoutFrame: DTCoreTextLayoutFrame
    ) -> Bool {
        guard let backgroundColor = textBlock.backgroundColor else { return true }

        let quoteFrame = frame
        let backgroundPath = UIBezierPath(roundedRect: quoteFrame, cornerRadius: QuoteStyle.cornerRadius)

        context.saveGState()
        context.setFillColor(backgroundColor.cgColor)
        context.addPath(backgroundPath.cgPath)
        context.fillPath()
        context.setFillColor(QuoteStyle.borderColor.cgColor)
        context.fill(CGRect(
            x: quoteFrame.minX,
            y: quoteFrame.minY,
            width: QuoteStyle.borderWidth,
            height: quoteFrame.height
        ))
        context.restoreGState()
        return false
    }

    private func handleLoadedImage(_ url: URL, imageSize: CGSize) {
        guard let displaySize = updateImageAttachments(matching: url, originalSize: imageSize) else {
            logDiagnostics(
                "imageLoaded noAttachmentUpdate url=\(url.absoluteString) imageSize=\(Self.string(from: imageSize)) attachments=\(attachmentDiagnostics())"
            )
            return
        }
        logDiagnostics(
            "imageLoaded updated url=\(url.absoluteString) imageSize=\(Self.string(from: imageSize)) display=\(Self.string(from: displaySize))"
        )
        attachmentLayoutUpdatedHandler?(url, imageSize, displaySize)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.removeAllCustomViews()
            self.removeAllCustomViewsForLinks()
            self.layouter = nil
            self.relayoutText()
            self.invalidateIntrinsicContentSize()
            self.logDiagnostics(
                "imageLoaded relayout intrinsic=\(Self.string(from: self.intrinsicContentSize)) bounds=\(Self.string(from: self.bounds.size))"
            )
            self.setNeedsLayout()
            self.layoutInvalidatedHandler?()
        }
    }

    private func updateImageAttachments(matching url: URL, originalSize: CGSize) -> CGSize? {
        guard attributedString.length > 0,
              originalSize.width > 0,
              originalSize.height > 0 else {
            return nil
        }

        var updatedDisplaySize: CGSize?
        attributedString.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, _, _ in
            guard let attachment = value as? DTTextAttachment,
                  attachment.contentURL == url else {
                return
            }

            let isSticker = isStickerImageURL(url)
            let presentation = DetailImageLayout.presentation(
                for: originalSize,
                maxWidth: maxImageWidth(for: url),
                isSticker: isSticker
            )
            let displaySize = presentation.size
            if isSticker == false, attachment.displaySize == displaySize {
                logDiagnostics(
                    "normal attachment fixed size unchanged url=\(url.absoluteString) imageSize=\(Self.string(from: originalSize)) display=\(Self.string(from: displaySize))"
                )
                return
            }
            guard attachment.originalSize != originalSize || attachment.displaySize != displaySize else {
                logDiagnostics(
                    "attachment already current url=\(url.absoluteString) original=\(Self.string(from: originalSize)) display=\(Self.string(from: displaySize))"
                )
                return
            }

            attachment.originalSize = originalSize
            attachment.displaySize = displaySize
            updatedDisplaySize = displaySize
        }
        return updatedDisplaySize
    }

    private func handleImageTap(_ tappedURL: URL) {
        guard let onImageTapped = imageTapHandler,
              let resolvedTappedURL = AvatarImageLoader.resolveImageURL(tappedURL) else {
            return
        }

        let urls = previewImageURLs()
        guard let index = urls.firstIndex(of: resolvedTappedURL) else { return }
        onImageTapped(urls, index)
    }

    private func previewImageURLs() -> [URL] {
        guard attributedString.length > 0 else { return [] }

        var urls: [URL] = []
        attributedString.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, _, _ in
            guard let attachment = value as? DTTextAttachment,
                  let contentURL = attachment.contentURL,
                  let resolvedURL = AvatarImageLoader.resolveImageURL(contentURL),
                  isStickerImageURL(resolvedURL) == false,
                  urls.contains(resolvedURL) == false else {
                return
            }
            urls.append(resolvedURL)
        }
        return urls
    }

    private func maxImageWidth(for url: URL) -> CGFloat {
        let width = bounds.width > 0 ? bounds.width : 320
        return isStickerImageURL(url) ? min(width, DetailImageLayout.fixedStickerWidth) : width
    }

    private func targetImagePointSide(for url: URL, originalSize: CGSize) -> CGFloat {
        let maxWidth = maxImageWidth(for: url)
        guard originalSize.width > 0, originalSize.height > 0 else {
            return isStickerImageURL(url) ? maxWidth : max(maxWidth, DetailImageLayout.maxImageHeight)
        }

        return DetailImageLayout.presentation(
            for: originalSize,
            maxWidth: maxWidth,
            isSticker: isStickerImageURL(url)
        ).targetPointSide
    }

    private func contentMode(for url: URL, originalSize: CGSize) -> UIView.ContentMode {
        let mode = DetailImageLayout.presentation(
            for: originalSize,
            maxWidth: maxImageWidth(for: url),
            isSticker: isStickerImageURL(url)
        ).mode

        switch mode {
        case .thumbnailCrop:
            return .scaleAspectFill
        case .aspectFit:
            return .scaleAspectFit
        }
    }

    private func richTextSize(constrainedToWidth width: CGFloat) -> CGSize {
        guard attributedString.length > 0 else {
            return CGSize(width: UIView.noIntrinsicMetric, height: 0)
        }
        guard width > 0 else {
            return CGSize(width: UIView.noIntrinsicMetric, height: 1)
        }

        if abs(bounds.width - width) > 0.5 {
            var adjustedBounds = bounds
            adjustedBounds.size.width = width
            bounds = adjustedBounds
        }
        layoutFrame = nil
        _ = layoutFrame
        let size = super.intrinsicContentSize
        logDiagnostics(
            "richTextSize width=\(Self.numberString(width)) result=\(Self.string(from: size)) bounds=\(Self.string(from: bounds.size)) attachments=\(attachmentDiagnostics())"
        )
        return CGSize(width: UIView.noIntrinsicMetric, height: ceil(max(size.height, 1)))
    }

    private var displayScale: CGFloat {
        window?.windowScene?.screen.scale ?? traitCollection.displayScale
    }

    private func isStickerImageURL(_ url: URL) -> Bool {
        url.absoluteString.lowercased().contains("sticker")
    }

    private func logDiagnostics(_ message: String) {
        guard NodeSeekDebugConfig.enableDetailRenderDiagnostics else { return }
        Self.logger.info("[\(self.diagnosticID, privacy: .public)] \(message, privacy: .public)")
    }

    private func attachmentDiagnostics() -> String {
        guard attributedString.length > 0 else { return "[]" }
        var parts: [String] = []
        attributedString.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, _, _ in
            guard let attachment = value as? DTTextAttachment else { return }
            parts.append(
                "url=\(attachment.contentURL?.absoluteString ?? "nil"),original=\(Self.string(from: attachment.originalSize)),display=\(Self.string(from: attachment.displaySize))"
            )
        }
        if parts.count > 6 {
            return "[\(parts.prefix(6).joined(separator: " | ")) | ... total=\(parts.count)]"
        }
        return "[\(parts.joined(separator: " | "))]"
    }

    private static func string(from rect: CGRect) -> String {
        "x=\(numberString(rect.origin.x)),y=\(numberString(rect.origin.y)),w=\(numberString(rect.width)),h=\(numberString(rect.height))"
    }

    private static func string(from size: CGSize) -> String {
        "\(numberString(size.width))x\(numberString(size.height))"
    }

    private static func numberString(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }

}

private final class DetailLinkOverlayButton: UIButton {
    private let url: URL
    private let onTapped: (URL) -> Void

    init(frame: CGRect, url: URL, onTapped: @escaping (URL) -> Void) {
        self.url = url
        self.onTapped = onTapped
        super.init(frame: frame)
        backgroundColor = .clear
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func handleTap() {
        onTapped(url)
    }
}

final class DetailInlineImageView: UIImageView {
    private static let logger = Logger(subsystem: "com.nodeseek.app", category: "DetailInlineImageView")

    private let imageURL: URL
    private let targetPixelWidth: CGFloat
    private let displayScale: CGFloat
    private let onImageLoaded: (URL, CGSize) -> Void
    private let onImageTapped: (URL) -> Void
    private var loadToken: UUID?
    private let diagnosticID = String(UUID().uuidString.prefix(8))

    init(
        frame: CGRect,
        imageURL: URL,
        targetPixelWidth: CGFloat,
        displayScale: CGFloat,
        onImageLoaded: @escaping (URL, CGSize) -> Void,
        onImageTapped: @escaping (URL) -> Void
    ) {
        self.imageURL = imageURL
        self.targetPixelWidth = targetPixelWidth
        self.displayScale = displayScale
        self.onImageLoaded = onImageLoaded
        self.onImageTapped = onImageTapped
        super.init(frame: frame)
        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()

        guard superview != nil else {
            logDiagnostics("removed url=\(imageURL.absoluteString) frame=\(Self.string(from: frame))")
            loadToken = nil
            return
        }
        guard loadToken == nil else { return }

        let token = UUID()
        loadToken = token
        logDiagnostics(
            "startLoad url=\(imageURL.absoluteString) frame=\(Self.string(from: frame)) targetPixelWidth=\(Self.numberString(targetPixelWidth)) displayScale=\(Self.numberString(displayScale))"
        )
        DetailImageLoader.shared.loadImageForInline(
            imageURL,
            maxPixelWidth: targetPixelWidth,
            displayScale: displayScale
        ) { [weak self] image in
            DispatchQueue.main.async {
                guard let self, self.loadToken == token else { return }
                self.image = image
                if let image {
                    self.logDiagnostics(
                        "loaded url=\(self.imageURL.absoluteString) imageSize=\(Self.string(from: image.size)) frame=\(Self.string(from: self.frame))"
                    )
                    self.onImageLoaded(self.imageURL, image.size)
                } else {
                    self.logDiagnostics("loaded nil url=\(self.imageURL.absoluteString)")
                }
            }
        }
    }

    @objc
    private func handleTap() {
        onImageTapped(imageURL)
    }

    private func logDiagnostics(_ message: String) {
        guard NodeSeekDebugConfig.enableDetailRenderDiagnostics else { return }
        Self.logger.info("[\(self.diagnosticID, privacy: .public)] \(message, privacy: .public)")
    }

    private static func string(from rect: CGRect) -> String {
        "x=\(numberString(rect.origin.x)),y=\(numberString(rect.origin.y)),w=\(numberString(rect.width)),h=\(numberString(rect.height))"
    }

    private static func string(from size: CGSize) -> String {
        "\(numberString(size.width))x\(numberString(size.height))"
    }

    private static func numberString(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}

private final class DetailPhotoBrowserPresenter: NSObject, JXPhotoBrowserDelegate {
    private let imageURLs: [URL]

    init(imageURLs: [URL]) {
        self.imageURLs = imageURLs
        super.init()
    }

    func present(from viewController: UIViewController, initialIndex: Int) {
        guard imageURLs.isEmpty == false else { return }

        let browser = JXPhotoBrowserViewController()
        browser.delegate = self
        browser.initialIndex = min(max(initialIndex, 0), imageURLs.count - 1)
        browser.transitionType = .fade
        browser.addOverlay(JXPageIndicatorOverlay())
        browser.present(from: viewController)
    }

    func numberOfItems(in browser: JXPhotoBrowserViewController) -> Int {
        imageURLs.count
    }

    func photoBrowser(
        _ browser: JXPhotoBrowserViewController,
        cellForItemAt index: Int,
        at indexPath: IndexPath
    ) -> JXPhotoBrowserAnyCell {
        browser.dequeueReusableCell(
            withReuseIdentifier: JXZoomImageCell.reuseIdentifier,
            for: indexPath
        ) as! JXZoomImageCell
    }

    func photoBrowser(_ browser: JXPhotoBrowserViewController, willDisplay cell: JXPhotoBrowserAnyCell, at index: Int) {
        guard let photoCell = cell as? JXZoomImageCell else { return }
        let imageURL = imageURLs[index]
        let requestKey = imageURL.absoluteString
        photoCell.imageView.image = nil
        photoCell.imageView.accessibilityIdentifier = requestKey
        DetailImageLoader.shared.loadImageForPreview(imageURL) { [weak photoCell] image in
            DispatchQueue.main.async {
                guard let photoCell else { return }
                guard photoCell.imageView.accessibilityIdentifier == requestKey else { return }
                photoCell.imageView.image = image
                photoCell.setNeedsLayout()
            }
        }
    }

    func photoBrowser(_ browser: JXPhotoBrowserViewController, didEndDisplaying cell: JXPhotoBrowserAnyCell, at index: Int) {
        guard let photoCell = cell as? JXZoomImageCell else { return }
        photoCell.imageView.accessibilityIdentifier = nil
        photoCell.imageView.image = nil
    }
}
