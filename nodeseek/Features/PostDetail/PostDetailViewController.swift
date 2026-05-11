//
//  PostDetailViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit
import AsyncDisplayKit

enum PostDetailLinkDestination {
    case currentPageAnchor(String)
    case nativePost(postID: String, page: Int, url: URL)
    case userProfile(URL)
    case web(URL)
    case safari(URL)
    case externalApp(URL)
}

enum ChickenLegConfirmationContext: Equatable {
    case post
    case comment

    var title: String {
        switch self {
        case .post:
            return "给帖子投放鸡腿？"
        case .comment:
            return "给评论投放鸡腿？"
        }
    }

    var message: String {
        "将投放 1 个鸡腿，成功后会标记为已投放。"
    }
}

typealias ChickenLegConfirmationPresenter = @MainActor (
    _ viewController: UIViewController,
    _ context: ChickenLegConfirmationContext,
    _ onConfirm: @escaping @MainActor () -> Void
) -> Void

typealias PasteboardStringWriter = @MainActor (String) -> Void

enum PostDetailReplySendButtonStyle {
    static let foregroundColor = UIColor.systemBackground
    static let backgroundColor = UIColor.label
    static let font = UIFont.systemFont(ofSize: 13, weight: .semibold)
    static let titleAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var outgoing = incoming
        outgoing.font = font
        return outgoing
    }
    static let activityIndicatorColorTransformer = UIConfigurationColorTransformer { _ in
        foregroundColor
    }
}

enum PostDetailLinkResolver {
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
            return isHTTPURL(resolvedURL) ? .safari(resolvedURL) : .externalApp(resolvedURL)
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

        if let route = NodeSeekPostRouteResolver.route(for: resolvedURL, baseURL: baseURL) {
            if let anchorID = route.anchorID,
               route.postID == currentPostID,
               route.page == max(currentPage, 1) {
                return .currentPageAnchor(anchorID)
            }
            // TODO: 支持当前帖子跨页锚点在目标页加载完成后自动定位。
            return .nativePost(postID: route.postID, page: route.page, url: route.url)
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
        NodeSeekSite.isNodeSeekHost(url)
    }
}

class PostDetailViewController: UIViewController {
    enum DisplayMode {
        case content
        case pageSkeleton
        case skeleton
    }

    enum Layout {
        static let horizontalInset: CGFloat = PostDetailContentLayout.horizontalInset
        static let replyButtonBottomInset: CGFloat = 204
    }

    let presenter: PostDetailPresenterProtocol
    let baseURL = NodeSeekSite.baseURL
    var currentPage: Int
    let initialPage: Int
    let wasOpenedFromInitialAnchor: Bool
    var currentHeaderContent: PostDetailHeaderContent?
    var pagination: PostDetailPagination?
    var headerRenderedContent: [RenderedContentBlock]?
    var comments: [Comment] = []
    var loadedCommentPageRanges: [Int: Range<Int>] = [:]
    var commentRenderedCache: [String: [RenderedContentBlock]] = [:]
    var renderedCommentIDs: Set<String> = []
    var commentRenderInFlight: Set<String> = []
    var detailImageSizeCache: [URL: CGSize] = [:]
    var renderGeneration: Int = 0
    let sourcePostURL: URL?
    var photoBrowserPresenter: DetailPhotoBrowserPresenter?
    var attachmentLayoutRefreshWorkItem: DispatchWorkItem?
    var tableReloadWorkItem: DispatchWorkItem?
    var initialContentRevealWorkItem: DispatchWorkItem?
    var pendingInitialContentRevealGeneration: Int?
    var pendingInitialAnchorID: String?
    var pendingReloadIndexPaths: Set<IndexPath> = []
    var displayMode: DisplayMode = .skeleton
    var hasRenderedDetailContent = false
    var showsReplyEntry = false
    let stickerCookieSession = NodeSeekCookieSession()
    var replyComposerMode: CommentComposerMode = .plain
    var replyContextBarHeightConstraint: NSLayoutConstraint?
    var replyStickerPickerHeightConstraint: NSLayoutConstraint?
    let leadingScreensForBatching: CGFloat = 2.0
    var lastBatchFetchRequestedCommentCount: Int?
    var chickenLegConfirmationPresenter: ChickenLegConfirmationPresenter = { viewController, context, onConfirm in
        let alert = UIAlertController(
            title: context.title,
            message: context.message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "投放 1 个", style: .default) { _ in
            Task { @MainActor in
                onConfirm()
            }
        })
        viewController.present(alert, animated: true)
    }
    #if DEBUG
    var pendingScrollToRow: Int?
    var testVisibleAnchorIDs: Set<String>?
    var testPresentedLoadedCommentID: String?
    var testHighlightedAnchorID: String?
    var testPresentedPreviewUsesCommentCellRendering = false
    var testPresentedPreviewPreferredHeight: CGFloat?
    var testPresentedPreviewKeepsCloseButtonOutsideContent = false
    var testPresentedPreviewUsesBottomSheet = false
    var testPresentedPreviewShowsFullPostButton = false
    var testOpenedFullPostPage: Int?
    var testOpenedFullPostAnchorWasNil = false
    #endif
    let skeletonCommentRowCount = 4
    let accountRefresher: any CurrentAccountRefreshing
    let nodeImageAPIKeyStore: NodeImageAPIKeyStoring
    let nodeImageUploadClient: NodeImageUploading
    let pasteboardStringWriter: PasteboardStringWriter
    var imageUploadTask: Task<Void, Never>?
    let renderQueue = DispatchQueue(
        label: "com.nodeseek.app.postdetail.render",
        qos: .userInitiated
    )
    let initialContentRevealTimeout: TimeInterval = 0.6

    let tableNode = ASTableNode(style: .plain)
    var toastHideWorkItem: DispatchWorkItem?
    let navigationAuthorTitleView = PostDetailNavigationAuthorTitleView()
    var isNavigationAuthorTitleVisible = false

    enum DetailRow {
        case header
        case entryHint
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

    let loadMoreCommentsIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    let loadMoreCommentsRefreshButton: UIButton = {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.title = "点击加载新评论"
        configuration.baseForegroundColor = .secondaryLabel
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        button.configuration = configuration
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "post-detail-refresh-comments-at-end-button"
        return button
    }()

    lazy var loadMoreCommentsContainer: UIView = {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 56))
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(separator)
        container.addSubview(loadMoreCommentsIndicator)
        container.addSubview(loadMoreCommentsRefreshButton)
        let separatorHeight = 1.0 / UIScreen.main.scale
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.topAnchor.constraint(equalTo: container.topAnchor),
            separator.heightAnchor.constraint(equalToConstant: separatorHeight),
            loadMoreCommentsIndicator.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            loadMoreCommentsIndicator.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            loadMoreCommentsRefreshButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            loadMoreCommentsRefreshButton.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
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

    private let replyButtonAnchorView: UIView = {
        let view = UIView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let floatingReplyButtonContainer: FloatingControlContainerView

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

    let replyContextStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = 2
        stackView.accessibilityIdentifier = "post-detail-reply-context-stack"
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    let replyContextScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = false
        scrollView.accessibilityIdentifier = "post-detail-reply-context-scroll-view"
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    let replyContextBarMaximumHeight: CGFloat = 86

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

    let replyToolbarView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = 8
        stackView.accessibilityIdentifier = "post-detail-reply-toolbar"
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    let replyToolbarSpacer = UIView()

    let replyImageUploadButton: UIButton = {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "photo")
        configuration.baseForegroundColor = .label
        configuration.background.backgroundColor = .clear
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        button.configuration = configuration
        button.accessibilityIdentifier = "post-detail-reply-image-upload-button"
        button.accessibilityLabel = "上传图片"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let inlineReplySendButton: UIButton = {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = "发送"
        configuration.baseForegroundColor = PostDetailReplySendButtonStyle.foregroundColor
        configuration.background.backgroundColor = PostDetailReplySendButtonStyle.backgroundColor
        configuration.background.cornerRadius = 8
        configuration.titleTextAttributesTransformer = PostDetailReplySendButtonStyle.titleAttributesTransformer
        configuration.activityIndicatorColorTransformer = PostDetailReplySendButtonStyle.activityIndicatorColorTransformer
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        button.configuration = configuration
        button.titleLabel?.numberOfLines = 1
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.9
        button.layer.cornerRadius = 8
        button.clipsToBounds = true
        button.accessibilityIdentifier = "post-detail-reply-send-button"
        button.accessibilityLabel = "发送"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let replyStickerButton: UIButton = {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "face.smiling")
        configuration.baseForegroundColor = .label
        configuration.background.backgroundColor = .clear
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        button.configuration = configuration
        button.accessibilityIdentifier = "post-detail-reply-sticker-button"
        button.accessibilityLabel = "表情"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let replyStickerPickerView = NodeSeekStickerPickerView()

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
        currentPage: Int = 1,
        initialAnchorID: String? = nil,
        accountRefresher: (any CurrentAccountRefreshing)? = nil,
        nodeImageAPIKeyStore: NodeImageAPIKeyStoring = KeychainNodeImageAPIKeyStore(),
        nodeImageUploadClient: NodeImageUploading = NodeImageUploadClient(),
        floatingPositionStore: FloatingControlPositionStoring = UserDefaultsFloatingControlPositionStore(),
        pasteboardStringWriter: @escaping PasteboardStringWriter = { UIPasteboard.general.string = $0 }
    ) {
        self.presenter = presenter
        self.sourcePostURL = sourcePostURL
        let normalizedInitialPage = max(currentPage, 1)
        self.currentPage = normalizedInitialPage
        self.initialPage = normalizedInitialPage
        self.pendingInitialAnchorID = initialAnchorID
        self.wasOpenedFromInitialAnchor = initialAnchorID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        self.accountRefresher = accountRefresher ?? CurrentAccountRefresher.shared
        self.nodeImageAPIKeyStore = nodeImageAPIKeyStore
        self.nodeImageUploadClient = nodeImageUploadClient
        self.floatingReplyButtonContainer = FloatingControlContainerView(
            accessibilityIdentifier: "post-detail-floating-reply-button",
            positionStorageKey: FloatingControlPositionKeys.postDetailReplyButton,
            positionStore: floatingPositionStore
        )
        self.pasteboardStringWriter = pasteboardStringWriter
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
        imageUploadTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItems()
        setupUI()
        presenter.viewDidLoad()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateTableContentInsets()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        floatingReplyButtonContainer.updateFloatingEdgeInsets(
            in: view,
            horizontalAnchorView: replyButtonAnchorView
        )
        floatingReplyButtonContainer.syncFrame(with: replyButtonAnchorView)
    }

    func configureNavigationItems() {
        title = nil
        navigationItem.titleView = navigationAuthorTitleView
        navigationAuthorTitleView.setVisible(false, animated: false)
        if let currentHeaderContent {
            configureNavigationAuthorTitle(with: currentHeaderContent)
        }

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
        let copyLinkAction = UIAction(
            title: "复制链接",
            image: UIImage(systemName: "link")
        ) { [weak self] _ in
            self?.copyCurrentPostLink()
        }

        moreButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(children: [refreshAction, copyLinkAction, shareAction])
        )
        moreButton?.accessibilityLabel = "更多"

        navigationItem.rightBarButtonItems = [moreButton, browserButton].compactMap { $0 }
    }

    func updateTableContentInsets() {
        let bottomInset = view.safeAreaInsets.bottom
        tableNode.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        tableNode.view.verticalScrollIndicatorInsets.bottom = bottomInset
    }

    func setupUI() {
        view.backgroundColor = .systemBackground
        tableNode.dataSource = self
        tableNode.delegate = self
        tableNode.leadingScreensForBatching = leadingScreensForBatching
        tableNode.view.backgroundColor = .systemBackground
        tableNode.view.separatorStyle = .none
        tableNode.view.showsVerticalScrollIndicator = true
        tableNode.view.tableFooterView = loadMoreCommentsContainer
        updateTableContentInsets()
        tableNode.view.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tableNode.view)
        view.addSubview(loadingIndicator)
        loginButton.addTarget(self, action: #selector(loginButtonTapped), for: .touchUpInside)
        loadMoreCommentsRefreshButton.addTarget(self, action: #selector(refreshCommentsAtEndTapped), for: .touchUpInside)
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
        let replyStickerPickerHeightConstraint = replyStickerPickerView.heightAnchor.constraint(equalToConstant: 0)
        self.replyContextBarHeightConstraint = replyContextBarHeightConstraint
        self.replyStickerPickerHeightConstraint = replyStickerPickerHeightConstraint
        NSLayoutConstraint.activate([
            tableNode.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableNode.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableNode.view.topAnchor.constraint(equalTo: view.topAnchor),
            tableNode.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

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

            replyButtonAnchorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            replyButtonAnchorView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Layout.replyButtonBottomInset),
            replyButtonAnchorView.widthAnchor.constraint(equalToConstant: 56),
            replyButtonAnchorView.heightAnchor.constraint(equalToConstant: 48),

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

            replyContextScrollView.leadingAnchor.constraint(equalTo: replyContextBar.leadingAnchor, constant: 10),
            replyContextScrollView.trailingAnchor.constraint(equalTo: replyContextBar.trailingAnchor, constant: -6),
            replyContextScrollView.topAnchor.constraint(equalTo: replyContextBar.topAnchor, constant: 4),
            replyContextScrollView.bottomAnchor.constraint(equalTo: replyContextBar.bottomAnchor, constant: -4),

            replyContextStackView.leadingAnchor.constraint(equalTo: replyContextScrollView.contentLayoutGuide.leadingAnchor),
            replyContextStackView.trailingAnchor.constraint(equalTo: replyContextScrollView.contentLayoutGuide.trailingAnchor),
            replyContextStackView.topAnchor.constraint(equalTo: replyContextScrollView.contentLayoutGuide.topAnchor),
            replyContextStackView.bottomAnchor.constraint(equalTo: replyContextScrollView.contentLayoutGuide.bottomAnchor),
            replyContextStackView.widthAnchor.constraint(equalTo: replyContextScrollView.frameLayoutGuide.widthAnchor),

            replyTextView.leadingAnchor.constraint(equalTo: replyEditorContainer.leadingAnchor, constant: 12),
            replyTextView.topAnchor.constraint(equalTo: replyToolbarView.bottomAnchor, constant: 8),
            replyTextView.trailingAnchor.constraint(equalTo: replyEditorContainer.trailingAnchor, constant: -12),
            replyTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 88),

            replyToolbarView.leadingAnchor.constraint(equalTo: replyEditorContainer.leadingAnchor, constant: 12),
            replyToolbarView.trailingAnchor.constraint(equalTo: replyEditorContainer.trailingAnchor, constant: -12),
            replyToolbarView.topAnchor.constraint(equalTo: replyContextBar.bottomAnchor, constant: 8),
            replyToolbarView.heightAnchor.constraint(equalToConstant: 36),

            replyImageUploadButton.widthAnchor.constraint(equalToConstant: 36),
            replyImageUploadButton.heightAnchor.constraint(equalToConstant: 36),

            replyStickerButton.widthAnchor.constraint(equalToConstant: 36),
            replyStickerButton.heightAnchor.constraint(equalToConstant: 36),

            inlineReplySendButton.widthAnchor.constraint(equalToConstant: 64),
            inlineReplySendButton.heightAnchor.constraint(equalToConstant: 36),

            replyStickerPickerView.leadingAnchor.constraint(equalTo: replyEditorContainer.leadingAnchor, constant: 12),
            replyStickerPickerView.trailingAnchor.constraint(equalTo: replyEditorContainer.trailingAnchor, constant: -12),
            replyStickerPickerView.topAnchor.constraint(equalTo: replyTextView.bottomAnchor, constant: 10),
            replyStickerPickerView.bottomAnchor.constraint(equalTo: replyEditorContainer.bottomAnchor, constant: -12),
            replyStickerPickerHeightConstraint
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appTextSizeDidChange(_:)),
            name: AppTextSizeSettings.didChangeNotification,
            object: nil
        )

        reloadTableData()
        updateReplyButtonVisibility()
    }

    @objc
    func refreshCommentsAtEndTapped() {
        AppLog.info(.postDetail, "点击详情评论到底 footer 更新按钮: currentPage=\(currentPage), totalComments=\(comments.count)")
        presenter.didTapRefreshCommentsAtEnd()
    }

    @objc
    func appTextSizeDidChange(_ notification: Notification) {
        renderGeneration += 1
        commentRenderInFlight.removeAll(keepingCapacity: true)
        commentRenderedCache.removeAll(keepingCapacity: true)
        renderedCommentIDs.removeAll(keepingCapacity: true)
        if let currentHeaderContent {
            headerRenderedContent = nil
            scheduleHeaderRender(for: currentHeaderContent)
        }
        reloadTableData()
        preheatCommentRender(for: comments)
    }

    func configureReplyEditor() {
        replyButton.addTarget(self, action: #selector(replyButtonTapped), for: .touchUpInside)
        floatingReplyButtonContainer.onAdsorbedEdgeChanged = { [weak self] edge in
            self?.replyButton.applyFloatingDockedCorners(for: edge)
        }
        floatingReplyButtonContainer.hostControl(replyButton)
        view.addSubview(replyButtonAnchorView)
        view.addSubview(floatingReplyButtonContainer)
        replyEditorBackdrop.addTarget(self, action: #selector(dismissReplyEditor), for: .touchUpInside)
        view.addSubview(replyEditorBackdrop)
        inlineReplySendButton.addTarget(self, action: #selector(sendReplyTapped), for: .touchUpInside)
        replyStickerButton.addTarget(self, action: #selector(toggleStickerPicker), for: .touchUpInside)
        replyImageUploadButton.addTarget(self, action: #selector(uploadImageTapped), for: .touchUpInside)
        replyStickerPickerView.onSelectSticker = { [weak self] item in
            self?.insertStickerToken(item.token)
        }
        replyContextBar.addSubview(replyContextScrollView)
        replyContextScrollView.addSubview(replyContextStackView)
        replyToolbarSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        replyToolbarView.addArrangedSubview(replyImageUploadButton)
        replyToolbarView.addArrangedSubview(replyStickerButton)
        replyToolbarView.addArrangedSubview(replyToolbarSpacer)
        replyToolbarView.addArrangedSubview(inlineReplySendButton)
        replyEditorContainer.addSubview(replyContextBar)
        replyEditorContainer.addSubview(replyToolbarView)
        replyEditorContainer.addSubview(replyTextView)
        replyEditorContainer.addSubview(replyStickerPickerView)
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
        configureNavigationAuthorTitle(with: content)
        updateNavigationAuthorVisibility(contentOffsetY: tableNode.contentOffset.y, animated: false)
    }

    func configureNavigationAuthorTitle(with content: PostDetailHeaderContent) {
        navigationAuthorTitleView.configure(
            postID: content.postID,
            authorName: content.authorName,
            avatarURL: content.avatarURL
        )
    }

    func updateNavigationAuthorVisibility(contentOffsetY: CGFloat, animated: Bool = false) {
        guard AuthorDisplayPolicy.isDisplayable(currentHeaderContent?.authorName ?? "") else {
            setNavigationAuthorTitleVisible(false, animated: animated)
            return
        }

        let showThreshold: CGFloat = 72
        let hideThreshold: CGFloat = 24
        let shouldShow = isNavigationAuthorTitleVisible
            ? contentOffsetY > hideThreshold
            : contentOffsetY > showThreshold
        setNavigationAuthorTitleVisible(shouldShow, animated: animated)
    }

    private func setNavigationAuthorTitleVisible(_ isVisible: Bool, animated: Bool) {
        guard isNavigationAuthorTitleVisible != isVisible else { return }
        isNavigationAuthorTitleVisible = isVisible
        navigationAuthorTitleView.setVisible(isVisible, animated: animated)
    }

    func reloadTableData() {
        tableReloadWorkItem?.cancel()
        pendingReloadIndexPaths.removeAll()
        guard isViewLoaded else { return }
        tableNode.reloadData()
    }

    func cachedDetailImageSize(for url: URL) -> CGSize? {
        guard let resolvedURL = ImageURLResolver.resolve(url),
              let size = detailImageSizeCache[resolvedURL],
              size.width > 0,
              size.height > 0 else {
            return nil
        }
        return size
    }

    func cacheDetailImageSize(_ size: CGSize, for url: URL) {
        guard size.width > 0,
              size.height > 0,
              let resolvedURL = ImageURLResolver.resolve(url) else {
            return
        }
        detailImageSizeCache[resolvedURL] = size
    }

    #if DEBUG
    func testRowCount() -> Int {
        tableNode(tableNode, numberOfRowsInSection: 0)
    }

    var testPendingInitialAnchorID: String? {
        pendingInitialAnchorID
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
        presenter.refreshInitialPage()
    }

    @objc
    func loginButtonTapped() {
        presenter.didTapLogin()
    }

}
