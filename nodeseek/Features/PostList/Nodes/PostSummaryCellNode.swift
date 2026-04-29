//
//  PostSummaryCellNode.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import AsyncDisplayKit
import UIKit

final class PostSummaryCellNode: ASCellNode {

    private enum Layout {
        static let horizontalSpacing: CGFloat = 12
        static let verticalSpacing: CGFloat = 5
        static let avatarSize: CGFloat = 58
        static let contentInset = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 12)
    }

    private let post: PostSummary
    private let avatarLoader = AvatarImageLoader.shared
    private var hasRequestedAvatar = false

    private lazy var avatarNode: ASDisplayNode = {
        let node = ASDisplayNode(viewBlock: { [weak self] in
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.layer.cornerRadius = 12
            imageView.layer.masksToBounds = true
            imageView.backgroundColor = .systemGray5
            self?.avatarImageView = imageView
            return imageView
        })
        node.style.preferredSize = CGSize(width: Layout.avatarSize, height: Layout.avatarSize)
        return node
    }()

    private let titleNode = ASTextNode()
    private let metadataNode = ASTextNode()
    private weak var avatarImageView: UIImageView?

    init(post: PostSummary) {
        self.post = post
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        backgroundColor = .clear
        configureText()
    }

    override func didLoad() {
        super.didLoad()
        requestAvatarIfNeeded()
    }

    override func didEnterDisplayState() {
        super.didEnterDisplayState()
        requestAvatarIfNeeded()
    }

    override func didExitDisplayState() {
        super.didExitDisplayState()
        cancelAvatarLoad()
        hasRequestedAvatar = false
    }

    deinit {
        cancelAvatarLoad()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        titleNode.style.flexShrink = 1
        metadataNode.style.flexShrink = 1

        let textStack = ASStackLayoutSpec.vertical()
        textStack.spacing = Layout.verticalSpacing
        textStack.children = [titleNode, metadataNode]
        textStack.style.flexGrow = 1
        textStack.style.flexShrink = 1

        let contentStack = ASStackLayoutSpec.horizontal()
        contentStack.spacing = Layout.horizontalSpacing
        contentStack.alignItems = .start
        contentStack.children = [avatarNode, textStack]

        return ASInsetLayoutSpec(insets: Layout.contentInset, child: contentStack)
    }

    private func configureText() {
        titleNode.maximumNumberOfLines = PostSummaryCellStyle.titleMaximumNumberOfLines
        titleNode.truncationMode = .byTruncatingTail
        titleNode.attributedText = Self.titleAttributedText(for: post)

        metadataNode.maximumNumberOfLines = PostSummaryCellStyle.metadataMaximumNumberOfLines
        metadataNode.truncationMode = .byTruncatingTail
        metadataNode.attributedText = Self.metadataAttributedText(for: post)
    }

    private func requestAvatarIfNeeded() {
        guard !hasRequestedAvatar else { return }
        guard let avatarImageView else { return }
        hasRequestedAvatar = true
        avatarLoader.loadAvatar(into: avatarImageView, postID: post.id, avatarURL: post.avatarURL)
    }

    private func cancelAvatarLoad() {
        guard let avatarImageView else { return }
        avatarLoader.cancel(on: avatarImageView)
    }

    static func metadataAttributedText(for post: PostSummary) -> NSAttributedString {
        let font = PostSummaryCellStyle.metadataFont
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.secondaryLabel
        ]
        let metadata = NSMutableAttributedString()

        func appendSeparatorIfNeeded() {
            guard metadata.length > 0 else { return }
            metadata.append(NSAttributedString(string: "  ", attributes: attributes))
        }

        appendSeparatorIfNeeded()
        metadata.append(NSAttributedString(string: post.authorName, attributes: attributes))

        appendSeparatorIfNeeded()
        metadata.append(metricAttributedText(
            systemName: "eye",
            value: post.viewCount,
            font: font,
            attributes: attributes
        ))

        appendSeparatorIfNeeded()
        metadata.append(metricAttributedText(
            systemName: "bubble.left",
            value: post.replyCount,
            font: font,
            attributes: attributes
        ))

        if let lastActive = post.lastActivityText?.trimmingCharacters(in: .whitespacesAndNewlines), !lastActive.isEmpty {
            appendSeparatorIfNeeded()
            metadata.append(NSAttributedString(string: lastActive, attributes: attributes))
        }

        return metadata
    }

    static func titleAttributedText(for post: PostSummary) -> NSAttributedString {
        let font = PostSummaryCellStyle.titleFont
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.label
        ]
        let title = NSMutableAttributedString()
        let configuration = UIImage.SymbolConfiguration(font: font, scale: .small)

        if post.isPinned {
            appendSymbol(
                "pin.fill",
                tintColor: .secondaryLabel,
                font: font,
                rotationAngle: .pi / 4,
                to: title
            )
            title.append(NSAttributedString(string: " ", attributes: attributes))
        }

        title.append(NSAttributedString(string: post.title, attributes: attributes))

        guard post.isLocked else {
            return title
        }

        title.append(NSAttributedString(string: " ", attributes: attributes))

        appendSymbol(
            "lock.fill",
            tintColor: .systemRed,
            font: font,
            configuration: configuration,
            to: title
        )

        return title
    }

    private static func appendSymbol(
        _ systemName: String,
        tintColor: UIColor,
        font: UIFont,
        configuration: UIImage.SymbolConfiguration? = nil,
        rotationAngle: CGFloat = 0,
        to text: NSMutableAttributedString
    ) {
        let configuration = configuration ?? UIImage.SymbolConfiguration(font: font, scale: .small)

        guard let image = UIImage(systemName: systemName, withConfiguration: configuration)?
            .withTintColor(tintColor, renderingMode: .alwaysOriginal) else {
            return
        }

        let displayImage = rotationAngle == 0 ? image : rotated(image, by: rotationAngle)
        let attachment = NSTextAttachment(image: displayImage)
        attachment.bounds = CGRect(
            x: 0,
            y: (font.capHeight - displayImage.size.height) / 2,
            width: displayImage.size.width,
            height: displayImage.size.height
        )
        text.append(NSAttributedString(attachment: attachment))
    }

    private static func rotated(_ image: UIImage, by angle: CGFloat) -> UIImage {
        let sourceSize = image.size
        let rotatedRect = CGRect(origin: .zero, size: sourceSize).applying(CGAffineTransform(rotationAngle: angle))
        let canvasSize = CGSize(
            width: ceil(abs(rotatedRect.width)),
            height: ceil(abs(rotatedRect.height))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale

        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { context in
            let cgContext = context.cgContext
            cgContext.translateBy(x: canvasSize.width / 2, y: canvasSize.height / 2)
            cgContext.rotate(by: angle)
            image.draw(in: CGRect(
                x: -sourceSize.width / 2,
                y: -sourceSize.height / 2,
                width: sourceSize.width,
                height: sourceSize.height
            ))
        }
    }

    private static func metricAttributedText(
        systemName: String,
        value: Int,
        font: UIFont,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let text = NSMutableAttributedString()
        let configuration = UIImage.SymbolConfiguration(font: font, scale: .small)

        if UIImage(systemName: systemName, withConfiguration: configuration) != nil {
            appendSymbol(
                systemName,
                tintColor: .secondaryLabel,
                font: font,
                configuration: configuration,
                to: text
            )
            text.append(NSAttributedString(string: " ", attributes: attributes))
        }

        text.append(NSAttributedString(string: "\(value)", attributes: attributes))
        return text
    }
}

enum PostSummaryCellStyle {
    static let titleMaximumNumberOfLines: UInt = 2
    static let metadataMaximumNumberOfLines: UInt = 1
    static let titleFont = UIFont.systemFont(ofSize: 19, weight: .semibold)
    static let metadataFont = UIFont.systemFont(ofSize: 14, weight: .regular)
}
