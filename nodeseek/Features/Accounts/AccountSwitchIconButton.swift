//
//  AccountSwitchIconButton.swift
//  nodeseek
//

import UIKit

/// 账号卡片右侧的极细描边胶囊切换按钮（「切换 ⇅」）。「我的」资料卡和侧边栏账号头共用，保证两种布局观感一致。
final class AccountSwitchIconButton: UIButton {
    private static let minimumHitSize: CGFloat = 44
    private static let minimumEdgeExpansion: CGFloat = 6

    init(accessibilityIdentifier: String) {
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.plain()
        configuration.title = AccountsL10n.text("切换")
        configuration.titleLineBreakMode = .byClipping
        configuration.image = UIImage(systemName: "chevron.up.chevron.down")
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 3
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        configuration.baseForegroundColor = .secondaryLabel
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 9)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
                for: .systemFont(ofSize: 12, weight: .medium),
                maximumPointSize: 15
            )
            return outgoing
        }
        var background = UIBackgroundConfiguration.clear()
        background.strokeColor = .separator
        background.strokeWidth = 0.75
        configuration.background = background

        self.configuration = configuration
        self.accessibilityIdentifier = accessibilityIdentifier
        accessibilityLabel = AccountsL10n.text("切换账号")
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 视觉保持轻量细胶囊，点击热区至少扩到 44pt 且外沿至少留 6pt 容差。
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isHidden == false, isUserInteractionEnabled, alpha > 0.01 else { return false }
        let dx = min(-Self.minimumEdgeExpansion, (bounds.width - Self.minimumHitSize) / 2)
        let dy = min(-Self.minimumEdgeExpansion, (bounds.height - Self.minimumHitSize) / 2)
        return bounds.insetBy(dx: dx, dy: dy).contains(point)
    }

    /// 已登录时一直显示（也是「添加账号」入口）；游客只在本机有已保存账号时显示。
    static func shouldShow(isLoggedIn: Bool, hasSavedAccounts: Bool) -> Bool {
        isLoggedIn || hasSavedAccounts
    }
}
