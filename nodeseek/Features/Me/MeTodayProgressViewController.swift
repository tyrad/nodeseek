import UIKit

final class MeTodayProgressViewController: UIViewController {
    static var localizedTitle: String { NSLocalizedString("今日进度", tableName: "Me", comment: "") }

    var onRetry: (() -> Void)?
    private let panel = UIVisualEffectView()
    private let card = UserProfileProgressCardView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let retryButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityViewIsModal = true

        let backdrop = UIControl()
        backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        backdrop.isAccessibilityElement = false
        backdrop.frame = view.bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backdrop.addTarget(self, action: #selector(closeDialog), for: .touchUpInside)
        view.addSubview(backdrop)

        panel.accessibilityIdentifier = "me-progress-dialog"
        panel.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 26.0, *) {
            panel.cornerConfiguration = .uniformCorners(radius: .fixed(28))
        } else {
            panel.layer.cornerCurve = .continuous
            panel.layer.cornerRadius = 28
            panel.clipsToBounds = true
        }
        view.addSubview(panel)
        applyMaterial()
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyMaterial),
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil
        )
        let safe = view.safeAreaLayoutGuide
        let preferredWidth = panel.widthAnchor.constraint(equalToConstant: 384)
        preferredWidth.priority = .defaultHigh
        let centered = panel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        centered.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            preferredWidth, centered,
            panel.widthAnchor.constraint(lessThanOrEqualTo: safe.widthAnchor, constant: -40),
            panel.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            panel.topAnchor.constraint(greaterThanOrEqualTo: safe.topAnchor, constant: 8),
            panel.bottomAnchor.constraint(lessThanOrEqualTo: safe.bottomAnchor, constant: -8)
        ])
        setUpContent()
    }

    @objc private func applyMaterial() {
        if UIAccessibility.isReduceTransparencyEnabled {
            panel.effect = nil
            panel.backgroundColor = .secondarySystemGroupedBackground
        } else {
            panel.backgroundColor = .clear
            if #available(iOS 26.0, *) {
                panel.effect = UIGlassEffect(style: .regular)
            } else {
                panel.effect = UIBlurEffect(style: .systemThickMaterial)
            }
        }
    }

    private func setUpContent() {
        let titleLabel = UILabel()
        titleLabel.text = Self.localizedTitle
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.accessibilityTraits.insert(.header)
        titleLabel.numberOfLines = 0
        let closeButton = UIButton(type: .close)
        closeButton.addTarget(self, action: #selector(closeDialog), for: .touchUpInside)
        let header = UIStackView(arrangedSubviews: [titleLabel, closeButton])
        header.alignment = .center
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView.addSubview(header)

        card.backgroundColor = .clear
        retryButton.setTitle(NSLocalizedString("重试", tableName: "Me", comment: ""), for: .normal)
        retryButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        retryButton.titleLabel?.adjustsFontForContentSizeCategory = true
        retryButton.tintColor = .label
        retryButton.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView.addSubview(scrollView)
        card.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(card)
        for control in [spinner, retryButton] {
            control.translatesAutoresizingMaskIntoConstraints = false
            panel.contentView.addSubview(control)
            NSLayoutConstraint.activate([
                control.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
                control.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
            ])
        }
        let fitContent = scrollView.heightAnchor.constraint(equalTo: card.heightAnchor)
        fitContent.priority = .defaultHigh
        let content = panel.contentView
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
            card.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            card.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            card.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            card.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            fitContent,
            retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    @objc private func closeDialog() {
        dismiss(animated: true)
    }

    override func accessibilityPerformEscape() -> Bool {
        closeDialog()
        return true
    }

    func render(level: UserLevelProgress, progress: UserTodayProgressRecord?, isLoading: Bool) {
        loadViewIfNeeded()
        card.isHidden = progress == nil
        retryButton.isHidden = progress != nil || isLoading
        if let progress { card.configure(level: level, today: progress) }
        if progress == nil && isLoading {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
    }
}
