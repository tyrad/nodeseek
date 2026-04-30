//
//  PostDetailViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit
import AsyncDisplayKit
import DTCoreText
import Kingfisher
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

        if let jumpURL = decodedExternalJumpURL(from: resolvedURL) {
            return .safari(jumpURL)
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

    private static func decodedExternalJumpURL(from url: URL) -> URL? {
        guard url.path == "/jump",
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

    private static func isNodeSeekHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "nodeseek.com" || host.hasSuffix(".nodeseek.com")
    }
}

class PostDetailViewController: UIViewController {
    private static let detailRenderLogger = Logger(subsystem: "com.nodeseek.app", category: "DetailRenderPipeline")

    private enum DisplayMode {
        case content
        case pageSkeleton
        case skeleton
    }

    private enum Layout {
        static let horizontalInset: CGFloat = PostDetailContentLayout.horizontalInset
        static let composerHorizontalInset: CGFloat = 12
        static let composerVerticalInset: CGFloat = 6
        static let composerTargetSpacing: CGFloat = 6
        static let composerTextHorizontalInset: CGFloat = 10
        static let composerTextVerticalInset: CGFloat = 12
        static let composerMinLines: CGFloat = 1
        static let composerMaxLines: CGFloat = 6
        static let composerDeferredHeightRefreshDelay: TimeInterval = 0.08
        static let sendButtonWidth: CGFloat = 40
        static let sendButtonHeight: CGFloat = 34
    }

    private let presenter: PostDetailPresenterProtocol
    private let baseURL = URL(string: "https://www.nodeseek.com")!
    private var currentPage: Int
    private var currentHeaderContent: PostDetailHeaderContent?
    private var pagination: PostDetailPagination?
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
    private var pageLoadingTargetPage: Int?
    #if DEBUG
    private var pendingScrollToRow: Int?
    #endif
    private var composerMode: CommentComposerMode = .plain
    private var isCommentSubmitting = false
    private var isKeyboardVisible = false
    private let skeletonCommentRowCount = 4
    private let renderQueue = DispatchQueue(
        label: "com.nodeseek.app.postdetail.render",
        qos: .userInitiated
    )

    private let tableNode = ASTableNode(style: .plain)
    private var composerBottomConstraint: NSLayoutConstraint?
    private var commentTextViewHeightConstraint: NSLayoutConstraint?
    private var commentTextViewTopToComposerConstraint: NSLayoutConstraint?
    private var commentTextViewTopToTargetConstraint: NSLayoutConstraint?
    private var sendCommentButtonSpacingConstraint: NSLayoutConstraint?
    private var sendCommentButtonWidthConstraint: NSLayoutConstraint?
    private var toastHideWorkItem: DispatchWorkItem?
    private var commentTextViewHeightRefreshWorkItem: DispatchWorkItem?

    private enum DetailRow {
        case header
        case postRepliesDivider
        case comment(Int)
        case skeletonComment(Int)
    }

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let loginButton: UIButton = {
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

    private lazy var pageScrubberView: PageScrubberView = {
        let view = PageScrubberView()
        view.onPageSelected = { [weak self] page in
            self?.pageLoadingTargetPage = page
            self?.presenter.didSelectPage(page)
        }
        return view
    }()

    private let composerContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.borderWidth = 0.5
        view.layer.borderColor = UIColor.separator.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let targetContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 8
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let targetLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.accessibilityIdentifier = "post-detail-comment-target-label"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let targetCancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        button.tintColor = .tertiaryLabel
        button.accessibilityIdentifier = "post-detail-comment-target-cancel-button"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let commentTextView: UITextView = {
        let textView = UITextView()
        textView.font = .preferredFont(forTextStyle: .body)
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 12
        textView.layer.cornerCurve = .continuous
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(
            top: Layout.composerTextVerticalInset,
            left: Layout.composerTextHorizontalInset,
            bottom: Layout.composerTextVerticalInset,
            right: Layout.composerTextHorizontalInset
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.accessibilityIdentifier = "post-detail-comment-input"
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()

    private let commentPlaceholderLabel: UILabel = {
        let label = UILabel()
        label.text = "写下你的评论..."
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .tertiaryLabel
        label.accessibilityIdentifier = "post-detail-comment-placeholder-label"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let sendCommentButton: UIButton = {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "paperplane.fill")
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        button.configuration = configuration
        button.accessibilityIdentifier = "post-detail-comment-send-button"
        button.accessibilityLabel = "发送评论"
        button.isHidden = true
        button.isEnabled = false
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let toastContainerView: UIView = {
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

    private let toastIconView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        imageView.tintColor = .systemGreen
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let toastLabel: UILabel = {
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
        commentTextViewHeightRefreshWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItems()
        setupUI()
        presenter.viewDidLoad()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCommentTextViewHeight(animated: false)
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
        view.addSubview(pageScrubberView)
        view.addSubview(composerContainerView)
        view.addSubview(loadingIndicator)
        loginButton.addTarget(self, action: #selector(loginButtonTapped), for: .touchUpInside)
        view.addSubview(loginButton)
        toastContainerView.addSubview(toastIconView)
        toastContainerView.addSubview(toastLabel)
        view.addSubview(toastContainerView)
        configureComposer()
        configureDismissKeyboardGesture()

        composerBottomConstraint = composerContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        NSLayoutConstraint.activate([
            tableNode.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableNode.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableNode.view.topAnchor.constraint(equalTo: view.topAnchor),
            tableNode.view.bottomAnchor.constraint(equalTo: composerContainerView.topAnchor),

            composerContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            composerContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            composerBottomConstraint!,

            pageScrubberView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: 12),
            pageScrubberView.topAnchor.constraint(equalTo: view.topAnchor),
            pageScrubberView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            loginButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loginButton.bottomAnchor.constraint(equalTo: composerContainerView.topAnchor, constant: -18),

            toastContainerView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            toastContainerView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            toastContainerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastContainerView.bottomAnchor.constraint(equalTo: composerContainerView.topAnchor, constant: -12),

            toastIconView.leadingAnchor.constraint(equalTo: toastContainerView.leadingAnchor, constant: 12),
            toastIconView.centerYAnchor.constraint(equalTo: toastContainerView.centerYAnchor),
            toastIconView.widthAnchor.constraint(equalToConstant: 18),
            toastIconView.heightAnchor.constraint(equalToConstant: 18),

            toastLabel.leadingAnchor.constraint(equalTo: toastIconView.trailingAnchor, constant: 8),
            toastLabel.trailingAnchor.constraint(equalTo: toastContainerView.trailingAnchor, constant: -14),
            toastLabel.topAnchor.constraint(equalTo: toastContainerView.topAnchor, constant: 10),
            toastLabel.bottomAnchor.constraint(equalTo: toastContainerView.bottomAnchor, constant: -10)
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
    }

    private func configureComposer() {
        commentTextView.delegate = self
        sendCommentButton.addTarget(self, action: #selector(sendCommentTapped), for: .touchUpInside)
        targetCancelButton.addTarget(self, action: #selector(cancelReplyTargetTapped), for: .touchUpInside)

        commentTextView.addSubview(commentPlaceholderLabel)
        targetContainerView.addSubview(targetLabel)
        targetContainerView.addSubview(targetCancelButton)
        composerContainerView.addSubview(targetContainerView)
        composerContainerView.addSubview(commentTextView)
        composerContainerView.addSubview(sendCommentButton)

        commentTextViewHeightConstraint = commentTextView.heightAnchor.constraint(equalToConstant: preferredCommentTextViewHeight())
        commentTextViewHeightConstraint?.priority = .required
        commentTextViewTopToComposerConstraint = commentTextView.topAnchor.constraint(
            equalTo: composerContainerView.topAnchor,
            constant: Layout.composerVerticalInset
        )
        commentTextViewTopToTargetConstraint = commentTextView.topAnchor.constraint(
            equalTo: targetContainerView.bottomAnchor,
            constant: Layout.composerTargetSpacing
        )
        sendCommentButtonSpacingConstraint = sendCommentButton.leadingAnchor.constraint(
            equalTo: commentTextView.trailingAnchor,
            constant: 0
        )
        sendCommentButtonWidthConstraint = sendCommentButton.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            targetContainerView.leadingAnchor.constraint(equalTo: composerContainerView.leadingAnchor, constant: Layout.composerHorizontalInset),
            targetContainerView.trailingAnchor.constraint(equalTo: composerContainerView.trailingAnchor, constant: -Layout.composerHorizontalInset),
            targetContainerView.topAnchor.constraint(equalTo: composerContainerView.topAnchor, constant: Layout.composerVerticalInset),

            targetLabel.leadingAnchor.constraint(equalTo: targetContainerView.leadingAnchor, constant: 10),
            targetLabel.topAnchor.constraint(equalTo: targetContainerView.topAnchor, constant: 7),
            targetLabel.bottomAnchor.constraint(equalTo: targetContainerView.bottomAnchor, constant: -7),

            targetCancelButton.leadingAnchor.constraint(equalTo: targetLabel.trailingAnchor, constant: 8),
            targetCancelButton.trailingAnchor.constraint(equalTo: targetContainerView.trailingAnchor, constant: -8),
            targetCancelButton.centerYAnchor.constraint(equalTo: targetContainerView.centerYAnchor),
            targetCancelButton.widthAnchor.constraint(equalToConstant: 24),
            targetCancelButton.heightAnchor.constraint(equalToConstant: 24),

            commentTextView.leadingAnchor.constraint(equalTo: composerContainerView.leadingAnchor, constant: Layout.composerHorizontalInset),
            commentTextViewTopToComposerConstraint!,
            commentTextView.bottomAnchor.constraint(equalTo: composerContainerView.bottomAnchor, constant: -Layout.composerVerticalInset),
            commentTextViewHeightConstraint!,

            commentPlaceholderLabel.leadingAnchor.constraint(
                equalTo: commentTextView.leadingAnchor,
                constant: commentTextView.textContainerInset.left
            ),
            commentPlaceholderLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: commentTextView.trailingAnchor,
                constant: -commentTextView.textContainerInset.right
            ),
            commentPlaceholderLabel.topAnchor.constraint(
                equalTo: commentTextView.topAnchor,
                constant: commentTextView.textContainerInset.top
            ),

            sendCommentButtonSpacingConstraint!,
            sendCommentButton.trailingAnchor.constraint(equalTo: composerContainerView.trailingAnchor, constant: -Layout.composerHorizontalInset),
            sendCommentButton.centerYAnchor.constraint(equalTo: commentTextView.centerYAnchor),
            sendCommentButtonWidthConstraint!,
            sendCommentButton.heightAnchor.constraint(equalToConstant: Layout.sendButtonHeight)
        ])

        updateCommentPlaceholderVisibility()
    }

    private func configureDismissKeyboardGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboardFromBackgroundTap(_:)))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
        tableNode.view.keyboardDismissMode = .onDrag
    }

    private func preferredCommentTextViewHeight() -> CGFloat {
        let minimumHeight = commentTextViewHeight(forLineCount: Layout.composerMinLines)
        let maximumHeight = commentTextViewHeight(forLineCount: Layout.composerMaxLines)

        guard commentTextView.text.isEmpty == false else {
            return minimumHeight
        }

        let width = commentTextView.bounds.width > 0
            ? commentTextView.bounds.width
            : view.bounds.width - Layout.composerHorizontalInset * 2 - 44 - 8
        let fittingSize = CGSize(width: max(width, 1), height: .greatestFiniteMagnitude)
        let measuredHeight = commentTextView.sizeThatFits(fittingSize).height
        return min(max(measuredHeight, minimumHeight), maximumHeight)
    }

    private func commentTextViewHeight(forLineCount lineCount: CGFloat) -> CGFloat {
        let lineHeight = commentTextView.font?.lineHeight ?? UIFont.preferredFont(forTextStyle: .body).lineHeight
        let insetHeight = commentTextView.textContainerInset.top + commentTextView.textContainerInset.bottom
        return lineHeight * lineCount + insetHeight
    }

    private func updateCommentTextViewHeight(animated: Bool = true) {
        guard let commentTextViewHeightConstraint else { return }
        let newHeight = preferredCommentTextViewHeight()
        let maximumHeight = commentTextViewHeight(forLineCount: Layout.composerMaxLines)
        commentTextView.isScrollEnabled = newHeight >= maximumHeight - 0.5
        guard abs(commentTextViewHeightConstraint.constant - newHeight) > 0.5 else { return }

        commentTextViewHeightConstraint.constant = newHeight

        guard animated, view.window != nil else {
            view.layoutIfNeeded()
            return
        }

        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.view.layoutIfNeeded()
        }
    }

    private func scheduleDeferredCommentTextViewHeightRefresh(animated: Bool = true) {
        commentTextViewHeightRefreshWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.commentTextView.setNeedsLayout()
            self.commentTextView.layoutIfNeeded()
            self.updateCommentTextViewHeight(animated: animated)
        }
        commentTextViewHeightRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Layout.composerDeferredHeightRefreshDelay,
            execute: workItem
        )
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

    #if DEBUG
    func testRowCount() -> Int {
        tableNode(tableNode, numberOfRowsInSection: 0)
    }
    #endif

    private func scheduleHeaderReload() {
        guard currentHeaderContent != nil else { return }
        guard displayMode == .content else { return }
        guard let row = detailRows.firstIndex(where: { if case .header = $0 { return true }; return false }) else { return }
        scheduleRowsReload([IndexPath(row: row, section: 0)])
    }

    private func scheduleCommentReload(commentID: String) {
        guard let commentIndex = comments.firstIndex(where: { $0.id == commentID }) else { return }
        guard let row = detailRows.firstIndex(where: {
            if case .comment(let index) = $0 {
                return index == commentIndex
            }
            return false
        }) else { return }
        scheduleRowsReload([IndexPath(row: row, section: 0)])
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
        guard displayMode != .content else { return }
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
    private func loginButtonTapped() {
        presenter.didTapLogin()
    }

    @objc
    private func sendCommentTapped() {
        let content = resolvedCommentContent()
        presenter.didSubmitComment(content: content)
    }

    @objc
    private func cancelReplyTargetTapped() {
        composerMode = .plain
        updateComposerTarget()
    }

    @objc
    private func dismissKeyboardFromBackgroundTap(_ recognizer: UITapGestureRecognizer) {
        view.endEditing(true)
    }

    @objc
    private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let convertedFrame = view.convert(frame, from: nil)
        let overlap = max(view.bounds.maxY - convertedFrame.minY - view.safeAreaInsets.bottom, 0)
        isKeyboardVisible = overlap > 0
        composerBottomConstraint?.constant = -overlap
        updateSendButtonVisibility()
        animateComposer(with: notification)
    }

    @objc
    private func keyboardWillHide(_ notification: Notification) {
        isKeyboardVisible = false
        composerBottomConstraint?.constant = 0
        updateSendButtonVisibility()
        animateComposer(with: notification)
    }

    private func animateComposer(with notification: Notification) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    private func resolvedCommentContent() -> String {
        CommentComposerContentBuilder.content(
            text: commentTextView.text,
            mode: composerMode,
            postURL: resolvedDetailURL() ?? baseURL
        )
    }

    private func updateComposerTarget() {
        switch composerMode {
        case .plain:
            targetContainerView.isHidden = true
            targetLabel.isHidden = true
            targetLabel.text = nil
            commentTextViewTopToTargetConstraint?.isActive = false
            commentTextViewTopToComposerConstraint?.isActive = true
        case .reply(let comment), .quote(let comment):
            targetContainerView.isHidden = false
            targetLabel.isHidden = false
            targetLabel.text = "回复 @\(comment.authorName) \(comment.floorText ?? "#\(comment.anchorID ?? comment.id)")"
            commentTextViewTopToComposerConstraint?.isActive = false
            commentTextViewTopToTargetConstraint?.isActive = true
        }
        updateCommentTextViewHeight(animated: true)
    }

    private func setCommentComposerText(_ text: String, animated: Bool) {
        commentTextView.text = text
        updateCommentPlaceholderVisibility()
        updateSendButtonState()
        updateCommentTextViewHeight(animated: animated)
        scheduleDeferredCommentTextViewHeightRefresh(animated: animated)
    }

    func handleReply(to comment: Comment) {
        composerMode = .reply(comment)
        updateComposerTarget()
        commentTextView.becomeFirstResponder()
    }

    func handleQuote(_ comment: Comment) {
        composerMode = .plain
        updateComposerTarget()
        let quoteText = CommentComposerContentBuilder.content(
            text: "",
            mode: .quote(comment),
            postURL: resolvedDetailURL() ?? baseURL
        )
        setCommentComposerText(quoteText, animated: false)
        commentTextView.becomeFirstResponder()
    }

    private func updateSendButtonVisibility() {
        sendCommentButton.isHidden = isKeyboardVisible == false
        sendCommentButtonSpacingConstraint?.constant = isKeyboardVisible ? 8 : 0
        sendCommentButtonWidthConstraint?.constant = isKeyboardVisible ? Layout.sendButtonWidth : 0
        updateSendButtonState()
    }

    private func updateCommentPlaceholderVisibility() {
        commentPlaceholderLabel.isHidden = commentTextView.text.isEmpty == false
    }

    #if DEBUG
    func simulateKeyboardVisibleForTesting() {
        if view.bounds.height <= 0 || view.bounds.width <= 0 {
            view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            view.layoutIfNeeded()
        }
        let keyboardHeight: CGFloat = 300
        let frame = CGRect(
            x: 0,
            y: view.bounds.maxY - keyboardHeight,
            width: max(view.bounds.width, 390),
            height: keyboardHeight
        )
        keyboardWillChangeFrame(Notification(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: frame,
                UIResponder.keyboardAnimationDurationUserInfoKey: 0
            ]
        ))
    }

    func simulateKeyboardHiddenForTesting() {
        keyboardWillHide(Notification(
            name: UIResponder.keyboardWillHideNotification,
            object: nil,
            userInfo: [UIResponder.keyboardAnimationDurationUserInfoKey: 0]
        ))
    }
    #endif

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
        guard let indexPath = indexPathForCurrentPageAnchor(anchorID) else { return }

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

    private func indexPathForCurrentPageAnchor(_ anchorID: String) -> IndexPath? {
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

    private func showDetailDestination(_ viewController: UIViewController) {
        if let navigationController {
            navigationController.pushViewController(viewController, animated: true)
        } else {
            present(UINavigationController(rootViewController: viewController), animated: true)
        }
    }

    private func resolvedDetailURL() -> URL? {
        if let postID = currentHeaderContent?.postID, postID.isEmpty == false {
            return URL(string: "https://www.nodeseek.com/post-\(postID)-\(currentPage)")
        }

        return sourcePostURL
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

    private var visiblePagination: PostDetailPagination? {
        guard let pagination, pagination.hasMultiplePages else { return nil }
        return pagination
    }

    private var detailRows: [DetailRow] {
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

    private func updatePageScrubber(isLoading: Bool, currentPageOverride: Int? = nil) {
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

    private func totalPageCount(from pagination: PostDetailPagination) -> Int {
        let itemPages = pagination.items.map(\.page)
        let candidatePages = itemPages + [pagination.currentPage, pagination.previousPage, pagination.nextPage].compactMap { $0 }
        return max(candidatePages.max() ?? pagination.currentPage, pagination.currentPage)
    }

    private func pageCompletionScrollRow() -> Int {
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

    private func fallbackPagination(from pagination: PostDetailPagination?, currentPage: Int) -> PostDetailPagination? {
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

extension PostDetailViewController: PostDetailViewProtocol {
    func showLoading() {
        loginButton.isHidden = true
        if hasRenderedDetailContent {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
            showLoadingSkeletonIfNeeded()
        }
    }

    func showPageLoading() {
        loginButton.isHidden = true
        loadingIndicator.stopAnimating()
        guard hasRenderedDetailContent, currentHeaderContent != nil else {
            showLoading()
            return
        }
        displayMode = .pageSkeleton
        updatePageScrubber(isLoading: true, currentPageOverride: pageLoadingTargetPage)
        reloadTableData()
    }

    func hideLoading() {
        loadingIndicator.stopAnimating()
    }

    func showError(message: String) {
        hideLoadingSkeleton()
        let alert = UIAlertController(title: "错误", message: message, preferredStyle: .alert)
        pageLoadingTargetPage = nil
        updatePageScrubber(isLoading: false)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    func showToast(message: String) {
        toastHideWorkItem?.cancel()
        toastLabel.text = message
        toastContainerView.isHidden = false
        toastContainerView.alpha = 0
        toastContainerView.transform = CGAffineTransform(translationX: 0, y: 8)

        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.toastContainerView.alpha = 1
            self.toastContainerView.transform = .identity
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.curveEaseIn, .allowUserInteraction]
            ) {
                self.toastContainerView.alpha = 0
                self.toastContainerView.transform = CGAffineTransform(translationX: 0, y: 8)
            } completion: { _ in
                self.toastContainerView.isHidden = true
                self.toastContainerView.transform = .identity
            }
        }
        toastHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    func render(detail: PostDetail) {
        title = "详情"
        loginButton.isHidden = true
        let shouldScrollToTop = hasRenderedDetailContent && detail.page != currentPage
        let existingHeaderContent = currentHeaderContent
        let existingRenderedContent = headerRenderedContent
        let shouldPreserveHeader = hasRenderedDetailContent
            && detail.page != 1
            && existingHeaderContent?.postID == detail.id
            && existingHeaderContent?.contentHTML.isEmpty == false
        currentPage = max(1, detail.page)
        pageLoadingTargetPage = nil
        renderGeneration += 1
        hasRenderedDetailContent = true
        displayMode = .content
        let headerContent = shouldPreserveHeader ? existingHeaderContent! : PostDetailHeaderContent(detail: detail)
        configureHeader(headerContent, renderedContent: shouldPreserveHeader ? existingRenderedContent : nil)
        pagination = detail.pagination ?? (shouldPreserveHeader ? fallbackPagination(from: pagination, currentPage: detail.page) : nil)
        comments = detail.comments
        commentRenderedCache.removeAll(keepingCapacity: true)
        renderedCommentIDs.removeAll(keepingCapacity: true)
        commentRenderInFlight.removeAll(keepingCapacity: true)
        updatePageScrubber(isLoading: false)
        reloadTableData()
        if shouldScrollToTop {
            let targetRow = pageCompletionScrollRow()
            #if DEBUG
            pendingScrollToRow = targetRow
            #endif
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.tableNode.scrollToRow(
                    at: IndexPath(row: targetRow, section: 0),
                    at: .top,
                    animated: false
                )
            }
        }
        if shouldPreserveHeader == false || existingRenderedContent == nil {
            scheduleHeaderRender(for: headerContent)
        }
        preheatCommentRender(for: comments)
    }

    func setCommentComposerSubmitting(_ isSubmitting: Bool) {
        isCommentSubmitting = isSubmitting

        var configuration = sendCommentButton.configuration ?? UIButton.Configuration.filled()
        configuration.showsActivityIndicator = isSubmitting
        configuration.image = isSubmitting ? nil : UIImage(systemName: "paperplane.fill")
        sendCommentButton.configuration = configuration
        sendCommentButton.accessibilityLabel = isSubmitting ? "正在发送评论" : "发送评论"

        updateSendButtonState()
    }

    func renderLoginRequired(message: String) {
        title = "详情"
        loginButton.isHidden = false
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
        pagination = nil
        comments = []
        commentRenderedCache.removeAll(keepingCapacity: true)
        renderedCommentIDs.removeAll(keepingCapacity: true)
        commentRenderInFlight.removeAll(keepingCapacity: true)
        updatePageScrubber(isLoading: false)
        reloadTableData()
        scheduleHeaderRender(for: headerContent)
    }

    func clearCommentComposer() {
        setCommentComposerText("", animated: true)
        composerMode = .plain
        updateComposerTarget()
    }
}

extension PostDetailViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updateCommentPlaceholderVisibility()
        updateSendButtonState()
        updateCommentTextViewHeight()
        scheduleDeferredCommentTextViewHeightRefresh()
    }

    private func updateSendButtonState() {
        sendCommentButton.isEnabled = isKeyboardVisible
            && isCommentSubmitting == false
            && !commentTextView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension PostDetailViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer is UITapGestureRecognizer else { return true }
        guard let touchedView = touch.view else { return true }
        return touchedView.isDescendant(of: composerContainerView) == false
    }
}

private final class CookieSharedWebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
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

    deinit {
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "网页"
        configureNavigationItems()

        webView.navigationDelegate = self
        webView.uiDelegate = self
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

    private func openInSafariViewController(_ url: URL) {
        present(SFSafariViewController(url: url), animated: true)
    }

    private func handleExternalNavigationIfNeeded(_ url: URL) -> Bool {
        guard case .safari(let safariURL) = PostDetailLinkResolver.destination(for: url, baseURL: self.url) else {
            return false
        }
        openInSafariViewController(safariURL)
        return true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingIndicator.stopAnimating()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           handleExternalNavigationIfNeeded(url) {
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
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

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        guard let targetURL = navigationAction.request.url else { return nil }

        if handleExternalNavigationIfNeeded(targetURL) {
            return nil
        }

        webView.load(navigationAction.request)
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        guard view.window != nil else {
            completionHandler()
            return
        }

        let alert = UIAlertController(title: webDialogTitle(from: frame), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler()
        })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard view.window != nil else {
            completionHandler(false)
            return
        }

        let alert = UIAlertController(title: webDialogTitle(from: frame), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            completionHandler(false)
        })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler(true)
        })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        guard view.window != nil else {
            completionHandler(nil)
            return
        }

        let alert = UIAlertController(title: webDialogTitle(from: frame), message: prompt, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = defaultText
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            completionHandler(nil)
        })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak alert] _ in
            completionHandler(alert?.textFields?.first?.text)
        })
        present(alert, animated: true)
    }

    private func webDialogTitle(from frame: WKFrameInfo) -> String {
        frame.request.url?.host ?? "网页"
    }
}

extension PostDetailViewController: ASTableDataSource, ASTableDelegate {
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
                    onReplyTapped: { comment in
                        self?.handleReply(to: comment)
                    },
                    onQuoteTapped: { comment in
                        self?.handleQuote(comment)
                    },
                    onTextLayoutInvalidated: {
                        self?.scheduleAttachmentLayoutRefresh()
                    }
                )
            }
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
}

private final class PostRepliesDividerCellNode: ASCellNode {
    private enum Layout {
        static let height: CGFloat = 8
    }

    private let dividerNode = ASDisplayNode()

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        backgroundColor = .systemBackground
        dividerNode.backgroundColor = .secondarySystemBackground
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        dividerNode.style.height = ASDimension(unit: .points, value: Layout.height)
        if constrainedSize.max.width.isFinite {
            dividerNode.style.width = ASDimension(unit: .points, value: constrainedSize.max.width)
        }
        return ASInsetLayoutSpec(insets: .zero, child: dividerNode)
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
        subtitleLabel.text = [
            AuthorDisplayPolicy.displayName(from: content.authorName),
            content.metadataText?.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
        contentView.configure(
            attributedContent,
            onImageTapped: onImageTapped,
            onLayoutInvalidated: onTextLayoutInvalidated
        )
        contentView.isHidden = attributedContent == nil
        contentTopConstraint?.constant = attributedContent == nil ? 0 : 16
        let shouldShowAvatar = AuthorDisplayPolicy.isDisplayable(content.authorName)
        avatarImageView.isHidden = !shouldShowAvatar
        if shouldShowAvatar {
            avatarLoader.loadAvatar(into: avatarImageView, postID: content.postID, avatarURL: content.avatarURL)
        } else {
            avatarLoader.cancel(on: avatarImageView)
            avatarImageView.image = nil
        }
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
        avatarImageView.isHidden = false
        metaLabel.text = nil
        bodyView.configure(nil, onImageTapped: nil, onLayoutInvalidated: nil)
        onImageTapped = nil
        onTextLayoutInvalidated = nil
    }

    func configure(comment: Comment, attributedBody: NSAttributedString?) {
        metaLabel.text = [
            comment.floorText,
            AuthorDisplayPolicy.displayName(from: comment.authorName),
            comment.createdAtText
        ].compactMap { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        bodyView.configure(
            attributedBody,
            onImageTapped: onImageTapped,
            onLayoutInvalidated: onTextLayoutInvalidated
        )
        let shouldShowAvatar = AuthorDisplayPolicy.isDisplayable(comment.authorName)
        avatarImageView.isHidden = !shouldShowAvatar
        if shouldShowAvatar {
            avatarLoader.loadAvatar(into: avatarImageView, postID: comment.id, avatarURL: comment.avatarURL)
        } else {
            avatarLoader.cancel(on: avatarImageView)
            avatarImageView.image = nil
        }
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
        guard let contentURL = attachment.contentURL else {
            logDiagnostics("viewForAttachment skipped type=\(String(describing: type(of: attachment))) contentURL=\(String(describing: attachment.contentURL)) frame=\(Self.string(from: frame))")
            return nil
        }

        logDiagnostics(
            "viewForAttachment url=\(contentURL.absoluteString) frame=\(Self.string(from: frame)) original=\(Self.string(from: attachment.originalSize)) display=\(Self.string(from: attachment.displaySize)) bounds=\(Self.string(from: bounds.size))"
        )
        let viewFrame = Self.attachmentViewFrame(
            proposedFrame: frame,
            displaySize: attachment.displaySize
        )

        let isStickerAttachment = isStickerAttachment(attachment, contentURL: contentURL)
        if isVideoURL(contentURL), isStickerAttachment {
            return DetailInlineVideoStickerView(frame: viewFrame, videoURL: contentURL)
        }

        guard attachment is DTImageTextAttachment else {
            logDiagnostics("viewForAttachment skipped type=\(String(describing: type(of: attachment))) contentURL=\(String(describing: attachment.contentURL)) frame=\(Self.string(from: frame))")
            return nil
        }

        let imageView = DetailInlineImageView(
            frame: viewFrame,
            imageURL: contentURL,
            targetPixelWidth: targetImagePointSide(
                originalSize: attachment.originalSize,
                isSticker: isStickerAttachment
            ) * displayScale,
            displayScale: displayScale,
            allowsInlineAnimation: allowsInlineAnimation(
                originalSize: attachment.originalSize,
                isSticker: isStickerAttachment
            ),
            onImageLoaded: { [weak self] loadedURL, imageSize in
                self?.handleLoadedImage(loadedURL, imageSize: imageSize)
            },
            onImageTapped: { [weak self] tappedURL in
                self?.handleImageTap(tappedURL)
            }
        )
        imageView.contentMode = contentMode(
            originalSize: attachment.originalSize,
            isSticker: isStickerAttachment
        )
        imageView.clipsToBounds = true
        imageView.isOpaque = false
        imageView.backgroundColor = .clear
        imageView.image = (attachment as? DTImageTextAttachment)?.image

        return imageView
    }

    nonisolated static func attachmentViewFrame(
        proposedFrame: CGRect,
        displaySize: CGSize
    ) -> CGRect {
        guard displaySize.width > 0,
              displaySize.height > 0 else {
            return proposedFrame
        }

        let yOffset = proposedFrame.height > displaySize.height
            ? (proposedFrame.height - displaySize.height) / 2
            : 0
        return CGRect(
            x: proposedFrame.minX,
            y: proposedFrame.minY + yOffset,
            width: displaySize.width,
            height: displaySize.height
        )
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

            let isSticker = isStickerAttachment(attachment, contentURL: url)
            let presentation = DetailImageLayout.presentation(
                for: originalSize,
                maxWidth: maxImageWidth(isSticker: isSticker),
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
                  isVideoURL(resolvedURL) == false,
                  isStickerAttachment(attachment, contentURL: resolvedURL) == false,
                  urls.contains(resolvedURL) == false else {
                return
            }
            urls.append(resolvedURL)
        }
        return urls
    }

    private func maxImageWidth(isSticker: Bool) -> CGFloat {
        let width = bounds.width > 0 ? bounds.width : 320
        return isSticker ? min(width, DetailImageLayout.fixedStickerWidth) : width
    }

    private func targetImagePointSide(originalSize: CGSize, isSticker: Bool) -> CGFloat {
        let maxWidth = maxImageWidth(isSticker: isSticker)
        guard originalSize.width > 0, originalSize.height > 0 else {
            return isSticker ? maxWidth : max(maxWidth, DetailImageLayout.maxImageHeight)
        }

        return DetailImageLayout.presentation(
            for: originalSize,
            maxWidth: maxWidth,
            isSticker: isSticker
        ).targetPointSide
    }

    private func allowsInlineAnimation(originalSize: CGSize, isSticker: Bool) -> Bool {
        guard isSticker || (originalSize.width > 0 && originalSize.height > 0) else { return false }
        return DetailImageLayout.allowsInlineAnimation(
            for: originalSize,
            maxWidth: maxImageWidth(isSticker: isSticker),
            isSticker: isSticker
        )
    }

    private func contentMode(originalSize: CGSize, isSticker: Bool) -> UIView.ContentMode {
        let mode = DetailImageLayout.presentation(
            for: originalSize,
            maxWidth: maxImageWidth(isSticker: isSticker),
            isSticker: isSticker
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

    private func isVideoURL(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        return pathExtension == "mp4" || pathExtension == "mov" || pathExtension == "m4v" || pathExtension == "webm"
    }

    private func isStickerAttachment(_ attachment: DTTextAttachment, contentURL: URL) -> Bool {
        DetailAttachmentAttributes.hasClass("sticker", in: attachment.attributes) || isStickerImageURL(contentURL)
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

final class DetailInlineImageView: AnimatedImageView {
    private static let logger = Logger(subsystem: "com.nodeseek.app", category: "DetailInlineImageView")

    private let imageURL: URL
    private let targetPixelWidth: CGFloat
    private let displayScale: CGFloat
    private let allowsInlineAnimation: Bool
    private let onImageLoaded: (URL, CGSize) -> Void
    private let onImageTapped: (URL) -> Void
    private var loadToken: UUID?
    private let diagnosticID = String(UUID().uuidString.prefix(8))

    init(
        frame: CGRect,
        imageURL: URL,
        targetPixelWidth: CGFloat,
        displayScale: CGFloat,
        allowsInlineAnimation: Bool,
        onImageLoaded: @escaping (URL, CGSize) -> Void,
        onImageTapped: @escaping (URL) -> Void
    ) {
        self.imageURL = imageURL
        self.targetPixelWidth = targetPixelWidth
        self.displayScale = displayScale
        self.allowsInlineAnimation = allowsInlineAnimation
        self.onImageLoaded = onImageLoaded
        self.onImageTapped = onImageTapped
        super.init(frame: frame)
        autoPlayAnimatedImage = true
        framePreloadCount = 6
        needsPrescaling = true
        purgeFramesOnBackground = true
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
            kf.cancelDownloadTask()
            purgeFrames()
            return
        }
        guard loadToken == nil else { return }

        let token = UUID()
        loadToken = token
        logDiagnostics(
            "startLoad url=\(imageURL.absoluteString) frame=\(Self.string(from: frame)) targetPixelWidth=\(Self.numberString(targetPixelWidth)) displayScale=\(Self.numberString(displayScale))"
        )

        if shouldUseAnimatedInlineLoader {
            loadAnimatedImage(token: token)
            return
        }

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

    private var shouldUseAnimatedInlineLoader: Bool {
        allowsInlineAnimation && imageURL.pathExtension.lowercased() == "gif"
    }

    private func loadAnimatedImage(token: UUID) {
        guard let resolvedURL = AvatarImageLoader.resolveImageURL(imageURL) else {
            logDiagnostics("animatedLoad invalidURL url=\(imageURL.absoluteString)")
            return
        }

        logDiagnostics("animatedLoad start url=\(resolvedURL.absoluteString)")
        kf.setImage(
            with: resolvedURL,
            options: [
                .requestModifier(AnyModifier { request in
                    var modifiedRequest = request
                    WebRequestFingerprint.applyImageHeaders(to: &modifiedRequest)
                    return modifiedRequest
                })
            ]
        ) { [weak self] result in
            guard let self, self.loadToken == token else { return }
            switch result {
            case .success(let value):
                self.logDiagnostics(
                    "animatedLoad loaded url=\(resolvedURL.absoluteString) imageSize=\(Self.string(from: value.image.size)) frame=\(Self.string(from: self.frame))"
                )
                self.onImageLoaded(self.imageURL, value.image.size)
            case .failure(let error):
                self.logDiagnostics(
                    "animatedLoad failed url=\(resolvedURL.absoluteString) error=\(error.localizedDescription)"
                )
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
