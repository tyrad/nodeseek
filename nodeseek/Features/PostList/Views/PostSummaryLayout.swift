//
//  PostSummaryLayout.swift
//  nodeseek
//
//  Created by Codex on 2026/10/31.
//

import UIKit

/// 帖子行的排版结果：拼好的文字、各元素位置和行高。
/// 只做纯计算，可以在后台线程提前生成，主线程滚动时直接取用。
struct PostSummaryLayout: @unchecked Sendable {
    /// 影响排版结果的外部条件，任一变化都要重新计算。
    struct Context: Equatable, @unchecked Sendable {
        let width: CGFloat
        let pointOffset: CGFloat
        let userInterfaceStyle: UIUserInterfaceStyle
        let displayScale: CGFloat
        let specialFollowRules: [SpecialFollowKeywordRule]

        @MainActor
        static func current(width: CGFloat, traitCollection: UITraitCollection) -> Context {
            Context(
                width: width,
                pointOffset: AppTextSizeSettings.shared.pointOffset,
                userInterfaceStyle: traitCollection.userInterfaceStyle,
                displayScale: traitCollection.displayScale > 0 ? traitCollection.displayScale : UIScreen.main.scale,
                specialFollowRules: SpecialFollowKeywordStore.shared.rules
            )
        }
    }

    enum Metrics {
        static let verticalSpacing: CGFloat = 5
        static let contentInset = UIEdgeInsets(
            top: PostListCellStyle.Layout.verticalContentInset,
            left: 16,
            bottom: PostListCellStyle.Layout.verticalContentInset,
            right: 12
        )
    }

    let item: PostListItem
    let context: Context
    let title: NSAttributedString
    let metadata: NSAttributedString
    let avatarFrame: CGRect?
    let titleFrame: CGRect
    let metadataFrame: CGRect
    /// 行内容高度，不含分割线。
    let height: CGFloat

    func matches(_ item: PostListItem, context: Context) -> Bool {
        self.item == item && self.context == context
    }

    static func make(item: PostListItem, context: Context) -> PostSummaryLayout {
        // 符号附件按当前外观栅格化；后台线程没有界面外观，需要显式指定。
        let traits = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: context.userInterfaceStyle),
            UITraitCollection(displayScale: context.displayScale)
        ])
        var title = NSAttributedString()
        var metadata = NSAttributedString()
        traits.performAsCurrent {
            title = PostSummaryText.titleAttributedText(
                for: item.post,
                isVisited: item.isVisited,
                specialFollowRules: context.specialFollowRules
            )
            metadata = PostSummaryText.metadataAttributedText(
                for: item.post,
                specialFollowRules: context.specialFollowRules
            )
        }

        let inset = Metrics.contentInset
        let hasAvatar = AuthorDisplayPolicy.isDisplayable(item.post.authorName)
        let avatarSize = PostListCellStyle.Avatar.size
        let avatarFrame = hasAvatar
            ? CGRect(x: inset.left, y: inset.top, width: avatarSize, height: avatarSize)
            : nil
        let textX = avatarFrame.map { $0.maxX + PostListCellStyle.Layout.horizontalSpacing } ?? inset.left
        let textWidth = max(0, context.width - textX - inset.right)

        let titleHeight = pixelCeil(
            measurable(title).boundingRect(
                with: CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).height,
            scale: context.displayScale
        )
        // 元信息只显示一行，按不限宽测出单行高度。
        let metadataHeight = pixelCeil(
            measurable(metadata).boundingRect(
                with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).height,
            scale: context.displayScale
        )

        let titleFrame = CGRect(x: textX, y: inset.top, width: textWidth, height: titleHeight)
        let metadataFrame = CGRect(
            x: textX,
            y: titleFrame.maxY + Metrics.verticalSpacing,
            width: textWidth,
            height: metadataHeight
        )
        let contentBottom = max(avatarFrame?.maxY ?? 0, metadataFrame.maxY)

        return PostSummaryLayout(
            item: item,
            context: context,
            title: title,
            metadata: metadata,
            avatarFrame: avatarFrame,
            titleFrame: titleFrame,
            metadataFrame: metadataFrame,
            height: contentBottom + inset.bottom
        )
    }

    /// 符号附件片段没有字体属性，UILabel 会用默认 17pt 字体参与行高计算；
    /// 测量时补上同样的默认字体，保证算出的高度和 UILabel 实际显示一致。
    private static func measurable(_ text: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: text)
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            if value == nil {
                mutable.addAttribute(.font, value: labelDefaultFont, range: range)
            }
        }
        return mutable
    }

    private static let labelDefaultFont = UIFont.systemFont(ofSize: 17)

    private static func pixelCeil(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        ceil(value * scale) / scale
    }
}
