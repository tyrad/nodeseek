//
//  PostDetailViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit

class PostDetailViewController: UIViewController {
    private enum Layout {
        static let horizontalInset: CGFloat = 20
        static let commentHorizontalInset: CGFloat = 12
        static let commentCardInset: CGFloat = 12
        static let avatarSize: CGFloat = 40
        static let avatarSpacing: CGFloat = 12
    }

    private let presenter: PostDetailPresenterProtocol
    private let contentRenderer = HTMLContentRenderer()
    private let baseURL = URL(string: "https://www.nodeseek.com")!
    private let headerView = PostDetailHeaderView()
    private var currentHeaderContent: PostDetailHeaderContent?
    private var comments: [Comment] = []

    private let tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.backgroundColor = .systemBackground
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 120
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    init(presenter: PostDetailPresenterProtocol, initialHeader: PostDetailHeaderContent? = nil) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)

        if let initialHeader {
            configureHeader(initialHeader)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        presenter.viewDidLoad()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        resizeTableHeaderView()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(PostDetailCommentCell.self, forCellReuseIdentifier: PostDetailCommentCell.reuseIdentifier)

        view.addSubview(tableView)
        view.addSubview(loadingIndicator)
        tableView.tableHeaderView = headerView

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func configureHeader(_ content: PostDetailHeaderContent) {
        currentHeaderContent = content
        let attributedContent = renderedAttributedText(
            html: content.contentHTML,
            maxImageWidth: availableHeaderContentWidth
        )
        headerView.configure(content, attributedContent: attributedContent)
        resizeTableHeaderView()
    }

    private func renderedAttributedText(html: String, maxImageWidth: CGFloat) -> NSAttributedString? {
        let blocks = contentRenderer.render(fragment: html, baseURL: baseURL, maxImageWidth: maxImageWidth)
        guard blocks.isEmpty == false else { return nil }

        let result = NSMutableAttributedString()
        for block in blocks {
            switch block {
            case .text(let attributedText):
                result.append(attributedText)
            case .imagePlaceholder(let url):
                result.append(NSAttributedString(string: url?.absoluteString ?? "[图片]"))
            case .unsupported(let reason):
                result.append(NSAttributedString(string: reason))
            }
        }

        return result.length > 0 ? result : nil
    }

    private func resizeTableHeaderView() {
        guard let tableHeaderView = tableView.tableHeaderView else { return }

        let width = tableView.bounds.width > 0 ? tableView.bounds.width : view.bounds.width
        guard width > 0 else { return }

        tableHeaderView.frame.size.width = width
        let targetSize = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let height = tableHeaderView.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        guard abs(tableHeaderView.frame.height - height) > 0.5 else { return }
        tableHeaderView.frame.size.height = height
        tableView.tableHeaderView = tableHeaderView
    }

    private var availableHeaderContentWidth: CGFloat {
        let width = tableView.bounds.width > 0 ? tableView.bounds.width : view.bounds.width
        return max((width > 0 ? width : 320) - Layout.horizontalInset * 2, 1)
    }

    private var availableCommentContentWidth: CGFloat {
        let width = tableView.bounds.width > 0 ? tableView.bounds.width : view.bounds.width
        let contentWidth = (width > 0 ? width : 320)
            - Layout.commentHorizontalInset * 2
            - Layout.commentCardInset * 2
            - Layout.avatarSize
            - Layout.avatarSpacing
        return max(contentWidth, 1)
    }
}

extension PostDetailViewController: PostDetailViewProtocol {
    func showLoading() {
        loadingIndicator.startAnimating()
    }

    func hideLoading() {
        loadingIndicator.stopAnimating()
    }

    func showError(message: String) {
        let alert = UIAlertController(title: "错误", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    func render(detail: PostDetail) {
        title = "详情"
        configureHeader(PostDetailHeaderContent(detail: detail))
        comments = detail.comments
        tableView.reloadData()
    }

    func renderLoginRequired(message: String) {
        title = "详情"
        let existing = currentHeaderContent
        configureHeader(PostDetailHeaderContent(
            postID: existing?.postID ?? "login-required",
            title: existing?.title ?? "需要登录",
            authorName: existing?.authorName ?? "NodeSeek",
            avatarURL: existing?.avatarURL,
            metadataText: existing?.metadataText,
            contentHTML: message
        ))
        comments = []
        tableView.reloadData()
    }
}

extension PostDetailViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        comments.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: PostDetailCommentCell.reuseIdentifier,
            for: indexPath
        ) as? PostDetailCommentCell else {
            return UITableViewCell()
        }

        cell.configure(
            comment: comments[indexPath.row],
            baseURL: baseURL,
            maxImageWidth: availableCommentContentWidth
        )
        return cell
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

    private let contentLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    private var contentTopConstraint: NSLayoutConstraint?

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
        contentLabel.attributedText = attributedContent
        contentLabel.isHidden = attributedContent == nil
        contentTopConstraint?.constant = attributedContent == nil ? 0 : 16
        avatarLoader.loadAvatar(into: avatarImageView, postID: content.postID, avatarURL: content.avatarURL)
    }

    private func setupUI() {
        backgroundColor = .systemBackground
        addSubview(titleLabel)
        addSubview(authorRowView)
        addSubview(contentLabel)
        authorRowView.addSubview(avatarImageView)
        authorRowView.addSubview(subtitleLabel)

        let contentTopConstraint = contentLabel.topAnchor.constraint(equalTo: authorRowView.bottomAnchor, constant: 16)
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

            contentLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.horizontalInset),
            contentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.horizontalInset),
            contentTopConstraint,
            contentLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Layout.bottomInset)
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

    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

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
        bodyLabel.attributedText = nil
    }

    func configure(comment: Comment, baseURL: URL, maxImageWidth: CGFloat) {
        metaLabel.text = [
            comment.floorText,
            comment.authorName,
            comment.createdAtText
        ].compactMap(\.self).joined(separator: " · ")
        bodyLabel.attributedText = renderedAttributedText(
            html: comment.contentHTML,
            baseURL: baseURL,
            maxImageWidth: maxImageWidth
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
        cardView.addSubview(bodyLabel)

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

            bodyLabel.leadingAnchor.constraint(equalTo: metaLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: metaLabel.trailingAnchor),
            bodyLabel.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 8),
            bodyLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -Layout.cardInset),
            bodyLabel.bottomAnchor.constraint(greaterThanOrEqualTo: avatarImageView.bottomAnchor)
        ])
    }

    private func renderedAttributedText(html: String, baseURL: URL, maxImageWidth: CGFloat) -> NSAttributedString? {
        let blocks = HTMLContentRenderer().render(fragment: html, baseURL: baseURL, maxImageWidth: maxImageWidth)
        guard blocks.isEmpty == false else { return nil }

        let result = NSMutableAttributedString()
        for block in blocks {
            switch block {
            case .text(let attributedText):
                result.append(attributedText)
            case .imagePlaceholder(let url):
                result.append(NSAttributedString(string: url?.absoluteString ?? "[图片]"))
            case .unsupported(let reason):
                result.append(NSAttributedString(string: reason))
            }
        }

        return result.length > 0 ? result : nil
    }
}
