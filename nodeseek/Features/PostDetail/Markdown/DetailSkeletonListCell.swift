import UIKit

/// 首次加载时的占位楼层，尺寸与 `PostDetailSkeletonCellNode` 的实际显示一致，切换列表实现时首屏观感不变。
/// Texture 版在纵向栈里未应用宽度比例，文字条实际铺满整行，这里按实际效果还原。
final class DetailSkeletonListCell: UICollectionViewCell {
    enum Kind {
        case header
        case comment
    }

    private enum Layout {
        static let horizontalInset: CGFloat = 20
        static let commentHorizontalInset: CGFloat = 12
        static let verticalInset: CGFloat = 10
        static let cardInset: CGFloat = 12
        static let avatarSize: CGFloat = 40
        static let avatarCornerRadius: CGFloat = 8
        static let avatarSpacing: CGFloat = 12
        static let lineSpacing: CGFloat = 10
        static let titleHeight: CGFloat = 22
        static let metaHeight: CGFloat = 14
        static let bodyHeight: CGFloat = 16
        static let imageHeight: CGFloat = 180
    }

    static func height(for kind: Kind) -> CGFloat {
        switch kind {
        case .header:
            let lines = Layout.titleHeight + Layout.avatarSize + 2 * Layout.bodyHeight + Layout.imageHeight
            return 2 * Layout.horizontalInset + lines + 4 * Layout.lineSpacing
        case .comment:
            let text = Layout.metaHeight + 3 * Layout.bodyHeight + 3 * Layout.lineSpacing
            return 2 * Layout.verticalInset + 2 * Layout.cardInset + max(Layout.avatarSize, text)
        }
    }

    private let card = UIView()
    private var placeholders: [UIView] = []
    private var kind: Kind?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .systemBackground
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ kind: Kind) {
        accessibilityIdentifier = kind == .header ? "post-detail-skeleton-header" : "post-detail-skeleton-comment"
        guard self.kind != kind else { return }
        self.kind = kind
        contentView.subviews.forEach { $0.removeFromSuperview() }
        placeholders.removeAll()
        kind == .header ? buildHeader() : buildComment()
        startPulse()
    }

    private func placeholder(height: CGFloat, radius: CGFloat) -> UIView {
        let view = UIView()
        view.backgroundColor = .systemGray5
        view.layer.cornerRadius = radius
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        placeholders.append(view)
        return view
    }

    private func avatar() -> UIView {
        let view = placeholder(height: Layout.avatarSize, radius: Layout.avatarCornerRadius)
        view.widthAnchor.constraint(equalToConstant: Layout.avatarSize).isActive = true
        return view
    }

    private func column(_ items: [(UIView, CGFloat)], in container: UIView) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = Layout.lineSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        for (view, fraction) in items {
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: fraction).isActive = true
        }
        return stack
    }

    private func buildHeader() {
        let meta = placeholder(height: Layout.metaHeight, radius: 4)
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let avatar = avatar()
        row.addSubview(avatar)
        row.addSubview(meta)
        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            avatar.topAnchor.constraint(equalTo: row.topAnchor),
            avatar.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            meta.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: Layout.avatarSpacing),
            meta.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
            meta.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.48)
        ])
        let stack = column([
            (placeholder(height: Layout.titleHeight, radius: 6), 1),
            (row, 1),
            (placeholder(height: Layout.bodyHeight, radius: 5), 1),
            (placeholder(height: Layout.bodyHeight, radius: 5), 1),
            (placeholder(height: Layout.imageHeight, radius: 8), 1)
        ], in: contentView)
        let inset = Layout.horizontalInset
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -inset),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: inset)
        ])
    }

    private func buildComment() {
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 8
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        let avatar = avatar()
        card.addSubview(avatar)
        let text = column([
            (placeholder(height: Layout.metaHeight, radius: 4), 1),
            (placeholder(height: Layout.bodyHeight, radius: 5), 1),
            (placeholder(height: Layout.bodyHeight, radius: 5), 1),
            (placeholder(height: Layout.bodyHeight, radius: 5), 1)
        ], in: card)
        let inset = Layout.cardInset
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Layout.commentHorizontalInset),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Layout.commentHorizontalInset),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Layout.verticalInset),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Layout.verticalInset),
            avatar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: inset),
            avatar.topAnchor.constraint(equalTo: card.topAnchor, constant: inset),
            text.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: Layout.avatarSpacing),
            text.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -inset),
            text.topAnchor.constraint(equalTo: card.topAnchor, constant: inset)
        ])
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        window == nil ? stopPulse() : startPulse()
    }

    private func startPulse() {
        guard window != nil else { return }
        for view in placeholders where view.layer.animation(forKey: "skeleton_pulse") == nil {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 1.0
            animation.toValue = 0.45
            animation.duration = 0.8
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            view.layer.add(animation, forKey: "skeleton_pulse")
        }
    }

    private func stopPulse() {
        placeholders.forEach { $0.layer.removeAnimation(forKey: "skeleton_pulse") }
    }
}
