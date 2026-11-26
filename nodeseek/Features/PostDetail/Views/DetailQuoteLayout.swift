import UIKit

nonisolated enum DetailQuoteLayout {
    static let borderWidth: CGFloat = 3
    static let cornerRadius: CGFloat = 4
    static let blockSpacing: CGFloat = 8
    static let insets = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 10)

    static func contentWidth(_ width: CGFloat) -> CGFloat {
        max(1, width - borderWidth - insets.left - insets.right)
    }
}
