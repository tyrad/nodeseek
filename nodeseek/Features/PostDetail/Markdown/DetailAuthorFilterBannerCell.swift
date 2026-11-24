import UIKit

/// 「只看 TA」筛选条：图标、说明和反色的「查看全部」按钮。
final class DetailAuthorFilterBannerCell: UICollectionViewCell {
    private let card = UIStackView()
    private let icon = UIImageView()
    private let message = UILabel()
    private let button = UIButton(type: .system)
    var onClear: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .systemBackground
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 8
        card.spacing = 10
        card.alignment = .center
        card.isLayoutMarginsRelativeArrangement = true
        card.directionalLayoutMargins = .init(top: 10, leading: 12, bottom: 10, trailing: 12)
        card.translatesAutoresizingMaskIntoConstraints = false
        icon.contentMode = .scaleAspectFit
        icon.tintColor = .secondaryLabel
        icon.setContentHuggingPriority(.required, for: .horizontal)
        message.textColor = .label
        message.adjustsFontForContentSizeCategory = true
        message.lineBreakMode = .byTruncatingTail
        message.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = .label
        config.baseForegroundColor = .systemBackground
        config.cornerStyle = .fixed
        config.background.cornerRadius = 8
        config.contentInsets = .init(top: 7, leading: 10, bottom: 7, trailing: 10)
        button.configuration = config
        button.accessibilityLabel = DetailListStrings.text("all")
        button.accessibilityIdentifier = "detail-author-filter-clear"
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addAction(UIAction { [weak self] _ in self?.onClear?() }, for: .touchUpInside)
        [icon, message, button].forEach(card.addArrangedSubview)
        contentView.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 34)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String?) {
        let font = UIFont.preferredFont(forTextStyle: .footnote)
        icon.image = UIImage(systemName: "line.3.horizontal.decrease.circle", withConfiguration: UIImage.SymbolConfiguration(font: font))
        message.font = font
        message.text = text
        button.configuration?.attributedTitle = AttributedString(DetailListStrings.text("show-all"), attributes: AttributeContainer([.font: font]))
    }

    func height(for width: CGFloat) -> CGFloat {
        bounds.size.width = width
        return ceil(contentView.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                        withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
    }
}
