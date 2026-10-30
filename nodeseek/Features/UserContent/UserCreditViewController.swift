import UIKit

@MainActor
final class UserCreditViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let model: UserCreditViewModel
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let refreshControl = UIRefreshControl()
    private let header = UIView()
    private let headerStack = UIStackView()
    private let balanceLabel = UILabel()
    private let ownerLabel = UILabel()
    private let footerButton = UIButton(type: .system)
    private let footerSpinner = UIActivityIndicatorView(style: .medium)
    private var listTask: Task<Void, Never>?
    private var profileTask: Task<Void, Never>?

    init(uid: Int, profile: UserProfileRecord? = nil, client: (any UserCreditLoading)? = nil) {
        model = UserCreditViewModel(uid: uid, profile: profile, client: client ?? NodeSeekUserContentClient())
        super.init(nibName: nil, bundle: nil)
        title = "鸡腿明细"
        navigationItem.largeTitleDisplayMode = .never
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        listTask?.cancel()
        profileTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        view.backgroundColor = .systemGroupedBackground
        tableView.backgroundColor = .systemGroupedBackground
        tableView.accessibilityIdentifier = "credit-list"
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 74
        tableView.register(UserCreditCell.self, forCellReuseIdentifier: "record")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(reload), for: .valueChanged)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        setupHeader()
        setupFooter()
        model.onChange = { [weak self] in self?.render() }
        reload()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeHeader()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || navigationController?.isBeingDismissed == true {
            listTask?.cancel()
            profileTask?.cancel()
        }
    }

    private func setupHeader() {
        let icon = UILabel()
        icon.text = "🍗"
        icon.font = .systemFont(ofSize: 40)
        icon.textAlignment = .center
        icon.isAccessibilityElement = false
        icon.translatesAutoresizingMaskIntoConstraints = false

        let caption = UILabel()
        caption.text = "鸡腿余额"
        caption.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12))
        caption.textColor = .secondaryLabel
        caption.adjustsFontForContentSizeCategory = true
        balanceLabel.font = UIFontMetrics(forTextStyle: .title1).scaledFont(for: .monospacedDigitSystemFont(ofSize: 28, weight: .bold))
        balanceLabel.textColor = .label
        balanceLabel.accessibilityIdentifier = "credit-balance"
        ownerLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12))
        ownerLabel.textColor = .secondaryLabel
        [balanceLabel, ownerLabel].forEach {
            $0.adjustsFontForContentSizeCategory = true
            $0.numberOfLines = 0
        }
        headerStack.axis = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 2
        [caption, balanceLabel, ownerLabel].forEach { headerStack.addArrangedSubview($0) }
        let content = UIStackView(arrangedSubviews: [icon, headerStack])
        content.alignment = .center
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(content)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 48),
            icon.heightAnchor.constraint(equalToConstant: 52),
            content.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: header.topAnchor, constant: 10),
            content.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8)
        ])
        tableView.tableHeaderView = header
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        viewIfLoaded?.setNeedsLayout()
    }

    private func sizeHeader() {
        guard tableView.bounds.width > 0 else { return }
        let size = header.systemLayoutSizeFitting(
            CGSize(width: tableView.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        if header.frame.size != size {
            header.frame.size = size
            tableView.tableHeaderView = header
        }
    }

    private func setupFooter() {
        let footer = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 64))
        footerButton.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        footerButton.titleLabel?.adjustsFontForContentSizeCategory = true
        footerButton.tintColor = .secondaryLabel
        footerButton.translatesAutoresizingMaskIntoConstraints = false
        footerSpinner.translatesAutoresizingMaskIntoConstraints = false
        footerButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if model.failedRefresh { reload() } else { loadMore() }
        }, for: .touchUpInside)
        footer.addSubview(footerButton)
        footer.addSubview(footerSpinner)
        NSLayoutConstraint.activate([
            footerButton.centerXAnchor.constraint(equalTo: footer.centerXAnchor),
            footerButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            footerButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            footerSpinner.centerXAnchor.constraint(equalTo: footer.centerXAnchor),
            footerSpinner.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
        ])
        tableView.tableFooterView = footer
    }

    @objc private func reload() {
        listTask?.cancel()
        profileTask?.cancel()
        let model = model
        listTask = Task { await model.load(refresh: true) }
        profileTask = Task { await model.refreshProfile() }
    }

    private func loadMore() {
        guard !model.isLoading, model.hasLoaded, model.hasMore else { return }
        let model = model
        listTask = Task { await model.load(refresh: false) }
    }

    private func render() {
        let skeleton = !model.hasLoaded && model.isLoading
        balanceLabel.text = model.profile.map { "\($0.coin)" } ?? (skeleton ? "      " : "—")
        balanceLabel.backgroundColor = model.profile == nil && skeleton ? .systemGray5 : .clear
        balanceLabel.accessibilityLabel = model.profile.map { "鸡腿余额 \($0.coin)" } ?? "鸡腿余额暂不可用"
        ownerLabel.text = model.profile?.name
        ownerLabel.isHidden = model.profile?.name.isEmpty != false
        ownerLabel.accessibilityIdentifier = "credit-owner"
        tableView.reloadData()
        sizeHeader()
        if !model.isLoading { refreshControl.endRefreshing() }
        let isEmpty = model.records.isEmpty && !skeleton
        tableView.backgroundView = isEmpty ? makeMessageView() : nil
        let footerVisible = !model.records.isEmpty && !skeleton
        footerButton.isHidden = !footerVisible || model.isLoading
        footerButton.isEnabled = model.hasMore || model.failedRefresh
        footerButton.setTitle(model.errorMessage ?? (model.hasMore ? "加载更多" : "没有更多记录"), for: .normal)
        footerButton.setTitleColor(.secondaryLabel, for: .disabled)
        if footerVisible && model.isLoading { footerSpinner.startAnimating() } else { footerSpinner.stopAnimating() }
    }

    private func makeMessageView() -> UIView {
        let container = UIView()
        let label = UILabel()
        label.text = model.errorMessage ?? "暂无鸡腿记录"
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        let button = UIButton(type: .system)
        button.setTitle("重试", for: .normal)
        button.tintColor = .label
        button.isHidden = model.errorMessage == nil
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.addAction(UIAction { [weak self] _ in self?.reload() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [label, button])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: 60),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24)
        ])
        return container
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        !model.hasLoaded && model.isLoading ? 5 : model.records.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { "变动记录" }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "record", for: indexPath) as! UserCreditCell
        let record = !model.hasLoaded && model.isLoading ? nil : model.records[indexPath.row]
        cell.configure(record: record)
        return cell
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isDragging, model.errorMessage == nil,
              scrollView.contentSize.height > 0,
              scrollView.contentOffset.y + scrollView.bounds.height > scrollView.contentSize.height - 150 else { return }
        loadMore()
    }
}
