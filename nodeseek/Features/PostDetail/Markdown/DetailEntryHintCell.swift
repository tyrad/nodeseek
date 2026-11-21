import UIKit

final class DetailEntryHintCell: UICollectionViewCell {
    private let card = UIStackView()
    private let message = UILabel()
    private let button = UIButton(type: .system)
    var onOpen: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .systemBackground
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 8
        card.spacing = 10
        card.isLayoutMarginsRelativeArrangement = true
        card.directionalLayoutMargins = .init(top: 10, leading: 12, bottom: 10, trailing: 12)
        card.translatesAutoresizingMaskIntoConstraints = false
        message.numberOfLines = 0
        message.textColor = .secondaryLabel
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addTarget(self, action: #selector(openPost), for: .touchUpInside)
        card.addArrangedSubview(message)
        card.addArrangedSubview(button)
        contentView.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 34)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(page: Int, afterJump: Bool, traits: UITraitCollection) {
        let stacked = traits.preferredContentSizeCategory.isAccessibilityCategory
        card.axis = stacked ? .vertical : .horizontal
        card.alignment = stacked ? .leading : .center
        let font = UIFont.preferredFont(forTextStyle: .footnote, compatibleWith: traits)
        message.font = font
        message.text = String.localizedStringWithFormat(
            DetailListStrings.text(afterJump ? "entry-starts-at-page" : "entry-opened-on-page"), page
        )
        var style = UIButton.Configuration.filled()
        style.title = DetailListStrings.text(afterJump ? "entry-return-first" : "entry-open-full-post")
        style.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var result = incoming
            result.font = font
            return result
        }
        style.baseForegroundColor = .systemBackground
        style.baseBackgroundColor = .label
        style.cornerStyle = .fixed
        style.background.cornerRadius = 8
        style.contentInsets = .init(top: 7, leading: 10, bottom: 7, trailing: 10)
        button.configuration = style
    }

    func height(for width: CGFloat) -> CGFloat {
        let size = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        return ceil(contentView.systemLayoutSizeFitting(size, withHorizontalFittingPriority: .required,
                                                        verticalFittingPriority: .fittingSizeLevel).height)
    }

    @objc private func openPost() { onOpen?() }
}
