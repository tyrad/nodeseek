import UIKit

enum PostDetailContentLayout {
    static let horizontalInset: CGFloat = 16
    static let commentTopInset: CGFloat = 12
    static let commentBottomInset: CGFloat = 12
    static let avatarSize: CGFloat = 40
    static let avatarCornerRadius: CGFloat = 8
    static let avatarSpacing: CGFloat = 10
    static let reactionActionHeight: CGFloat = 30
    static let reactionActionMinWidth: CGFloat = 48
    static let reactionIconReservedWidth: CGFloat = 16
    static let reactionTitleSpacing: CGFloat = 3
    static let reactionHorizontalWidthPadding: CGFloat = 16
    static let reactionIconOnlyWidth: CGFloat = 36
    static let reactionActionSpacing: CGFloat = 4
    static let reactionSymbolPointSize: CGFloat = 14
    static let inactiveReactionAlpha: CGFloat = 0.62
    static let reactionContentEdgeInsets = UIEdgeInsets(top: 5, left: 7, bottom: 5, right: 7)

    static func reactionCountText(_ count: Int) -> String {
        let safeCount = max(0, count)
        if safeCount < 10_000 {
            return "\(safeCount)"
        }
        if safeCount < 100_000_000 {
            return compactCountText(safeCount, divisor: 10_000, unit: "万")
        }
        return compactCountText(safeCount, divisor: 100_000_000, unit: "亿")
    }

    private static func compactCountText(_ count: Int, divisor: Int, unit: String) -> String {
        let integerPart = count / divisor
        let decimalPart = (count % divisor) * 10 / divisor
        if integerPart >= 100 || decimalPart == 0 {
            return "\(integerPart)\(unit)"
        }
        return "\(integerPart).\(decimalPart)\(unit)"
    }
}
