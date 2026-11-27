import UIKit

/// 网页正文中的星辰收款卡。卡面和流水分别响应点按。
final class DetailStardustView: UIStackView {
    private let receipt: StardustReceipt
    private let open: (URL) -> Void
    private let loadStatus: (StardustReceipt) async throws -> StardustReceiptStatus?
    private let card = UIButton(type: .custom)
    private let footer = UIButton(type: .system)
    private let gradient = CAGradientLayer()
    private var statusTask: Task<Void, Never>?
    private var retry = false

    init(receipt: StardustReceipt, open: @escaping (URL) -> Void,
         loadStatus: @escaping (StardustReceipt) async throws -> StardustReceiptStatus? = StardustReceiptStatus.load) {
        self.receipt = receipt
        self.open = open
        self.loadStatus = loadStatus
        super.init(frame: .zero)
        axis = .vertical
        alignment = .center
        configureCard()
        footer.accessibilityIdentifier = "stardust-ledger"
        footer.titleLabel?.numberOfLines = 0
        footer.titleLabel?.textAlignment = .center
        footer.titleLabel?.adjustsFontForContentSizeCategory = true
        footer.titleLabel?.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .italicSystemFont(ofSize: 12))
        footer.setTitleColor(.secondaryLabel, for: .normal)
        footer.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if retry { refresh() } else { open(receipt.ledgerURL) }
        }, for: .touchUpInside)
        addArrangedSubview(footer)
        footer.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor).isActive = true
        footer.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .nodeSeekAccountSessionDidChange, object: nil)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func label(_ text: String, size: CGFloat, weight: UIFont.Weight) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: size, weight: weight))
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }

    private func configureCard() {
        card.layer.cornerRadius = 10
        card.clipsToBounds = true
        card.backgroundColor = UIColor(white: 0.25, alpha: 1)
        gradient.colors = [
            UIColor(red: 0.25, green: 0.33, blue: 0.35, alpha: 1).cgColor,
            UIColor(red: 0.36, green: 0.28, blue: 0.42, alpha: 1).cgColor,
            UIColor(red: 0.33, green: 0.26, blue: 0.30, alpha: 1).cgColor
        ]
        gradient.startPoint = .zero
        gradient.endPoint = CGPoint(x: 1, y: 0.3)
        let fade = CAGradientLayer()
        fade.colors = [UIColor.black.cgColor, UIColor.clear.cgColor]
        gradient.mask = fade
        card.layer.insertSublayer(gradient, at: 0)

        let avatar = UIImageView()
        avatar.contentMode = .scaleAspectFill
        avatar.layer.cornerRadius = 9
        avatar.clipsToBounds = true
        AvatarImageLoader.shared.loadAvatar(into: avatar, postID: "stardust-\(receipt.memberID)",
                                            avatarURL: NodeSeekNotificationURLBuilder.avatarURL(memberID: receipt.memberID))
        let amount = label(String(receipt.amount), size: 20, weight: .bold)
        let symbol = UIImageView(image: Self.stardustIcon)
        symbol.contentMode = .scaleAspectFit
        let amountRow = UIStackView(arrangedSubviews: [amount, symbol])
        amountRow.alignment = .center
        amountRow.spacing = 2
        amount.setContentHuggingPriority(.required, for: .horizontal)
        symbol.widthAnchor.constraint(equalToConstant: UIFontMetrics(forTextStyle: .body).scaledValue(for: 22)).isActive = true
        symbol.heightAnchor.constraint(equalTo: symbol.widthAnchor).isActive = true
        let reference = label("Ref ID \(receipt.referenceID)", size: 10, weight: .medium)
        reference.textAlignment = .right
        let metadata = UIStackView(arrangedSubviews: [reference])
        metadata.axis = .vertical
        metadata.alignment = .trailing
        if receipt.oneTime { metadata.addArrangedSubview(label("Onetime", size: 10, weight: .medium)) }
        let top = UIStackView(arrangedSubviews: [amountRow, UIView(), metadata])
        top.alignment = .top
        top.spacing = 4
        let details = UIStackView(arrangedSubviews: [top])
        details.axis = .vertical
        details.spacing = 2
        if !receipt.note.isEmpty { details.addArrangedSubview(label(receipt.note, size: 12, weight: .medium)) }
        let row = UIStackView(arrangedSubviews: [avatar, details])
        row.spacing = 15
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        card.accessibilityIdentifier = "stardust-payment"
        card.accessibilityLabel = ["\(receipt.amount) 🌌", receipt.note, reference.text, receipt.oneTime ? "Onetime" : nil]
            .compactMap { $0 }.joined(separator: ", ")
        card.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            open(receipt.sourceURL)
        }, for: .touchUpInside)
        addArrangedSubview(card)
        let preferredWidth = card.widthAnchor.constraint(equalToConstant: 290)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            preferredWidth, card.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 50), avatar.heightAnchor.constraint(equalToConstant: 50),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10)
        ])
    }

    /// 卡面使用彩色星系图形，流水行沿用站点的 🌌 文本。
    private static let stardustIcon = UIGraphicsImageRenderer(size: CGSize(width: 22, height: 22)).image { canvas in
        let context = canvas.cgContext
        context.translateBy(x: 11, y: 11)
        context.rotate(by: .pi / 4)
        func disc(_ width: CGFloat, _ height: CGFloat, _ color: UIColor) {
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        }
        disc(22, 15, UIColor(red: 0.04, green: 0.15, blue: 0.28, alpha: 1))
        disc(19, 12, .systemBlue)
        disc(14, 9, .systemCyan)
        disc(10, 7, .systemIndigo)
        disc(5, 4, .white)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = card.bounds
        gradient.mask?.frame = gradient.bounds
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refresh()
    }

    @objc private func refresh() {
        statusTask?.cancel()
        guard window != nil else { return }
        retry = false
        footer.accessibilityValue = nil
        footer.setAttributedTitle(nil, for: .normal)
        footer.setTitle(DetailListStrings.text("stardust-loading"), for: .normal)
        statusTask = Task { [weak self, loadStatus, receipt] in
            do {
                let status = try await loadStatus(receipt)
                guard !Task.isCancelled else { return }
                if let status {
                    self?.show(status)
                } else {
                    self?.footer.setTitle(DetailListStrings.text("stardust-login"), for: .normal)
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                retry = true
                footer.setTitle(DetailListStrings.text("stardust-retry"), for: .normal)
                footer.accessibilityValue = error.localizedDescription
                AppLog.warning(.service, "星辰流水读取失败：\(error.localizedDescription)")
            }
        }
    }

    private func show(_ status: StardustReceiptStatus) {
        let prefix = DetailListStrings.text(status.paid ? "stardust-paid" : "stardust-unpaid")
        let count = String(status.count)
        let format = DetailListStrings.text("stardust-summary")
        let summary = String(format: format, count, status.total)
        let text = NSMutableAttributedString(string: prefix + summary, attributes: [.foregroundColor: UIColor.secondaryLabel])
        let range = (summary as NSString).range(of: count)
        if range.location != NSNotFound {
            text.addAttribute(.foregroundColor, value: UIColor.systemGreen,
                              range: NSRange(location: (prefix as NSString).length + range.location, length: range.length))
        }
        footer.accessibilityValue = nil
        footer.setAttributedTitle(text, for: .normal)
    }
}
