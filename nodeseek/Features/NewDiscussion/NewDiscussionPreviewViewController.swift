//
//  NewDiscussionPreviewViewController.swift
//  nodeseek
//

import AsyncDisplayKit
import UIKit

/// 发帖预览：正文转成 HTML 后走详情页同一套渲染，看到的就是发出去在 App 里的样子。
final class NewDiscussionPreviewViewController: UIViewController {
    private let draft: NewDiscussionDraft
    private let publishTitle: String
    private let onPublish: () -> Void
    private let tableNode = ASTableNode(style: .plain)
    private var headerContent: PostDetailHeaderContent
    private var renderedContent: [RenderedContentBlock]?

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

        tableNode.dataSource = self
        tableNode.view.separatorStyle = .none
        tableNode.view.backgroundColor = .systemBackground
        tableNode.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableNode.view)
        NSLayoutConstraint.activate([
            tableNode.view.topAnchor.constraint(equalTo: view.topAnchor),
            tableNode.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableNode.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableNode.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        loadAuthor()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 富文本颜色在渲染时就固定了，要等进入窗口拿到真实的深浅模式再渲染。
        if renderedContent == nil {
            reloadRenderedContent()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard renderedContent != nil,
              previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        reloadRenderedContent()
    }

    private func reloadRenderedContent() {
        traitCollection.performAsCurrent { renderContent() }
        tableNode.reloadData(completion: nil)
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

    private func renderContent() {
        let markdown = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !markdown.isEmpty else {
            renderedContent = [.text(NSAttributedString(
                string: "正文还是空的",
                attributes: [.font: UIFont.preferredFont(forTextStyle: .body), .foregroundColor: UIColor.tertiaryLabel]
            ))]
            return
        }
        let html = MarkdownPreviewHTMLRenderer.html(from: markdown, stickerURL: Self.stickerURL)
        let maxImageWidth = max(view.bounds.width - PostDetailContentLayout.horizontalInset * 2, 1)
        renderedContent = PostDetailViewController.makeRenderedContent(
            html: html,
            baseURL: NodeSeekSite.baseURL,
            maxImageWidth: maxImageWidth,
            showsSignature: false
        )
    }

    /// 作者信息只用缓存账号，读不到时显示“我”，不为预览单独发请求。
    private func loadAuthor() {
        Task { [weak self] in
            let account = await CurrentAccountRefresher.shared.cachedAccount()
            guard let self, let account, account.isLoggedIn else { return }
            headerContent = Self.headerContent(for: draft, account: account)
            tableNode.reloadData(completion: nil)
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

    private static func stickerURL(_ token: String) -> URL? {
        stickerURLs[token]
    }
}

extension NewDiscussionPreviewViewController: ASTableDataSource {
    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        renderedContent == nil ? 0 : 1
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        let content = headerContent
        let renderedContent = renderedContent
        return { [weak self] in
            let node = PostBodyCellNode(
                content: content,
                renderedContent: renderedContent,
                onImageTapped: { _, _ in },
                showsReplyActions: false,
                onTextLayoutInvalidated: {
                    self?.tableNode.relayoutItems()
                }
            )
            node.selectionStyle = .none
            return node
        }
    }
}
