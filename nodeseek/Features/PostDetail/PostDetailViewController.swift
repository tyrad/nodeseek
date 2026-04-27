//
//  PostDetailViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit

class PostDetailViewController: UIViewController {
    private enum Layout {
        static let screenHorizontalInset: CGFloat = 20
        static let commentInset: CGFloat = 12
        static let avatarSize: CGFloat = 40
        static let avatarCornerRadius: CGFloat = 8
        static let avatarSpacing: CGFloat = 12
    }
    
    // MARK: - Properties
    private let presenter: PostDetailPresenterProtocol
    private let contentRenderer = HTMLContentRenderer()
    private let avatarLoader = AvatarImageLoader.shared
    private let baseURL = URL(string: "https://www.nodeseek.com")!
    
    // MARK: - UI Components
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private let contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .title2)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let authorAvatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .systemGray5
        imageView.layer.cornerRadius = Layout.avatarCornerRadius
        imageView.layer.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let authorStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Layout.avatarSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    // MARK: - Initialization
    init(presenter: PostDetailPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        presenter.viewDidLoad()
    }
    
    // MARK: - Setup UI
    private func setupUI() {
        view.backgroundColor = .systemBackground
        view.addSubview(scrollView)
        view.addSubview(loadingIndicator)
        scrollView.addSubview(contentStackView)
        contentStackView.addArrangedSubview(titleLabel)
        contentStackView.addArrangedSubview(authorStackView)
        authorStackView.addArrangedSubview(authorAvatarImageView)
        authorStackView.addArrangedSubview(subtitleLabel)
        
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: Layout.screenHorizontalInset),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -Layout.screenHorizontalInset),
            contentStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -(Layout.screenHorizontalInset * 2)),

            authorAvatarImageView.widthAnchor.constraint(equalToConstant: Layout.avatarSize),
            authorAvatarImageView.heightAnchor.constraint(equalToConstant: Layout.avatarSize),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}

// MARK: - View Protocol
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
        self.title = "详情"
        titleLabel.text = detail.title
        subtitleLabel.text = [detail.authorName, detail.metadataText].compactMap(\.self).joined(separator: " · ")
        avatarLoader.loadAvatar(into: authorAvatarImageView, postID: detail.id, avatarURL: detail.avatarURL)

        resetDetailContent()
        appendContentBlock(html: detail.contentHTML, maxImageWidth: availableContentWidth)

        if detail.comments.isEmpty == false {
            contentStackView.addArrangedSubview(makeDivider())
            contentStackView.addArrangedSubview(makeCommentCountLabel(count: detail.comments.count))
        }

        for comment in detail.comments {
            contentStackView.addArrangedSubview(makeCommentView(comment))
        }
    }

    private func resetDetailContent() {
        while contentStackView.arrangedSubviews.count > 2 {
            let view = contentStackView.arrangedSubviews[2]
            contentStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func appendContentBlock(html: String, maxImageWidth: CGFloat) {
        let blocks = contentRenderer.render(fragment: html, baseURL: baseURL, maxImageWidth: maxImageWidth)
        guard blocks.isEmpty == false else { return }

        for block in blocks {
            switch block {
            case .text(let attributedText):
                contentStackView.addArrangedSubview(makeContentLabel(attributedText))
            case .imagePlaceholder(let url):
                contentStackView.addArrangedSubview(makePlainLabel(url?.absoluteString ?? "[图片]"))
            case .unsupported(let reason):
                contentStackView.addArrangedSubview(makePlainLabel(reason))
            }
        }
    }

    private func makeCommentView(_ comment: Comment) -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .top
        stack.spacing = Layout.avatarSpacing
        stack.layoutMargins = UIEdgeInsets(
            top: Layout.commentInset,
            left: Layout.commentInset,
            bottom: Layout.commentInset,
            right: Layout.commentInset
        )
        stack.isLayoutMarginsRelativeArrangement = true
        stack.backgroundColor = .secondarySystemBackground
        stack.layer.cornerRadius = 8

        let avatarImageView = makeAvatarImageView()
        avatarLoader.loadAvatar(into: avatarImageView, postID: comment.id, avatarURL: comment.avatarURL)
        stack.addArrangedSubview(avatarImageView)

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 8
        stack.addArrangedSubview(contentStack)

        let metaLabel = UILabel()
        metaLabel.font = .preferredFont(forTextStyle: .footnote)
        metaLabel.textColor = .secondaryLabel
        metaLabel.numberOfLines = 0
        metaLabel.text = [
            comment.floorText,
            comment.authorName,
            comment.createdAtText
        ].compactMap(\.self).joined(separator: " · ")
        contentStack.addArrangedSubview(metaLabel)

        let blocks = contentRenderer.render(
            fragment: comment.contentHTML,
            baseURL: baseURL,
            maxImageWidth: availableCommentContentWidth
        )
        for block in blocks {
            switch block {
            case .text(let attributedText):
                contentStack.addArrangedSubview(makeContentLabel(attributedText))
            case .imagePlaceholder(let url):
                contentStack.addArrangedSubview(makePlainLabel(url?.absoluteString ?? "[图片]"))
            case .unsupported(let reason):
                contentStack.addArrangedSubview(makePlainLabel(reason))
            }
        }

        return stack
    }

    private func makeAvatarImageView() -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .systemGray5
        imageView.layer.cornerRadius = Layout.avatarCornerRadius
        imageView.layer.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: Layout.avatarSize),
            imageView.heightAnchor.constraint(equalToConstant: Layout.avatarSize)
        ])
        return imageView
    }

    private func makeContentLabel(_ attributedText: NSAttributedString) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.attributedText = attributedText
        return label
    }

    private func makePlainLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        label.numberOfLines = 0
        label.text = text
        return label
    }

    private func makeDivider() -> UIView {
        let view = UIView()
        view.backgroundColor = .separator
        view.heightAnchor.constraint(equalToConstant: 1 / max(traitCollection.displayScale, 1)).isActive = true
        return view
    }

    private func makeCommentCountLabel(count: Int) -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .label
        label.text = "回复 \(count)"
        return label
    }

    private var availableContentWidth: CGFloat {
        let width = view.bounds.width > 0 ? view.bounds.width : 320
        return max(width - Layout.screenHorizontalInset * 2, 1)
    }

    private var availableCommentContentWidth: CGFloat {
        max(availableContentWidth - Layout.commentInset * 2 - Layout.avatarSize - Layout.avatarSpacing, 1)
    }
}
