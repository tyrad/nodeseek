//
//  HotListViewController.swift
//  nodeseek
//

import UIKit

/// 热榜：导航栏放实时 / 日榜 / 周榜三个 tab，下方三个独立列表左右滑动切换，与首页分类一致。
final class HotListViewController: UIViewController, TabReselectHandling {
    var onSelectPost: ((PostSummary) -> Void)? {
        didSet { pages.values.forEach { $0.onSelectPost = onSelectPost } }
    }

    private let repository: HotListRepository
    private let kinds = HotListKind.allCases
    private var pages: [HotListKind: HotListPageViewController] = [:]
    private(set) var selectedKind: HotListKind = .realtime
    private var tabButtons: [HotListKind: CategoryTabButton] = [:]
    private var hasLinkedPopGesture = false

    private let pageViewController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal,
        options: [.interPageSpacing: 0]
    )

    private let tabStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 22
        stack.alignment = .fill
        return stack
    }()

    init(repository: HotListRepository = HotListService.shared) {
        self.repository = repository
        super.init(nibName: nil, bundle: nil)
        title = HotListL10n.text("热榜")
        for kind in kinds {
            pages[kind] = HotListPageViewController(kind: kind, repository: repository)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        setupTabs()
        let settingsItem = UIBarButtonItem(
            image: UIImage(systemName: "slider.horizontal.3"),
            style: .plain,
            target: self,
            action: #selector(settingsTapped)
        )
        settingsItem.accessibilityLabel = HotListL10n.text("热榜设置")
        settingsItem.accessibilityIdentifier = "hot-list-settings-button"
        navigationItem.rightBarButtonItem = settingsItem
        setupPages()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        linkPopGestureIfNeeded()
    }

    func handleTabReselect() {
        pages[selectedKind]?.scrollToTop()
    }

    func page(for kind: HotListKind) -> HotListPageViewController? {
        pages[kind]
    }

    func select(_ kind: HotListKind, animated: Bool = true) {
        guard kind != selectedKind else {
            handleTabReselect()
            return
        }
        guard let page = pages[kind],
              let from = kinds.firstIndex(of: selectedKind),
              let to = kinds.firstIndex(of: kind) else { return }
        updateSelection(kind)
        pageViewController.setViewControllers([page], direction: to > from ? .forward : .reverse, animated: animated)
    }

    // MARK: - Setup

    private func setupTabs() {
        for kind in kinds {
            let button = CategoryTabButton()
            button.setTitle(kind.tabTitle, for: .normal)
            button.accessibilityIdentifier = "hot-list-tab-\(kind.rawValue)"
            button.addAction(UIAction { [weak self] _ in self?.select(kind) }, for: .touchUpInside)
            tabButtons[kind] = button
            tabStack.addArrangedSubview(button)
        }
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        tabStack.heightAnchor.constraint(equalToConstant: 40).isActive = true
        navigationItem.titleView = tabStack
        updateSelection(selectedKind)
    }

    private func setupPages() {
        addChild(pageViewController)
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageViewController.view)
        NSLayoutConstraint.activate([
            pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        pageViewController.didMove(toParent: self)
        pageViewController.dataSource = self
        pageViewController.delegate = self
        if let first = pages[selectedKind] {
            pageViewController.setViewControllers([first], direction: .forward, animated: false)
        }
    }

    private func updateSelection(_ kind: HotListKind) {
        selectedKind = kind
        for (buttonKind, button) in tabButtons {
            let isSelected = buttonKind == kind
            button.applySelectedStyle(isSelected: isSelected)
            button.accessibilityTraits = isSelected ? [.button, .selected] : .button
        }
    }

    /// 在第一页从屏幕左缘右滑时优先返回上一页，而不是被分页滚动吃掉。
    private func linkPopGestureIfNeeded() {
        guard !hasLinkedPopGesture,
              let popGesture = navigationController?.interactivePopGestureRecognizer,
              let scrollView = pageViewController.view.subviews.compactMap({ $0 as? UIScrollView }).first
        else { return }
        scrollView.panGestureRecognizer.require(toFail: popGesture)
        hasLinkedPopGesture = true
    }

    @objc private func settingsTapped() {
        navigationController?.pushViewController(HotListSettingsViewController(repository: repository), animated: true)
    }
}

extension HotListViewController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? HotListPageViewController,
              let index = kinds.firstIndex(of: page.kind), index > 0 else { return nil }
        return pages[kinds[index - 1]]
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? HotListPageViewController,
              let index = kinds.firstIndex(of: page.kind), index < kinds.count - 1 else { return nil }
        return pages[kinds[index + 1]]
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed, let page = pageViewController.viewControllers?.first as? HotListPageViewController else { return }
        updateSelection(page.kind)
    }
}
