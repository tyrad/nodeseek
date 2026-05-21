//
//  PostListViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit

enum PostListTopBarStyle {
    enum Menu {
        static let symbolPointSize: CGFloat = 16
        static let symbolWeight = UIImage.SymbolWeight.regular
    }

    enum Tab {
        static let pointSize: CGFloat = 17
        static let selectedWeight = UIFont.Weight.medium
        static let normalWeight = UIFont.Weight.regular
    }
}

class PostListViewController: UIViewController {
    private enum TopBarLayout {
        static let topOffset: CGFloat = -4
        static let contentSpacing: CGFloat = 2
        static let controlSize: CGFloat = 40
    }

    private enum FloatingControlLayout {
        static let sortToggleBottomInset: CGFloat = 204
    }

    // MARK: - Properties
    let presenter: PostListPresenterProtocol
    let detailTestURLProvider: () -> String
    var categories: [PostListCategoryItem] = []
    var selectedCategory: PostListCategoryItem = .all
    var currentSortMode: PostListSortMode = .replyTime
    var sortToggleWidthConstraint: NSLayoutConstraint?
    private var sortToggleTrailingConstraint: NSLayoutConstraint?
    private var sortToggleCollapseWorkItem: DispatchWorkItem?
    var isSortToggleExpanded = false
    let sideMenuViewController = PostListSideMenuViewController()
    let menuButtonFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    private let categoryReselectFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    var hasCompactTopButton: Bool {
        compactTopButton.superview != nil
    }
    
    // MARK: - UI Components
    let pageContainerViewController: PostPageContainerViewController
    private let compactTopButton: UIButton = {
        let button = UIButton(type: .system)
        let symbolConfig = UIImage.SymbolConfiguration(
            pointSize: PostListTopBarStyle.Menu.symbolPointSize,
            weight: PostListTopBarStyle.Menu.symbolWeight
        )
        let image = UIImage(systemName: "list.bullet", withConfiguration: symbolConfig)
            ?? UIImage(systemName: "line.3.horizontal", withConfiguration: symbolConfig)
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .label
        configuration.image = image?.withRenderingMode(.alwaysTemplate)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        configuration.background.backgroundColor = .clear
        configuration.background.cornerRadius = 0
        configuration.cornerStyle = .fixed
        button.configuration = configuration
        button.tintColor = .label
        button.backgroundColor = .clear
        button.layer.cornerRadius = 0
        button.layer.borderWidth = 0
        button.accessibilityIdentifier = "post-list-menu-button"
        button.configurationUpdateHandler = { updateButton in
            updateButton.alpha = updateButton.isHighlighted ? 0.72 : 1.0
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let categoryEditButton: UIButton = {
        let button = UIButton(type: .system)
        let symbolConfig = UIImage.SymbolConfiguration(
            pointSize: PostListTopBarStyle.Menu.symbolPointSize,
            weight: PostListTopBarStyle.Menu.symbolWeight
        )
        let image = UIImage(systemName: "gearshape", withConfiguration: symbolConfig)
            ?? UIImage(systemName: "square.and.pencil", withConfiguration: symbolConfig)
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .label
        configuration.image = image?.withRenderingMode(.alwaysTemplate)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        configuration.background.backgroundColor = .clear
        configuration.background.cornerRadius = 0
        configuration.cornerStyle = .fixed
        button.configuration = configuration
        button.tintColor = .label
        button.backgroundColor = .clear
        button.layer.cornerRadius = 0
        button.layer.borderWidth = 0
        button.accessibilityIdentifier = "post-list-category-edit-button"
        button.accessibilityLabel = "编辑首页分类"
        button.configurationUpdateHandler = { updateButton in
            updateButton.alpha = updateButton.isHighlighted ? 0.72 : 1.0
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let sortToggleAnchorView: UIView = {
        let view = UIView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let floatingSortToggleContainer: FloatingControlContainerView

    let sortToggleButton = PostListSortToggleButton()
    
    private let tabScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private let tabStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var tabButtons: [PostListCategoryItem: CategoryTabButton] = [:]
    
    // MARK: - Initialization
    init(
        presenter: PostListPresenterProtocol,
        visitedStore: VisitedPostStoreProtocol = EmptyVisitedPostStore(),
        floatingPositionStore: FloatingControlPositionStoring = UserDefaultsFloatingControlPositionStore(),
        detailTestURLProvider: @escaping () -> String = {
            UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string ?? ""
        }
    ) {
        self.presenter = presenter
        self.detailTestURLProvider = detailTestURLProvider
        self.pageContainerViewController = PostPageContainerViewController(
            visitedStore: visitedStore
        )
        self.floatingSortToggleContainer = FloatingControlContainerView(
            accessibilityIdentifier: "post-list-floating-sort-toggle",
            positionStorageKey: FloatingControlPositionKeys.postListSortToggle,
            positionStore: floatingPositionStore
        )
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        presenter.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        refreshAppearanceForCurrentTraits()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        floatingSortToggleContainer.updateFloatingEdgeInsets(
            in: view,
            topBoundary: pageContainerViewController.view.frame.minY,
            horizontalAnchorView: sortToggleAnchorView
        )
        floatingSortToggleContainer.syncFrame(with: sortToggleAnchorView)
    }

    // MARK: - Setup UI
    private func setupUI() {
        navigationItem.title = nil
        navigationItem.leftBarButtonItem = nil
        
        view.backgroundColor = .systemBackground
        pageContainerViewController.eventDelegate = self
        addChild(pageContainerViewController)
        let pageContainerView = pageContainerViewController.view!
        pageContainerView.translatesAutoresizingMaskIntoConstraints = false
        compactTopButton.addTarget(self, action: #selector(leftButtonTapped), for: .touchUpInside)
        compactTopButton.addTarget(self, action: #selector(prepareMenuButtonFeedback), for: .touchDown)
        categoryEditButton.addTarget(self, action: #selector(categoryEditButtonTapped), for: .touchUpInside)
        sortToggleButton.addTarget(self, action: #selector(sortToggleButtonTapped), for: .touchUpInside)
        floatingSortToggleContainer.onAdsorbedEdgeChanged = { [weak self] edge in
            self?.sortToggleButton.applyDockedEdge(edge)
        }
        floatingSortToggleContainer.hostControl(sortToggleButton)
        view.addSubview(pageContainerView)
        view.addSubview(compactTopButton)
        view.addSubview(sortToggleAnchorView)
        view.addSubview(floatingSortToggleContainer)
        view.addSubview(tabScrollView)
        tabScrollView.addSubview(tabStackView)

        let sortToggleTrailingConstraint = sortToggleAnchorView.trailingAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.trailingAnchor,
            constant: PostListSortToggleButton.collapsedTrailing
        )
        let sortToggleWidthConstraint = sortToggleAnchorView.widthAnchor.constraint(
            equalToConstant: PostListSortToggleButton.collapsedWidth
        )
        self.sortToggleTrailingConstraint = sortToggleTrailingConstraint
        self.sortToggleWidthConstraint = sortToggleWidthConstraint

        NSLayoutConstraint.activate([
            pageContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageContainerView.topAnchor.constraint(equalTo: tabScrollView.bottomAnchor, constant: TopBarLayout.contentSpacing),
            pageContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            compactTopButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            compactTopButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: TopBarLayout.topOffset),
            compactTopButton.widthAnchor.constraint(equalToConstant: TopBarLayout.controlSize),
            compactTopButton.heightAnchor.constraint(equalToConstant: TopBarLayout.controlSize),

            categoryEditButton.widthAnchor.constraint(equalToConstant: TopBarLayout.controlSize),
            categoryEditButton.heightAnchor.constraint(equalToConstant: TopBarLayout.controlSize),

            sortToggleTrailingConstraint,
            sortToggleAnchorView.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -FloatingControlLayout.sortToggleBottomInset
            ),
            sortToggleWidthConstraint,
            sortToggleAnchorView.heightAnchor.constraint(equalToConstant: PostListSortToggleButton.height),

            tabScrollView.leadingAnchor.constraint(equalTo: compactTopButton.trailingAnchor, constant: 8),
            tabScrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            tabScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: TopBarLayout.topOffset),
            tabScrollView.heightAnchor.constraint(equalToConstant: TopBarLayout.controlSize),

            tabStackView.leadingAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.leadingAnchor),
            tabStackView.trailingAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.trailingAnchor),
            tabStackView.topAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.topAnchor),
            tabStackView.bottomAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.bottomAnchor),
            tabStackView.heightAnchor.constraint(equalTo: tabScrollView.frameLayoutGuide.heightAnchor)
        ])
        pageContainerViewController.didMove(toParent: self)

        installSideMenuController()
        sortToggleButton.apply(sortMode: currentSortMode, expanded: false)
        sortToggleButton.applyAlpha(expanded: false)
    }
    
    // MARK: - Actions
    @objc private func prepareMenuButtonFeedback() {
        menuButtonFeedbackGenerator.prepare()
    }

    @objc private func leftButtonTapped() {
        menuButtonFeedbackGenerator.impactOccurred()
        sideMenuViewController.show(animated: true)
    }

    @objc private func sortToggleButtonTapped() {
        setSortToggleExpanded(true, animated: true)
        let sortMode = pageContainerViewController.toggleSortMode(for: selectedCategory)
        renderSortMode(sortMode)
        pageContainerViewController.scrollToTop(for: selectedCategory, animated: false)
        scheduleSortToggleCollapse()
    }

    @objc private func categoryEditButtonTapped() {
        presenter.didTapCategoryPreferences()
    }

    @objc private func categoryButtonTapped(_ sender: CategoryTabButton) {
        guard let category = sender.category else { return }
        guard category != selectedCategory else {
            categoryReselectFeedbackGenerator.impactOccurred()
            pageContainerViewController.scrollToTop(for: selectedCategory, animated: false)
            presenter.didReselectCategory(category)
            return
        }
        selectedCategory = category
        applySelectedCategory(category, syncPage: true, pageAnimated: true)
        renderSortMode(pageContainerViewController.sortMode(for: category))
        presenter.didSelectCategory(category)
    }

    func rebuildCategoryButtons() {
        tabButtons = [:]
        tabStackView.arrangedSubviews.forEach { subview in
            tabStackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        for category in categories {
            let button = CategoryTabButton()
            button.category = category
            button.setTitle(category.title, for: .normal)
            button.addTarget(self, action: #selector(categoryButtonTapped(_:)), for: .touchUpInside)
            tabStackView.addArrangedSubview(button)
            tabButtons[category] = button
        }
        tabStackView.addArrangedSubview(categoryEditButton)
    }

    func applySelectedCategory(_ selected: PostListCategoryItem, syncPage: Bool, pageAnimated: Bool) {
        for (category, button) in tabButtons {
            button.applySelectedStyle(isSelected: category == selected)
        }

        if let selectedButton = tabButtons[selected] {
            let rect = selectedButton.convert(selectedButton.bounds, to: tabScrollView)
            tabScrollView.scrollRectToVisible(rect.insetBy(dx: -16, dy: 0), animated: true)
        }

        if syncPage {
            pageContainerViewController.setCurrentCategory(selected, animated: pageAnimated)
        }
        renderSortMode(pageContainerViewController.sortMode(for: selected))
    }

    private func scheduleSortToggleCollapse() {
        sortToggleCollapseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.setSortToggleExpanded(false, animated: true)
        }
        sortToggleCollapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35, execute: workItem)
    }

    private func setSortToggleExpanded(_ expanded: Bool, animated: Bool) {
        sortToggleCollapseWorkItem?.cancel()
        sortToggleCollapseWorkItem = nil
        isSortToggleExpanded = expanded
        sortToggleButton.apply(sortMode: currentSortMode, expanded: expanded)
        sortToggleWidthConstraint?.constant = expanded
            ? PostListSortToggleButton.expandedWidth(for: currentSortMode.accessibilityTitle)
            : PostListSortToggleButton.collapsedWidth
        sortToggleTrailingConstraint?.constant = expanded
            ? PostListSortToggleButton.expandedTrailing
            : PostListSortToggleButton.collapsedTrailing

        let animations: () -> Void = { [weak self] in
            self?.sortToggleButton.applyAlpha(expanded: expanded)
            self?.view.layoutIfNeeded()
        }
        guard animated else {
            animations()
            return
        }
        sortToggleButton.applyJellyAnimation(expanded: expanded)
        UIView.animate(
            withDuration: PostListSortToggleButton.transitionDuration,
            delay: 0,
            usingSpringWithDamping: PostListSortToggleButton.transitionDamping,
            initialSpringVelocity: PostListSortToggleButton.transitionVelocity,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: animations
        )
    }

    private func refreshAppearanceForCurrentTraits() {
        view.backgroundColor = .systemBackground
        compactTopButton.tintColor = .label
        categoryEditButton.tintColor = .label
        applySelectedCategory(selectedCategory, syncPage: false, pageAnimated: false)
        sortToggleButton.apply(sortMode: currentSortMode, expanded: isSortToggleExpanded)
        pageContainerViewController.refreshVisibleAppearanceForCurrentTraits()
    }

    private func installSideMenuController() {
        sideMenuViewController.onLoginTapped = { [weak self] in
            self?.presenter.didTapLogin()
        }
        sideMenuViewController.onAccountProfileTapped = { [weak self] profileURL in
            self?.presenter.didTapAccountProfile(profileURL: profileURL)
        }
        sideMenuViewController.onNewDiscussionTapped = { [weak self] in
            self?.presenter.didTapNewDiscussion()
        }
        sideMenuViewController.onCheckInTapped = { [weak self] in
            self?.presenter.didTapCheckIn()
        }
        sideMenuViewController.onNotificationTapped = { [weak self] url in
            self?.presenter.didTapNotification(url: url)
        }
        sideMenuViewController.onRecentVisitedTapped = { [weak self] in
            self?.presenter.didTapRecentVisited()
        }
        sideMenuViewController.onUserDiscussionsTapped = { [weak self] in
            self?.presenter.didTapUserDiscussions()
        }
        sideMenuViewController.onUserCommentsTapped = { [weak self] in
            self?.presenter.didTapUserComments()
        }
        sideMenuViewController.onUserCollectionsTapped = { [weak self] in
            self?.presenter.didTapUserCollections()
        }
        sideMenuViewController.onSearchTapped = { [weak self] in
            self?.presenter.didTapSearch()
        }
        sideMenuViewController.onSettingsTapped = { [weak self] in
            self?.presenter.didTapSettings()
        }
        addChild(sideMenuViewController)
        view.addSubview(sideMenuViewController.view)
        sideMenuViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sideMenuViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sideMenuViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sideMenuViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            sideMenuViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        sideMenuViewController.didMove(toParent: self)
    }
}
