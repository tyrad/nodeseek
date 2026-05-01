//
//  PostDetailViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit
import AsyncDisplayKit
import OSLog

enum PostDetailLinkDestination {
    case currentPageAnchor(String)
    case nativePost(postID: String, page: Int, url: URL)
    case userProfile(URL)
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

        if let redirectTargetURL = decodedHTTPRedirectTarget(from: resolvedURL) {
            return .safari(redirectTargetURL)
        }

        if isNodeSeekRedirector(resolvedURL) {
            return .safari(resolvedURL)
        }

        if let anchorID = normalizedAnchorID(from: resolvedURL),
           resolvedURL.path.isEmpty || resolvedURL.path == "/" {
            return .currentPageAnchor(anchorID)
        }

        let path = resolvedURL.path
        if isUserProfilePath(path) {
            return .userProfile(resolvedURL)
        }

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

    private static func isNodeSeekRedirector(_ url: URL) -> Bool {
        url.path == "/jump"
    }

    private static func decodedHTTPRedirectTarget(from url: URL) -> URL? {
        guard isNodeSeekRedirector(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawTarget = components.queryItems?.first(where: { $0.name == "to" })?.value?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              rawTarget.isEmpty == false,
              let targetURL = URL(string: rawTarget),
              isHTTPURL(targetURL) else {
            return nil
        }
        return targetURL
    }

    private static func isHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func isUserProfilePath(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 2, components[0] == "space" else { return false }
        return components[1].isEmpty == false
    }

    private static func isNodeSeekHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "nodeseek.com" || host.hasSuffix(".nodeseek.com")
    }
}

class PostDetailViewController: UIViewController {
    static let detailRenderLogger = Logger(subsystem: "com.nodeseek.app", category: "DetailRenderPipeline")

    enum DisplayMode {
        case content
        case pageSkeleton
        case skeleton
    }

    enum Layout {
        static let horizontalInset: CGFloat = PostDetailContentLayout.horizontalInset
        static let bottomContentPadding: CGFloat = 96
    }

    let presenter: PostDetailPresenterProtocol
    let baseURL = URL(string: "https://www.nodeseek.com")!
    var currentPage: Int
    var currentHeaderContent: PostDetailHeaderContent?
    var pagination: PostDetailPagination?
    var headerRenderedContent: [RenderedContentBlock]?
    var comments: [Comment] = []
    var commentRenderedCache: [String: [RenderedContentBlock]] = [:]
    var renderedCommentIDs: Set<String> = []
    var commentRenderInFlight: Set<String> = []
    var renderGeneration: Int = 0
    let sourcePostURL: URL?
    var photoBrowserPresenter: DetailPhotoBrowserPresenter?
    var attachmentLayoutRefreshWorkItem: DispatchWorkItem?
    var tableReloadWorkItem: DispatchWorkItem?
    var pendingReloadIndexPaths: Set<IndexPath> = []
    var displayMode: DisplayMode = .skeleton
    var hasRenderedDetailContent = false
    var showsReplyEntry = false
    var replyComposerMode: CommentComposerMode = .plain
    var replyContextBarHeightConstraint: NSLayoutConstraint?
    var pageLoadingTargetPage: Int?
    #if DEBUG
    var pendingScrollToRow: Int?
    #endif
    let skeletonCommentRowCount = 4
    let renderQueue = DispatchQueue(
        label: "com.nodeseek.app.postdetail.render",
        qos: .userInitiated
    )

    let tableNode = ASTableNode(style: .plain)
    var toastHideWorkItem: DispatchWorkItem?

    enum DetailRow {
        case header
        case postRepliesDivider
        case comment(Int)
        case skeletonComment(Int)
    }

    let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    let loginButton: UIButton = {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = "登录查看"
        configuration.image = UIImage(systemName: "person.crop.circle.badge.plus")
        configuration.imagePadding = 8
        configuration.baseBackgroundColor = .label
        configuration.baseForegroundColor = .systemBackground
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
        button.configuration = configuration
        button.accessibilityIdentifier = "post-detail-login-button"
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    lazy var pageScrubberView: PageScrubberView = {
        let view = PageScrubberView()
        view.onPageSelected = { [weak self] page in
            self?.pageLoadingTargetPage = page
            self?.presenter.didSelectPage(page)
        }
        return view
    }()

    let replyButton: UIButton = {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "text.bubble.fill")
        configuration.baseForegroundColor = .systemBackground
        configuration.background.backgroundColor = .clear
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 14)
        button.configuration = configuration
        button.backgroundColor = .label
        button.accessibilityIdentifier = "post-detail-reply-button"
        button.accessibilityLabel = "评论"
        button.isHidden = true
        button.layer.cornerRadius = 24
        button.layer.cornerCurve = .continuous
        button.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        button.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let replyEditorBackdrop: UIControl = {
        let control = UIControl()
        control.backgroundColor = UIColor.black.withAlphaComponent(0.08)
        control.accessibilityIdentifier = "post-detail-reply-backdrop"
        control.isHidden = true
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    let replyEditorContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 18
        view.layer.borderColor = UIColor.separator.cgColor
        view.layer.borderWidth = 1
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.12
        view.layer.shadowRadius = 16
        view.layer.shadowOffset = CGSize(width: 0, height: 8)
        view.accessibilityIdentifier = "post-detail-reply-editor"
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let replyContextBar: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 10
        view.accessibilityIdentifier = "post-detail-reply-context-bar"
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let replyContextLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.lineBreakMode = .byTruncatingTail
        label.accessibilityIdentifier = "post-detail-reply-context-label"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let replyContextCloseButton: UIButton = {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "xmark")
        configuration.baseForegroundColor = .tertiaryLabel
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        button.configuration = configuration
        button.accessibilityLabel = "取消引用"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let replyTextView: UITextView = {
        let textView = UITextView()
        textView.font = .preferredFont(forTextStyle: .body)
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 12
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        textView.accessibilityIdentifier = "post-detail-reply-text-view"
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()

    let inlineReplySendButton: UIButton = {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "arrow.up")
        configuration.baseForegroundColor = .label
        configuration.background.backgroundColor = .clear
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        button.configuration = configuration
        button.accessibilityIdentifier = "post-detail-reply-send-button"
        button.accessibilityLabel = "发送"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let toastContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.label.withAlphaComponent(0.92)
        view.layer.cornerRadius = 14
        view.layer.cornerCurve = .continuous
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.18
        view.layer.shadowRadius = 14
        view.layer.shadowOffset = CGSize(width: 0, height: 8)
        view.isHidden = true
        view.alpha = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let toastIconView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        imageView.tintColor = .systemGreen
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    let toastLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .systemBackground
        label.backgroundColor = .clear
        label.textAlignment = .natural
        label.numberOfLines = 0
        label.accessibilityIdentifier = "post-detail-toast-label"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
        toastHideWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItems()
        setupUI()
        presenter.viewDidLoad()
    }

    func configureNavigationItems() {
        let browserButton = UIBarButtonItem(
            image: UIImage(systemName: "safari"),
            style: .plain,
            target: self,
            action: #selector(openInBrowserTapped)
        )
        browserButton.accessibilityLabel = "在浏览器打开"

        var moreButton: UIBarButtonItem?
        let refreshAction = UIAction(
            title: "刷新",
            image: UIImage(systemName: "arrow.clockwise")
        ) { [weak self] _ in
            self?.refreshTapped()
        }
        let shareAction = UIAction(
            title: "分享",
            image: UIImage(systemName: "square.and.arrow.up")
        ) { [weak self] _ in
            self?.shareCurrentPost(sourceItem: moreButton)
        }

        moreButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(children: [refreshAction, shareAction])
        )
        moreButton?.accessibilityLabel = "更多"

        navigationItem.rightBarButtonItems = [moreButton, browserButton].compactMap { $0 }
    }

    func setupUI() {
        view.backgroundColor = .systemBackground
        tableNode.dataSource = self
        tableNode.delegate = self
        tableNode.view.backgroundColor = .systemBackground
        tableNode.view.separatorStyle = .none
        tableNode.view.showsVerticalScrollIndicator = true
        tableNode.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: Layout.bottomContentPadding, right: 0)
        tableNode.view.verticalScrollIndicatorInsets.bottom = Layout.bottomContentPadding
        tableNode.view.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tableNode.view)
        view.addSubview(pageScrubberView)
        view.addSubview(loadingIndicator)
        loginButton.addTarget(self, action: #selector(loginButtonTapped), for: .touchUpInside)
        view.addSubview(loginButton)
        toastContainerView.addSubview(toastIconView)
        toastContainerView.addSubview(toastLabel)
        view.addSubview(toastContainerView)
        configureDismissKeyboardGesture()
        configureReplyEditor()

        let replyEditorBottomConstraint = replyEditorContainer.bottomAnchor.constraint(
            equalTo: view.keyboardLayoutGuide.topAnchor,
            constant: -12
        )
        let replyContextBarHeightConstraint = replyContextBar.heightAnchor.constraint(equalToConstant: 0)
        self.replyContextBarHeightConstraint = replyContextBarHeightConstraint
        NSLayoutConstraint.activate([
            tableNode.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableNode.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableNode.view.topAnchor.constraint(equalTo: view.topAnchor),
            tableNode.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            pageScrubberView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: 12),
            pageScrubberView.topAnchor.constraint(equalTo: view.topAnchor),
            pageScrubberView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            loginButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loginButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18),

            toastContainerView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            toastContainerView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            toastContainerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            toastIconView.leadingAnchor.constraint(equalTo: toastContainerView.leadingAnchor, constant: 12),
            toastIconView.centerYAnchor.constraint(equalTo: toastContainerView.centerYAnchor),
            toastIconView.widthAnchor.constraint(equalToConstant: 18),
            toastIconView.heightAnchor.constraint(equalToConstant: 18),

            toastLabel.leadingAnchor.constraint(equalTo: toastIconView.trailingAnchor, constant: 8),
            toastLabel.trailingAnchor.constraint(equalTo: toastContainerView.trailingAnchor, constant: -14),
            toastLabel.topAnchor.constraint(equalTo: toastContainerView.topAnchor, constant: 10),
            toastLabel.bottomAnchor.constraint(equalTo: toastContainerView.bottomAnchor, constant: -10),

            replyButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            replyButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            replyButton.widthAnchor.constraint(equalToConstant: 56),
            replyButton.heightAnchor.constraint(equalToConstant: 48),

            replyEditorBackdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            replyEditorBackdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            replyEditorBackdrop.topAnchor.constraint(equalTo: view.topAnchor),
            replyEditorBackdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            replyEditorContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            replyEditorContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            replyEditorBottomConstraint,
            replyEditorContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 96),

            replyContextBar.leadingAnchor.constraint(equalTo: replyEditorContainer.leadingAnchor, constant: 12),
            replyContextBar.trailingAnchor.constraint(equalTo: replyEditorContainer.trailingAnchor, constant: -12),
            replyContextBar.topAnchor.constraint(equalTo: replyEditorContainer.topAnchor, constant: 12),
            replyContextBarHeightConstraint,

            replyContextLabel.leadingAnchor.constraint(equalTo: replyContextBar.leadingAnchor, constant: 10),
            replyContextLabel.trailingAnchor.constraint(equalTo: replyContextCloseButton.leadingAnchor, constant: -6),
            replyContextLabel.centerYAnchor.constraint(equalTo: replyContextBar.centerYAnchor),

            replyContextCloseButton.trailingAnchor.constraint(equalTo: replyContextBar.trailingAnchor, constant: -6),
            replyContextCloseButton.centerYAnchor.constraint(equalTo: replyContextBar.centerYAnchor),
            replyContextCloseButton.widthAnchor.constraint(equalToConstant: 24),
            replyContextCloseButton.heightAnchor.constraint(equalToConstant: 24),

            replyTextView.leadingAnchor.constraint(equalTo: replyEditorContainer.leadingAnchor, constant: 12),
            replyTextView.topAnchor.constraint(equalTo: replyContextBar.bottomAnchor, constant: 8),
            replyTextView.bottomAnchor.constraint(equalTo: replyEditorContainer.bottomAnchor, constant: -12),
            replyTextView.trailingAnchor.constraint(equalTo: inlineReplySendButton.leadingAnchor, constant: -8),
            replyTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),

            inlineReplySendButton.trailingAnchor.constraint(equalTo: replyEditorContainer.trailingAnchor, constant: -12),
            inlineReplySendButton.centerYAnchor.constraint(equalTo: replyTextView.centerYAnchor),
            inlineReplySendButton.widthAnchor.constraint(equalToConstant: 40),
            inlineReplySendButton.heightAnchor.constraint(equalToConstant: 40)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )

        reloadTableData()
        updatePageScrubber(isLoading: false)
        updateReplyButtonVisibility()
    }

    func configureReplyEditor() {
        replyButton.addTarget(self, action: #selector(replyButtonTapped), for: .touchUpInside)
        view.addSubview(replyButton)
        replyEditorBackdrop.addTarget(self, action: #selector(dismissReplyEditor), for: .touchUpInside)
        view.addSubview(replyEditorBackdrop)
        inlineReplySendButton.addTarget(self, action: #selector(sendReplyTapped), for: .touchUpInside)
        replyContextCloseButton.addTarget(self, action: #selector(clearReplyContext), for: .touchUpInside)
        replyContextBar.addSubview(replyContextLabel)
        replyContextBar.addSubview(replyContextCloseButton)
        replyEditorContainer.addSubview(replyContextBar)
        replyEditorContainer.addSubview(replyTextView)
        replyEditorContainer.addSubview(inlineReplySendButton)
        view.addSubview(replyEditorContainer)
    }

    func configureDismissKeyboardGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboardFromBackgroundTap(_:)))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
        tableNode.view.keyboardDismissMode = .onDrag
    }

    func configureHeader(_ content: PostDetailHeaderContent, renderedContent: [RenderedContentBlock]?) {
        currentHeaderContent = content
        headerRenderedContent = renderedContent
    }

    func reloadTableData() {
        tableReloadWorkItem?.cancel()
        pendingReloadIndexPaths.removeAll()
        guard isViewLoaded else { return }
        tableNode.reloadData()
    }

    #if DEBUG
    func testRowCount() -> Int {
        tableNode(tableNode, numberOfRowsInSection: 0)
    }
    #endif

    func scheduleHeaderReload() {
        guard currentHeaderContent != nil else { return }
        guard displayMode == .content else { return }
        guard let row = detailRows.firstIndex(where: { if case .header = $0 { return true }; return false }) else { return }
        scheduleRowsReload([IndexPath(row: row, section: 0)])
    }

    func scheduleCommentReload(commentID: String) {
        guard let commentIndex = comments.firstIndex(where: { $0.id == commentID }) else { return }
        guard let row = detailRows.firstIndex(where: {
            if case .comment(let index) = $0 {
                return index == commentIndex
            }
            return false
        }) else { return }
        scheduleRowsReload([IndexPath(row: row, section: 0)])
    }

    func scheduleRowsReload(_ indexPaths: [IndexPath]) {
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

    func showLoadingSkeletonIfNeeded() {
        guard hasRenderedDetailContent == false else { return }
        guard displayMode != .skeleton else { return }
        displayMode = .skeleton
        reloadTableData()
    }

    func hideLoadingSkeleton() {
        guard displayMode != .content else { return }
        displayMode = .content
        reloadTableData()
    }

    @objc
    func refreshTapped() {
        presenter.viewDidLoad()
    }

    @objc
    func loginButtonTapped() {
        presenter.didTapLogin()
    }

}
