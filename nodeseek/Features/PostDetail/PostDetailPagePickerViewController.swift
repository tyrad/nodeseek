//
//  PostDetailPagePickerViewController.swift
//  nodeseek
//

import UIKit

/// 详情页的页码面板：首页/末页快捷按钮 + 页码网格，点选后关闭并回调。
final class PostDetailPagePickerViewController: UIViewController {
    private enum Layout {
        static let horizontalInset: CGFloat = 18
        static let topInset: CGFloat = 20
        static let spacing: CGFloat = 12
        static let columns = 5
        static let cellHeight: CGFloat = 40
        static let cellSpacing: CGFloat = 8
        static let quickButtonHeight: CGFloat = 40
        /// 网格超过这么多行就允许拉到全屏。
        static let compactMaxRows = 6
    }

    private let totalPages: Int
    private let currentPage: Int
    private let loadedPages: Set<Int>
    private let exitsAuthorFilter: Bool
    private let onSelectPage: (Int) -> Void

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let firstPageButton = UIButton(type: .system)
    private let lastPageButton = UIButton(type: .system)
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())

    init(
        totalPages: Int,
        currentPage: Int,
        loadedPages: Set<Int>,
        exitsAuthorFilter: Bool,
        onSelectPage: @escaping (Int) -> Void
    ) {
        self.totalPages = max(1, totalPages)
        self.currentPage = min(max(1, currentPage), max(1, totalPages))
        self.loadedPages = loadedPages
        self.exitsAuthorFilter = exitsAuthorFilter
        self.onSelectPage = onSelectPage
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            let rows = (self.totalPages + Layout.columns - 1) / Layout.columns
            let visibleRows = CGFloat(min(rows, Layout.compactMaxRows))
            let contentHeight = Layout.topInset + 44 + Layout.spacing
                + Layout.quickButtonHeight + Layout.spacing
                + visibleRows * Layout.cellHeight + (visibleRows - 1) * Layout.cellSpacing
                + 24
            if #available(iOS 16.0, *) {
                let compact = UISheetPresentationController.Detent.custom(identifier: .init("pagePicker.compact")) { context in
                    min(contentHeight, context.maximumDetentValue)
                }
                sheet.detents = rows > Layout.compactMaxRows ? [compact, .large()] : [compact]
            } else {
                sheet.detents = [.medium(), .large()]
            }
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 18
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureLabels()
        configureQuickButtons()
        configureCollectionView()
        layoutContent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let item = currentPage - 1
        guard item >= 0, item < collectionView.numberOfItems(inSection: 0) else { return }
        collectionView.scrollToItem(at: IndexPath(item: item, section: 0), at: .centeredVertically, animated: false)
    }

    private func configureLabels() {
        titleLabel.text = "跳到第几页"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label

        var subtitle = "共 \(totalPages) 页 · 当前第 \(currentPage) 页"
        if exitsAuthorFilter {
            subtitle += " · 跳页后退出只看楼主"
        }
        subtitleLabel.text = subtitle
        subtitleLabel.font = .preferredFont(forTextStyle: .footnote)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0
    }

    private func configureQuickButtons() {
        configureQuickButton(firstPageButton, title: "首页", page: 1)
        firstPageButton.accessibilityIdentifier = "post-detail-page-picker-first"
        configureQuickButton(lastPageButton, title: "末页 · \(totalPages)", page: totalPages)
        lastPageButton.accessibilityIdentifier = "post-detail-page-picker-last"
    }

    private func configureQuickButton(_ button: UIButton, title: String, page: Int) {
        var configuration = UIButton.Configuration.bordered()
        configuration.title = title
        configuration.baseForegroundColor = .label
        configuration.baseBackgroundColor = .secondarySystemBackground
        configuration.cornerStyle = .medium
        button.configuration = configuration
        button.addAction(UIAction { [weak self] _ in
            self?.select(page: page)
        }, for: .touchUpInside)
    }

    private func configureCollectionView() {
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = false
        collectionView.accessibilityIdentifier = "post-detail-page-picker-grid"
        collectionView.register(PageCell.self, forCellWithReuseIdentifier: PageCell.reuseIdentifier)
    }

    private func makeLayout() -> UICollectionViewLayout {
        let fraction = 1.0 / CGFloat(Layout.columns)
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(fraction),
            heightDimension: .fractionalHeight(1)
        ))
        item.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: Layout.cellSpacing / 2,
            bottom: 0,
            trailing: Layout.cellSpacing / 2
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(Layout.cellHeight)),
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = Layout.cellSpacing
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: -Layout.cellSpacing / 2,
            bottom: 16,
            trailing: -Layout.cellSpacing / 2
        )
        return UICollectionViewCompositionalLayout(section: section)
    }

    private func layoutContent() {
        let headerStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        headerStack.axis = .vertical
        headerStack.spacing = 4

        let quickStack = UIStackView(arrangedSubviews: [firstPageButton, lastPageButton])
        quickStack.axis = .horizontal
        quickStack.distribution = .fillEqually
        quickStack.spacing = Layout.cellSpacing

        [headerStack, quickStack, collectionView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Layout.topInset),
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.horizontalInset),
            headerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalInset),

            quickStack.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: Layout.spacing),
            quickStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.horizontalInset),
            quickStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalInset),
            quickStack.heightAnchor.constraint(equalToConstant: Layout.quickButtonHeight),

            collectionView.topAnchor.constraint(equalTo: quickStack.bottomAnchor, constant: Layout.spacing),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.horizontalInset),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalInset),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func select(page: Int) {
        let onSelectPage = onSelectPage
        dismiss(animated: true) {
            onSelectPage(page)
        }
    }
}

extension PostDetailPagePickerViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        totalPages
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PageCell.reuseIdentifier, for: indexPath)
        let page = indexPath.item + 1
        (cell as? PageCell)?.configure(
            page: page,
            isCurrent: page == currentPage,
            isLoaded: loadedPages.contains(page)
        )
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        select(page: indexPath.item + 1)
    }
}

private final class PageCell: UICollectionViewCell {
    static let reuseIdentifier = "PostDetailPagePickerCell"

    private let label = UILabel()
    private let loadedDot = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 10
        contentView.layer.cornerCurve = .continuous

        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)

        loadedDot.layer.cornerRadius = 2
        loadedDot.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(loadedDot)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            loadedDot.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            loadedDot.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            loadedDot.widthAnchor.constraint(equalToConstant: 4),
            loadedDot.heightAnchor.constraint(equalToConstant: 4)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { contentView.alpha = isHighlighted ? 0.6 : 1 }
    }

    func configure(page: Int, isCurrent: Bool, isLoaded: Bool) {
        label.text = "\(page)"
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: isCurrent ? .semibold : .medium)
        contentView.backgroundColor = isCurrent ? .systemGray3 : .secondarySystemBackground
        loadedDot.backgroundColor = isCurrent ? .label : .secondaryLabel
        loadedDot.isHidden = isLoaded == false
        accessibilityLabel = isCurrent ? "第 \(page) 页，当前页" : "第 \(page) 页"
        accessibilityTraits = isCurrent ? [.button, .selected] : .button
        isAccessibilityElement = true
    }
}
