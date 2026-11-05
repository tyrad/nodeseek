import UIKit

/// 夜间阅读降低明暗反差，白天继续使用系统动态颜色。
enum ReadingColors {
    // 列表未读标题比正文更亮，保留与已读标题的区分。
    static let unreadTitle = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(named: "ReadingUnreadTitle")!.resolvedColor(with: traits)
            : UIColor.label.resolvedColor(with: traits)
    }

    static let text = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(named: "ReadingText")!.resolvedColor(with: traits)
            : UIColor.label.resolvedColor(with: traits)
    }
}
