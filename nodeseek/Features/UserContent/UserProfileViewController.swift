//
//  UserProfileViewController.swift
//  nodeseek
//
//  Created by Claude on 2026/10/30.
//

import SafariServices
import UIKit

/// 原生个人页，替代 `/space/<uid>` 的 WebView。
@MainActor
final class UserProfileViewController: UIViewController {
    private enum Layout {
        static let sideInset: CGFloat = 16
        static let cardCornerRadius: CGFloat = 14
        static let avatarSize: CGFloat = 72
        static let sectionSpacing: CGFloat = 22
    }

    private let uid: Int
    private let client: NodeSeekUserContentClient
    private let currentAccountStore: CurrentAccountStore

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let refreshControl = UIRefreshControl()
    private let skeletonView = UserProfileSkeletonView()
    private let errorView = UserContentErrorView(accessibilityIdentifier: "user-profile-error-view")
    private let avatarControl = UserProfileAvatarControl()
    private var photoBrowserPresenter: DetailPhotoBrowserPresenter?
    private let progressSection = UIStackView()
    private let progressCard = UserProfileProgressCardView()

    private var profile: UserProfileRecord?
    private var isSelf = false
    private var loadTask: Task<Void, Never>?
    var onSelectPost: ((PostSummary, Int, String?) -> Void)?

    init(
        uid: Int,
        client: NodeSeekUserContentClient? = nil,
        currentAccountStore: CurrentAccountStore = .shared
    ) {
        self.uid = uid
        self.client = client ?? NodeSeekUserContentClient()
        self.currentAccountStore = currentAccountStore
        super.init(nibName: nil, bundle: nil)
        navigationItem.largeTitleDisplayMode = .never
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupMoreMenu()
        loadProfile(showsIndicator: true)
    }

    // MARK: - 布局

    private func setupUI() {
        view.backgroundColor = .systemGroupedBackground

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)

        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        avatarControl.translatesAutoresizingMaskIntoConstraints = false
        avatarControl.addTarget(self, action: #selector(avatarTapped), for: .touchUpInside)
        NSLayoutConstraint.activate([
            avatarControl.widthAnchor.constraint(equalToConstant: Layout.avatarSize),
            avatarControl.heightAnchor.constraint(equalToConstant: Layout.avatarSize)
        ])

        skeletonView.translatesAutoresizingMaskIntoConstraints = false
        skeletonView.isHidden = true
        errorView.onRetry = { [weak self] in
            self?.loadProfile(showsIndicator: true)
        }

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        view.addSubview(skeletonView)
        view.addSubview(errorView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            skeletonView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            skeletonView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            skeletonView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),

            errorView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            errorView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
    }

    private func setupMoreMenu() {
        let webAction = UIAction(title: "网页版主页", image: UIImage(systemName: "globe")) { [weak self] _ in
            self?.openWebProfile()
        }
        let copyAction = UIAction(title: "复制主页链接", image: UIImage(systemName: "link")) { [weak self] _ in
            UIPasteboard.general.url = self?.profileURL
        }
        let item = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(children: [webAction, copyAction])
        )
        item.accessibilityLabel = "个人页更多操作"
        navigationItem.rightBarButtonItem = item
    }

    private var profileURL: URL {
        NodeSeekSite.baseURL
            .appendingPathComponent("space")
            .appendingPathComponent("\(uid)")
    }

    // MARK: - 加载

    private func loadProfile(showsIndicator: Bool) {
        loadTask?.cancel()
        if showsIndicator {
            scrollView.isHidden = true
            errorView.isHidden = true
            skeletonView.isHidden = false
        }

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let currentUID = await currentAccountStore.snapshot()?.account.nodeSeekUID
                let profile = try await client.loadProfile(uid: uid)
                guard !Task.isCancelled else { return }
                self.isSelf = currentUID == uid
                show(profile)
                if isSelf {
                    loadTodayProgress()
                }
            } catch {
                guard !Task.isCancelled else { return }
                showError(error.localizedDescription)
            }
        }
    }

    private func loadTodayProgress() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let progress = try await client.loadTodayProgress(uid: uid)
                guard let profile else { return }
                progressCard.configure(level: profile.levelProgress, today: progress)
                progressSection.isHidden = false
            } catch {
                // 进度只是附加信息，失败时不打扰用户
                progressSection.isHidden = true
                AppLog.info(.account, "个人页今日进度加载失败：\(error.localizedDescription)")
            }
        }
    }

    private func show(_ profile: UserProfileRecord) {
        self.profile = profile
        navigationItem.backButtonTitle = profile.name
        skeletonView.isHidden = true
        refreshControl.endRefreshing()
        errorView.isHidden = true
        scrollView.isHidden = false
        rebuildContent(with: profile)
    }

    private func showError(_ message: String) {
        skeletonView.isHidden = true
        refreshControl.endRefreshing()
        // 已有内容时下拉刷新失败保留旧内容
        guard profile == nil else { return }
        scrollView.isHidden = true
        errorView.messageLabel.text = message
        errorView.isHidden = false
    }

    @objc private func refreshTriggered() {
        loadProfile(showsIndicator: false)
    }

    // MARK: - 内容

    private func rebuildContent(with profile: UserProfileRecord) {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        contentStack.addArrangedSubview(makeHeader(profile))
        contentStack.setCustomSpacing(18, after: contentStack.arrangedSubviews.last!)
        contentStack.addArrangedSubview(inset(makeStatsCard(profile)))

        if isSelf {
            progressSection.axis = .vertical
            progressSection.isHidden = true
            progressSection.arrangedSubviews.forEach { $0.removeFromSuperview() }
            progressSection.addArrangedSubview(makeSectionHeader("今日进度", trailing: Self.todayText()))
            progressSection.addArrangedSubview(inset(progressCard))
            contentStack.addArrangedSubview(progressSection)
        }

        contentStack.addArrangedSubview(makeSectionHeader(isSelf ? "我的内容" : "内容"))
        contentStack.addArrangedSubview(inset(makeContentCard(profile)))

        // 没写自述的用户接口返回 null，整块不显示
        let readme = profile.readme.trimmingCharacters(in: .whitespacesAndNewlines)
        if !readme.isEmpty {
            contentStack.addArrangedSubview(makeSectionHeader("自述"))
            let readmeView = UserProfileReadmeView(markdown: readme)
            readmeView.onOpenURL = { [weak self] url in
                self?.openLink(url)
            }
            contentStack.addArrangedSubview(inset(makeCard(containing: readmeView)))
        }
    }

    private func makeHeader(_ profile: UserProfileRecord) -> UIView {
        avatarControl.detailPhotoThumbnailURL = profile.avatarURL
        AvatarImageLoader.shared.loadAvatar(
            into: avatarControl.imageView,
            postID: "profile-\(profile.uid)",
            avatarURL: profile.avatarURL
        )

        let nameLabel = UILabel()
        nameLabel.text = profile.name
        nameLabel.font = .systemFont(ofSize: 24, weight: .bold)
        nameLabel.textColor = .label
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let nameRow = UIStackView(arrangedSubviews: [nameLabel])
        nameRow.axis = .horizontal
        nameRow.alignment = .center
        nameRow.spacing = 6
        for role in profile.roleNames {
            nameRow.addArrangedSubview(UserProfileBadgeLabel(text: role))
        }
        nameRow.addArrangedSubview(UIView())
        if !isSelf {
            nameRow.addArrangedSubview(makeMessageButton())
        }

        let infoStack = UIStackView(arrangedSubviews: [nameRow])
        infoStack.axis = .vertical
        infoStack.spacing = 3
        if !profile.bio.isEmpty {
            infoStack.addArrangedSubview(makeLabel(profile.bio, size: 14.5, color: .secondaryLabel, lines: 2))
        }
        var meta = "UID \(profile.uid)"
        if let days = profile.joinedDays() {
            meta += " · 加入 \(days) 天"
        }
        infoStack.addArrangedSubview(makeLabel(meta, size: 12.5, color: .secondaryLabel))

        let header = UIStackView(arrangedSubviews: [avatarControl, infoStack])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 14
        header.isLayoutMarginsRelativeArrangement = true
        header.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
        return header
    }

    @objc private func avatarTapped() {
        guard let url = avatarControl.detailPhotoThumbnailURL else { return }
        DetailPhotoTransitionAnchor.record(imageView: avatarControl.imageView, url: url)
        let presenter = DetailPhotoBrowserPresenter(imageURLs: [url])
        photoBrowserPresenter = presenter
        presenter.present(from: self, initialIndex: 0)
    }

    private func makeMessageButton() -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: "bubble.left",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        )
        configuration.imagePadding = 4
        configuration.title = "私信"
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 13.5, weight: .semibold)
            return attributes
        }
        configuration.baseForegroundColor = .label
        configuration.background.backgroundColor = .tertiarySystemFill
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        let button = UIButton(configuration: configuration)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addAction(UIAction { [weak self] _ in
            self?.openMessage()
        }, for: .touchUpInside)
        return button
    }

    private func makeStatsCard(_ profile: UserProfileRecord) -> UIView {
        let uid = profile.uid
        let creditStat: UserProfileStatView
        if isSelf {
            creditStat = UserProfileStatView(value: "\(profile.coin)", title: "鸡腿") { [weak self] in
                self?.navigationController?.pushViewController(UserCreditViewController(uid: uid, profile: profile), animated: true)
            }
        } else {
            creditStat = UserProfileStatView(value: "\(profile.coin)", title: "鸡腿")
        }
        var items: [UserProfileStatView] = [
            UserProfileStatView(value: "Lv \(profile.rank)", title: "等级"),
            creditStat,
            UserProfileStatView(value: "\(profile.stardust)", title: "星辰") { [weak self] in
                self?.navigationController?.pushViewController(UserStardustViewController(uid: uid, profile: profile, isSelf: self?.isSelf ?? false), animated: true)
            }
        ]
        // 粉丝、关注列表网页只能看自己的
        if isSelf {
            items.append(UserProfileStatView(value: "\(profile.fans)", title: "粉丝") { [weak self] in
                self?.navigationController?.pushViewController(UserConnectionsViewController(initialKind: .followers), animated: true)
            })
            items.append(UserProfileStatView(value: "\(profile.follows)", title: "关注") { [weak self] in
                self?.navigationController?.pushViewController(UserConnectionsViewController(initialKind: .following), animated: true)
            })
        } else {
            items.append(UserProfileStatView(value: "\(profile.fans)", title: "粉丝"))
        }
        items.dropFirst().forEach { $0.showsLeadingSeparator = true }

        let stack = UIStackView(arrangedSubviews: items)
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 0, bottom: 12, trailing: 0)
        return makeCard(containing: stack)
    }

    private func makeContentCard(_ profile: UserProfileRecord) -> UIView {
        let uid = profile.uid
        let name = profile.name
        var rows = [
            UserProfileRowView(
                symbolName: "doc.text",
                title: isSelf ? "我的帖子" : "主题帖",
                count: profile.postCount
            ) { [weak self] in
                guard let self else { return }
                let title = isSelf ? "帖子" : "\(name) 的帖子"
                pushList(UserDiscussionsViewController(uid: uid, title: title))
            },
            UserProfileRowView(
                symbolName: "bubble.left",
                title: isSelf ? "我的评论" : "评论",
                count: profile.commentCount
            ) { [weak self] in
                guard let self else { return }
                let title = isSelf ? "评论" : "\(name) 的评论"
                pushList(UserCommentsViewController(uid: uid, title: title))
            }
        ]
        if isSelf {
            rows.append(UserProfileRowView(
                symbolName: "star",
                title: "我的收藏",
                count: profile.collectionCount
            ) { [weak self] in
                self?.pushList(UserCollectionsViewController(uid: uid))
            })
        }
        rows.dropFirst().forEach { $0.showsTopSeparator = true }

        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        return makeCard(containing: stack)
    }

    // MARK: - 跳转

    private func pushList(_ viewController: UIViewController) {
        let onSelectPost: (PostSummary, Int, String?) -> Void = { [weak self] post, page, anchorID in
            self?.openPost(post, page: page, anchorID: anchorID)
        }
        switch viewController {
        case let list as UserDiscussionsViewController:
            list.onSelectPost = onSelectPost
        case let list as UserCommentsViewController:
            list.onSelectPost = onSelectPost
        case let list as UserCollectionsViewController:
            list.onSelectPost = onSelectPost
        default:
            break
        }
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func openPost(_ post: PostSummary, page: Int, anchorID: String?) {
        if let onSelectPost {
            onSelectPost(post, page, anchorID)
            return
        }
        let detail = PostDetailRouter.createModule(post: post, page: page, initialAnchorID: anchorID)
        navigationController?.pushViewController(detail, animated: true)
    }

    /// 自述里的链接：站内帖子走原生详情，其余站内页面用 WebView，站外用 Safari
    private func openLink(_ url: URL) {
        if let route = NodeSeekPostRouteResolver.route(for: url, baseURL: NodeSeekSite.baseURL) {
            let post = UserContentPostSummaryFactory.postSummary(id: Int(route.postID) ?? 0, title: "帖子 #\(route.postID)")
            openPost(post, page: route.page, anchorID: route.anchorID)
            return
        }
        let absoluteURL = url.scheme == nil ? URL(string: url.absoluteString, relativeTo: NodeSeekSite.baseURL)?.absoluteURL ?? url : url
        if let uid = UserProfileRouter.nativeUID(for: absoluteURL) {
            navigationController?.pushViewController(UserProfileViewController(uid: uid), animated: true)
            return
        }
        if NodeSeekSite.isNodeSeekHost(absoluteURL) {
            navigationController?.pushViewController(NodeSeekWebViewController(url: absoluteURL), animated: true)
            return
        }
        guard absoluteURL.scheme == "http" || absoluteURL.scheme == "https" else { return }
        present(SFSafariViewController(url: absoluteURL), animated: true)
    }

    private func openMessage() {
        let url = NodeSeekNotificationURLBuilder.webURL(fragment: "/message?mode=talk&to=\(uid)")
        navigationController?.pushViewController(NodeSeekWebViewController(url: url), animated: true)
    }

    private func openWeb(path: String, query: [URLQueryItem]) {
        var components = URLComponents(url: NodeSeekSite.baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = query
        guard let url = components?.url else { return }
        navigationController?.pushViewController(NodeSeekWebViewController(url: url), animated: true)
    }

    private func openWebProfile() {
        let viewController = UserInfoWebViewController(profileURL: profileURL, title: profile?.name ?? "用户主页")
        navigationController?.pushViewController(viewController, animated: true)
    }

    // MARK: - 小工具

    private func makeCard(containing content: UIView) -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = Layout.cardCornerRadius
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            content.topAnchor.constraint(equalTo: card.topAnchor),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])
        return card
    }

    private func inset(_ view: UIView) -> UIView {
        let container = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.sideInset),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Layout.sideInset),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func makeSectionHeader(_ title: String, trailing: String? = nil) -> UIView {
        let titleLabel = makeLabel(title, size: 13, color: .secondaryLabel)
        let stack = UIStackView(arrangedSubviews: [titleLabel, UIView()])
        if let trailing {
            stack.addArrangedSubview(makeLabel(trailing, size: 13, color: .secondaryLabel))
        }
        stack.axis = .horizontal
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Layout.sectionSpacing,
            leading: 32,
            bottom: 7,
            trailing: 32
        )
        return stack
    }

    private func makeLabel(_ text: String, size: CGFloat, color: UIColor, lines: Int = 1) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size)
        label.textColor = color
        label.numberOfLines = lines
        return label
    }

    private static func todayText() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日"
        return formatter.string(from: Date())
    }
}

// MARK: - 子视图

/// 个人页头像。点按打开大图，并作为缩放预览的起点。
private final class UserProfileAvatarControl: UIControl, DetailPhotoThumbnailSource {
    let imageView = UIImageView()
    var detailPhotoThumbnailURL: URL?
    var detailPhotoThumbnailView: UIImageView { imageView }

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 16
        imageView.layer.cornerCurve = .continuous
        imageView.backgroundColor = .tertiarySystemFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        isAccessibilityElement = true
        accessibilityIdentifier = "user-profile-avatar"
        accessibilityLabel = "查看头像大图"
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// 角色徽章：描边颜色跟随深浅色切换
private final class UserProfileBadgeLabel: UILabel {
    init(text: String) {
        super.init(frame: .zero)
        self.text = text
        font = .systemFont(ofSize: 11.5, weight: .semibold)
        textColor = .label
        textAlignment = .center
        layer.cornerRadius = 5
        layer.borderWidth = 1
        updateBorderColor()
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + 12, height: 19)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateBorderColor()
    }

    private func updateBorderColor() {
        layer.borderColor = UIColor.label.resolvedColor(with: traitCollection).cgColor
    }
}

private final class UserProfileStatView: UIControl {
    private let separator = UIView()
    private let action: (() -> Void)?

    var showsLeadingSeparator = false {
        didSet { separator.isHidden = !showsLeadingSeparator }
    }

    init(value: String, title: String, action: (() -> Void)? = nil) {
        self.action = action
        super.init(frame: .zero)

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .bold)
        valueLabel.textColor = .label
        valueLabel.textAlignment = .center
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .secondaryLabel

        let titleRow = UIStackView(arrangedSubviews: [titleLabel])
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 2
        if action != nil {
            let chevron = UIImageView(image: UIImage(
                systemName: "chevron.right",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
            ))
            chevron.tintColor = .secondaryLabel
            titleRow.addArrangedSubview(chevron)
        }

        let stack = UIStackView(arrangedSubviews: [valueLabel, titleRow])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        separator.backgroundColor = .separator
        separator.isHidden = true
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            valueLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -8),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            separator.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])

        isAccessibilityElement = true
        accessibilityLabel = "\(title) \(value)"
        accessibilityTraits = action == nil ? .staticText : .button
        if action != nil {
            addTarget(self, action: #selector(tapped), for: .touchUpInside)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            guard action != nil else { return }
            alpha = isHighlighted ? 0.5 : 1
        }
    }

    @objc private func tapped() {
        action?()
    }
}

private final class UserProfileRowView: UIControl {
    private let separator = UIView()
    private let action: () -> Void

    var showsTopSeparator = false {
        didSet { separator.isHidden = !showsTopSeparator }
    }

    init(symbolName: String, title: String, count: Int?, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)

        let iconView = UIImageView(image: UIImage(
            systemName: symbolName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        ))
        iconView.tintColor = .label
        iconView.contentMode = .center
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 16)
        titleLabel.textColor = .label

        let countLabel = UILabel()
        countLabel.text = count.map { "\($0)" }
        countLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        countLabel.textColor = .secondaryLabel

        let chevron = UIImageView(image: UIImage(
            systemName: "chevron.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        ))
        chevron.tintColor = .tertiaryLabel

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, UIView(), countLabel, chevron])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.setCustomSpacing(14, after: iconView)
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        separator.backgroundColor = .separator
        separator.isHidden = true
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 46),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 50),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])

        isAccessibilityElement = true
        accessibilityLabel = [title, count.map { "\($0)" }].compactMap { $0 }.joined(separator: " ")
        accessibilityTraits = .button
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? .systemFill : .clear
        }
    }

    @objc private func tapped() {
        action()
    }
}

/// 今日进度卡片：只有进度条带系统色，其余保持黑白
final class UserProfileProgressCardView: UIView {
    private let levelTitleLabel = UILabel()
    private let levelValueLabel = UILabel()
    private let levelBar = UserProfileProgressBar(color: .systemIndigo)
    private let checkInRow = UserProfileProgressRow(title: "签到", color: .systemOrange)
    private let postRow = UserProfileProgressRow(title: "发帖", color: .systemBlue)
    private let commentRow = UserProfileProgressRow(title: "评论", color: .systemTeal)
    private let freeLikeRow = UserProfileProgressRow(title: "免费投喂", color: .systemPink)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous

        levelTitleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        levelTitleLabel.textColor = .label
        levelValueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        levelValueLabel.textColor = .secondaryLabel
        levelValueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let levelTop = UIStackView(arrangedSubviews: [levelTitleLabel, UIView(), levelValueLabel])
        levelTop.axis = .horizontal
        levelTop.alignment = .firstBaseline

        let levelStack = UIStackView(arrangedSubviews: [levelTop, levelBar])
        levelStack.axis = .vertical
        levelStack.spacing = 10
        levelStack.isLayoutMarginsRelativeArrangement = true
        levelStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)

        let divider = UIView()
        divider.backgroundColor = .separator

        let rowsStack = UIStackView(arrangedSubviews: [checkInRow, postRow, commentRow, freeLikeRow])
        rowsStack.axis = .vertical
        rowsStack.isLayoutMarginsRelativeArrangement = true
        rowsStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)

        let stack = UIStackView(arrangedSubviews: [levelStack, divider, rowsStack])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(level: UserLevelProgress, today: UserTodayProgressRecord) {
        if level.isMaxRank {
            levelTitleLabel.text = "Lv \(level.rank) 已满级"
            levelValueLabel.text = "\(level.coin) 鸡腿"
        } else {
            levelTitleLabel.text = "距 Lv \(level.nextRank) 还差 \(level.remaining) 鸡腿"
            levelValueLabel.text = "\(level.coin) / \(level.upperBound)"
        }
        levelBar.fraction = level.fraction

        if let gain = today.checkInGain {
            checkInRow.configure(fraction: 1, value: "+\(gain) ✓", isDone: true)
        } else {
            checkInRow.configure(fraction: 0, value: "未签到", isDone: false)
        }
        postRow.configure(current: today.postCoin, maximum: today.maxPostCoin)
        commentRow.configure(current: today.commentBonusCount, maximum: today.maxCommentBonusCount)
        freeLikeRow.configure(current: today.freeLikeUsed, maximum: today.maxFreeLike)
    }
}

private final class UserProfileProgressRow: UIStackView {
    private let bar: UserProfileProgressBar
    private let valueLabel = UILabel()

    init(title: String, color: UIColor) {
        bar = UserProfileProgressBar(color: color)
        super.init(frame: .zero)
        axis = .horizontal
        alignment = .center
        spacing = 12

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15)
        titleLabel.textColor = .label

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        valueLabel.textColor = .secondaryLabel
        valueLabel.textAlignment = .right

        addArrangedSubview(titleLabel)
        addArrangedSubview(bar)
        addArrangedSubview(valueLabel)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            titleLabel.widthAnchor.constraint(equalToConstant: 64),
            valueLabel.widthAnchor.constraint(equalToConstant: 58)
        ])
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(current: Int, maximum: Int) {
        let fraction = maximum > 0 ? Double(current) / Double(maximum) : 0
        configure(fraction: fraction, value: "\(current) / \(maximum)", isDone: maximum > 0 && current >= maximum)
    }

    func configure(fraction: Double, value: String, isDone: Bool) {
        bar.fraction = fraction
        valueLabel.text = value
        valueLabel.textColor = isDone ? .label : .secondaryLabel
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: isDone ? .semibold : .regular)
    }
}

private final class UserProfileProgressBar: UIView {
    private let fillView = UIView()

    var fraction: Double = 0 {
        didSet { setNeedsLayout() }
    }

    init(color: UIColor) {
        super.init(frame: .zero)
        backgroundColor = .systemFill
        layer.cornerRadius = 3
        clipsToBounds = true
        fillView.backgroundColor = color
        fillView.layer.cornerRadius = 3
        addSubview(fillView)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 6).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let clamped = min(1, max(0, fraction))
        fillView.frame = CGRect(x: 0, y: 0, width: bounds.width * clamped, height: bounds.height)
    }
}
