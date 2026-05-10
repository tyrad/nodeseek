//
//  PostListSortToggleButton.swift
//  nodeseek
//

import UIKit

final class PostListSortToggleButton: UIButton {
    static let collapsedWidth: CGFloat = 58
    static let height: CGFloat = 42
    static let collapsedTrailing: CGFloat = 12
    static let expandedTrailing: CGFloat = 0
    static let transitionDuration: TimeInterval = 0.34
    static let transitionDamping: CGFloat = 0.68
    static let transitionVelocity: CGFloat = 0.6

    private enum Layout {
        static let minimumExpandedWidth: CGFloat = 168
        static let cornerRadius: CGFloat = 14
        static let collapsedAlpha: CGFloat = 0.62
        static let expandedAlpha: CGFloat = 1
        static let jellyAnimationKey = "sortToggleJelly"
        static let jellyDuration: TimeInterval = 0.42
        static let jellyKeyTimes: [NSNumber] = [0, 0.28, 0.58, 0.82, 1]
        static let jellyTimingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeOut)
        ]
        static let expandedImagePadding: CGFloat = 6
        static let expandedInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 16)
        static let collapsedInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        static let titleFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
        static let titleAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = titleFont
            return outgoing
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func expandedWidth(for title: String) -> CGFloat {
        let titleWidth = ceil((title as NSString).size(withAttributes: [.font: Layout.titleFont]).width)
        let imageWidth: CGFloat = 18
        let measuredWidth = Layout.expandedInsets.leading
            + imageWidth
            + Layout.expandedImagePadding
            + titleWidth
            + Layout.expandedInsets.trailing
        return max(Layout.minimumExpandedWidth, ceil(measuredWidth))
    }

    func apply(sortMode: PostListSortMode, expanded: Bool) {
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        let image = UIImage(systemName: sortMode.symbolName, withConfiguration: symbolConfiguration)
        let title = sortMode.accessibilityTitle
        setImage(image, for: .normal)
        setTitle(expanded ? title : nil, for: .normal)
        configureTitleLabel()

        var configuration = configuration ?? UIButton.Configuration.plain()
        configuration.baseForegroundColor = .systemBackground
        configuration.image = image
        configuration.title = expanded ? title : nil
        configuration.imagePadding = expanded ? Layout.expandedImagePadding : 0
        configuration.contentInsets = expanded ? Layout.expandedInsets : Layout.collapsedInsets
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.titleTextAttributesTransformer = expanded ? Layout.titleAttributesTransformer : nil
        self.configuration = configuration
        backgroundColor = .label
        tintColor = .systemBackground
        layer.borderColor = UIColor.separator.cgColor
        accessibilityLabel = title
    }

    func applyAlpha(expanded: Bool) {
        alpha = expanded ? Layout.expandedAlpha : Layout.collapsedAlpha
    }

    func applyJellyAnimation(expanded: Bool) {
        layer.removeAnimation(forKey: Layout.jellyAnimationKey)

        let scaleX = CAKeyframeAnimation(keyPath: "transform.scale.x")
        scaleX.values = expanded
            ? [1, 1.08, 0.98, 1.02, 1]
            : [1, 0.94, 1.04, 0.99, 1]
        scaleX.keyTimes = Layout.jellyKeyTimes
        scaleX.timingFunctions = Layout.jellyTimingFunctions

        let scaleY = CAKeyframeAnimation(keyPath: "transform.scale.y")
        scaleY.values = expanded
            ? [1, 0.96, 1.03, 0.99, 1]
            : [1, 1.04, 0.97, 1.01, 1]
        scaleY.keyTimes = Layout.jellyKeyTimes
        scaleY.timingFunctions = Layout.jellyTimingFunctions

        let animationGroup = CAAnimationGroup()
        animationGroup.animations = [scaleX, scaleY]
        animationGroup.duration = Layout.jellyDuration
        animationGroup.isRemovedOnCompletion = true
        layer.add(animationGroup, forKey: Layout.jellyAnimationKey)
    }

    private func configureAppearance() {
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .systemBackground
        configuration.imagePadding = 0
        configuration.contentInsets = Layout.collapsedInsets
        configuration.titleLineBreakMode = .byTruncatingTail
        self.configuration = configuration
        accessibilityIdentifier = "post-list-sort-toggle"
        tintColor = .systemBackground
        setTitleColor(.systemBackground, for: .normal)
        configureTitleLabel()
        backgroundColor = .label
        layer.cornerRadius = Layout.cornerRadius
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 5)
        translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureTitleLabel() {
        titleLabel?.font = Layout.titleFont
        titleLabel?.numberOfLines = 1
        titleLabel?.lineBreakMode = .byTruncatingTail
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.9
    }
}

private extension PostListSortMode {
    var symbolName: String {
        switch self {
        case .postTime:
            return "line.3.horizontal.decrease.circle.fill"
        case .replyTime:
            return "arrow.up.arrow.down.circle.fill"
        }
    }
}
