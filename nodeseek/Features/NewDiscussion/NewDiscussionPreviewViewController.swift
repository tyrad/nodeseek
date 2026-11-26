//
//  NewDiscussionPreviewViewController.swift
//  nodeseek
//

import UIKit

/// 发帖预览：正文转成 HTML 后走详情页同一套渲染，看到的就是发出去在 App 里的样子。
final class NewDiscussionPreviewViewController: UIViewController {
    private let draft: NewDiscussionDraft
    private let publishTitle: String
    private let onPublish: () -> Void
    private let preview = DetailFloorPreviewScrollView()
    private var headerContent: PostDetailHeaderContent

    init(draft: NewDiscussionDraft, publishTitle: String = "发布", onPublish: @escaping () -> Void) {
        self.draft = draft
        self.publishTitle = publishTitle
        self.onPublish = onPublish
        self.headerContent = Self.headerContent(for: draft, account: nil)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "预览"
        view.backgroundColor = .systemBackground
        setupPublishButton()

        preview.configureHeader = { [weak self] cell in
            guard let content = self?.headerContent else { return }
            cell.configureHeader(title: content.title, requiredLevel: content.requiredReadingLevel,
                                 name: content.authorName, badges: [], time: content.metadataText, floor: nil)
            cell.configureAuthor(name: content.authorName, avatarURL: content.avatarURL, profileURL: nil) { _ in }
        }
        let markdown = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let stickers = Self.stickerURLs
        let emptyColor = MarkdownEditorStyler.secondaryTextColor
        preview.loadContent = DetailFloorPreviewScrollView.background { width in
            guard !markdown.isEmpty else {
                return [.text(NSAttributedString(string: "正文还是空的", attributes: [
                    .font: AppTypography.commentBodyFont(), .foregroundColor: emptyColor
                ]))]
            }
            let html = MarkdownPreviewHTMLRenderer.html(from: markdown) { stickers[$0] }
            return PostDetailViewController.makeRenderedContent(html: html, baseURL: NodeSeekSite.baseURL,
                                                               maxImageWidth: width, showsSignature: false)
        }
        preview.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(preview)
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: view.topAnchor),
            preview.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            preview.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        loadAuthor()
    }

    private func setupPublishButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.title = publishTitle
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .label
        configuration.baseForegroundColor = .systemBackground
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        let button = UIButton(configuration: configuration)
        button.addAction(UIAction { [weak self] _ in self?.onPublish() }, for: .touchUpInside)
        let item = UIBarButtonItem(customView: button)
        if #available(iOS 26.0, *) {
            item.hidesSharedBackground = true
        }
        navigationItem.rightBarButtonItem = item
    }

    /// 作者信息只用缓存账号，读不到时显示“我”，不为预览单独发请求。
    private func loadAuthor() {
        Task { [weak self] in
            let account = await CurrentAccountRefresher.shared.cachedAccount()
            guard let self, let account, account.isLoggedIn else { return }
            headerContent = Self.headerContent(for: draft, account: account)
            preview.refreshHeader()
        }
    }

    private static func headerContent(for draft: NewDiscussionDraft, account: AccountResponse?) -> PostDetailHeaderContent {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let metadata = [draft.category?.title, draft.rank == .onlyMe ? "私有" : nil, "刚刚"]
            .compactMap { $0 }
            .joined(separator: " · ")
        var requiredLevel: Int?
        if draft.rank != .everyone && draft.rank != .onlyMe {
            requiredLevel = draft.rank.rawValue
        }
        return PostDetailHeaderContent(
            postID: "new-discussion-preview",
            title: title.isEmpty ? "（无标题）" : title,
            authorName: account?.displayName ?? "我",
            avatarURL: account?.avatarURL,
            metadataText: metadata,
            requiredReadingLevel: requiredLevel
        )
    }

    private static let stickerURLs: [String: URL] = {
        var result: [String: URL] = [:]
        for pack in NodeSeekStickerLibrary.defaultPacks {
            for item in pack.items {
                result[item.token] = item.imageURLs.first
            }
        }
        return result
    }()
}
