import UIKit

@MainActor
final class UserCreditCell: UITableViewCell {
    private let reasonLabel = UILabel()
    private let changeLabel = UILabel()
    private let timeLabel = UILabel()
    private let balanceLabel = UILabel()
    private let stack = UIStackView()
    private let skeleton = UIView()
    private var contentConstraints: [NSLayoutConstraint] = []
    private var skeletonConstraints: [NSLayoutConstraint] = []

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .secondarySystemGroupedBackground
        reasonLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 16, weight: .semibold))
        changeLabel.font = UIFontMetrics(forTextStyle: .title3).scaledFont(for: .monospacedDigitSystemFont(ofSize: 20, weight: .semibold))
        [timeLabel, balanceLabel].forEach {
            $0.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12))
            $0.textColor = .secondaryLabel
        }
        [reasonLabel, changeLabel].forEach { $0.textColor = .label }
        [reasonLabel, changeLabel, timeLabel, balanceLabel].forEach {
            $0.adjustsFontForContentSizeCategory = true
            $0.numberOfLines = 0
        }
        changeLabel.textAlignment = .right
        balanceLabel.textAlignment = .right
        changeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let top = UIStackView(arrangedSubviews: [reasonLabel, changeLabel])
        top.alignment = .firstBaseline
        top.spacing = 12
        let bottom = UIStackView(arrangedSubviews: [timeLabel, balanceLabel])
        bottom.alignment = .firstBaseline
        bottom.spacing = 8
        stack.axis = .vertical
        stack.spacing = 8
        [top, bottom].forEach { stack.addArrangedSubview($0) }
        stack.translatesAutoresizingMaskIntoConstraints = false
        skeleton.translatesAutoresizingMaskIntoConstraints = false
        skeleton.backgroundColor = .systemGray5
        skeleton.layer.cornerRadius = 12
        skeleton.layer.cornerCurve = .continuous
        skeleton.isHidden = true
        contentView.addSubview(stack)
        contentView.addSubview(skeleton)
        contentConstraints = [
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
        ]
        skeletonConstraints = [
            skeleton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            skeleton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            skeleton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            skeleton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            skeleton.heightAnchor.constraint(equalToConstant: 54)
        ]
        NSLayoutConstraint.activate(contentConstraints)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(record: UserCreditRecord?) {
        let loading = record == nil
        isUserInteractionEnabled = false
        accessibilityElementsHidden = loading
        stack.isHidden = loading
        skeleton.isHidden = !loading
        NSLayoutConstraint.deactivate(loading ? contentConstraints : skeletonConstraints)
        NSLayoutConstraint.activate(loading ? skeletonConstraints : contentConstraints)
        guard let record else { return }
        reasonLabel.text = record.reason
        changeLabel.text = record.changeText
        balanceLabel.text = "余额 \(record.balance)"
        timeLabel.text = Self.timeText(record.createdAt)
    }

    private static func timeText(_ raw: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = iso.date(from: raw)
        if date == nil {
            iso.formatOptions = [.withInternetDateTime]
            date = iso.date(from: raw)
        }
        guard let date else { return raw }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }
}
