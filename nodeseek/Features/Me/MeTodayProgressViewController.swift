import UIKit

final class MeTodayProgressViewController: UIViewController {
    static var localizedTitle: String { NSLocalizedString("今日进度", tableName: "Me", comment: "") }

    var onRetry: (() -> Void)?
    private let card = UserProfileProgressCardView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let retryButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Self.localizedTitle
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        card.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(card)
        view.addSubview(scrollView)
        retryButton.setTitle(NSLocalizedString("重试", tableName: "Me", comment: ""), for: .normal)
        retryButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        retryButton.titleLabel?.adjustsFontForContentSizeCategory = true
        retryButton.tintColor = .label
        retryButton.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)
        for control in [spinner, retryButton] {
            control.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(control)
            NSLayoutConstraint.activate([
                control.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                control.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
            ])
        }
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            card.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            card.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            card.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            card.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
            retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
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
