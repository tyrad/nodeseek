//
//  PostListViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit

class PostListViewController: UIViewController {
    
    // MARK: - Properties
    private let presenter: PostListPresenterProtocol
    private var categories: [PostListCategory] = []
    private var selectedCategory: PostListCategory = .all
    private var currentSortMode: PostListSortMode = .replyTime
    private var sortToggleWidthConstraint: NSLayoutConstraint?
    private var sortToggleTrailingConstraint: NSLayoutConstraint?
    private var sortToggleCollapseWorkItem: DispatchWorkItem?
    private var isSortToggleExpanded = false
    private let sideMenuViewController = PostListSideMenuViewController()
    private let menuButtonFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    var hasCompactTopButton: Bool {
        compactTopButton.superview != nil
    }
    
    // MARK: - UI Components
    private let pageContainerView = PostTexturePageContainerView()
    private let compactTopButton: UIButton = {
        let button = UIButton(type: .system)
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
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

    private let sortToggleButton: UIButton = {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .systemBackground
        configuration.imagePadding = 0
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        configuration.titleLineBreakMode = .byTruncatingTail
        button.configuration = configuration
        button.accessibilityIdentifier = "post-list-sort-toggle"
        button.tintColor = .systemBackground
        button.setTitleColor(.systemBackground, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.titleLabel?.numberOfLines = 1
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.9
        button.backgroundColor = .label
        button.layer.cornerRadius = SortToggleLayout.cornerRadius
        button.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        button.layer.borderWidth = 0.5
        button.layer.borderColor = UIColor.separator.cgColor
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.18
        button.layer.shadowRadius = 12
        button.layer.shadowOffset = CGSize(width: 0, height: 5)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
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

    private var tabButtons: [PostListCategory: CategoryTabButton] = [:]
    
    // MARK: - Initialization
    init(presenter: PostListPresenterProtocol) {
        self.presenter = presenter
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
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    // MARK: - Setup UI
    private func setupUI() {
        navigationItem.title = nil
        navigationItem.leftBarButtonItem = nil
        
        view.backgroundColor = .systemBackground
        pageContainerView.translatesAutoresizingMaskIntoConstraints = false
        pageContainerView.delegate = self
        pageContainerView.attach(to: self)
        compactTopButton.addTarget(self, action: #selector(leftButtonTapped), for: .touchUpInside)
        compactTopButton.addTarget(self, action: #selector(prepareMenuButtonFeedback), for: .touchDown)
        sortToggleButton.addTarget(self, action: #selector(sortToggleButtonTapped), for: .touchUpInside)
        view.addSubview(pageContainerView)
        view.addSubview(compactTopButton)
        view.addSubview(sortToggleButton)
        view.addSubview(tabScrollView)
        view.addSubview(loadingIndicator)
        tabScrollView.addSubview(tabStackView)

        let sortToggleTrailingConstraint = sortToggleButton.trailingAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.trailingAnchor,
            constant: SortToggleLayout.collapsedTrailing
        )
        let sortToggleWidthConstraint = sortToggleButton.widthAnchor.constraint(
            equalToConstant: SortToggleLayout.collapsedWidth
        )
        self.sortToggleTrailingConstraint = sortToggleTrailingConstraint
        self.sortToggleWidthConstraint = sortToggleWidthConstraint

        NSLayoutConstraint.activate([
            pageContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageContainerView.topAnchor.constraint(equalTo: tabScrollView.bottomAnchor, constant: 6),
            pageContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            compactTopButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            compactTopButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            compactTopButton.widthAnchor.constraint(equalToConstant: 40),
            compactTopButton.heightAnchor.constraint(equalToConstant: 40),

            sortToggleTrailingConstraint,
            sortToggleButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -56),
            sortToggleWidthConstraint,
            sortToggleButton.heightAnchor.constraint(equalToConstant: SortToggleLayout.height),

            tabScrollView.leadingAnchor.constraint(equalTo: compactTopButton.trailingAnchor, constant: 8),
            tabScrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            tabScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            tabScrollView.heightAnchor.constraint(equalToConstant: 40),

            tabStackView.leadingAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.leadingAnchor),
            tabStackView.trailingAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.trailingAnchor),
            tabStackView.topAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.topAnchor),
            tabStackView.bottomAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.bottomAnchor),
            tabStackView.heightAnchor.constraint(equalTo: tabScrollView.frameLayoutGuide.heightAnchor),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        installSideMenuController()
        applySortTogglePresentation(expanded: false)
        applySortToggleAlpha(expanded: false)
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
        presenter.didToggleSortMode()
        pageContainerView.scrollToTop(for: selectedCategory, animated: false)
        scheduleSortToggleCollapse()
    }

    @objc private func categoryButtonTapped(_ sender: CategoryTabButton) {
        guard let category = sender.category else { return }
        guard category != selectedCategory else { return }
        selectedCategory = category
        applySelectedCategory(category, syncPage: true, pageAnimated: true)
        presenter.didSelectCategory(category)
    }

    private func rebuildCategoryButtons() {
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
    }

    private func applySelectedCategory(_ selected: PostListCategory, syncPage: Bool, pageAnimated: Bool) {
        for (category, button) in tabButtons {
            button.applySelectedStyle(isSelected: category == selected)
        }

        if let selectedButton = tabButtons[selected] {
            let rect = selectedButton.convert(selectedButton.bounds, to: tabScrollView)
            tabScrollView.scrollRectToVisible(rect.insetBy(dx: -16, dy: 0), animated: true)
        }

        if syncPage {
            pageContainerView.setCurrentCategory(selected, animated: pageAnimated)
        }
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
        applySortTogglePresentation(expanded: expanded)
        sortToggleWidthConstraint?.constant = expanded
            ? SortToggleLayout.expandedWidth(for: currentSortMode.accessibilityTitle)
            : SortToggleLayout.collapsedWidth
        sortToggleTrailingConstraint?.constant = expanded ? SortToggleLayout.expandedTrailing : SortToggleLayout.collapsedTrailing

        let animations: () -> Void = { [weak self] in
            self?.applySortToggleAlpha(expanded: expanded)
            self?.view.layoutIfNeeded()
        }
        guard animated else {
            animations()
            return
        }
        applySortToggleJellyAnimation(expanded: expanded)
        UIView.animate(
            withDuration: SortToggleLayout.transitionDuration,
            delay: 0,
            usingSpringWithDamping: SortToggleLayout.transitionDamping,
            initialSpringVelocity: SortToggleLayout.transitionVelocity,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: animations
        )
    }

    private func applySortTogglePresentation(expanded: Bool) {
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        let image = UIImage(systemName: currentSortMode.symbolName, withConfiguration: symbolConfiguration)
        let title = currentSortMode.accessibilityTitle
        sortToggleButton.setImage(image, for: .normal)
        sortToggleButton.setTitle(expanded ? title : nil, for: .normal)
        sortToggleButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        sortToggleButton.titleLabel?.numberOfLines = 1
        sortToggleButton.titleLabel?.lineBreakMode = .byTruncatingTail
        sortToggleButton.titleLabel?.adjustsFontSizeToFitWidth = true
        sortToggleButton.titleLabel?.minimumScaleFactor = 0.9

        var configuration = sortToggleButton.configuration ?? UIButton.Configuration.plain()
        configuration.baseForegroundColor = .systemBackground
        configuration.image = image
        configuration.title = expanded ? title : nil
        configuration.imagePadding = expanded ? SortToggleLayout.expandedImagePadding : 0
        configuration.contentInsets = expanded ? SortToggleLayout.expandedInsets : SortToggleLayout.collapsedInsets
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.titleTextAttributesTransformer = expanded ? SortToggleLayout.titleAttributesTransformer : nil
        sortToggleButton.configuration = configuration
        sortToggleButton.accessibilityLabel = currentSortMode.accessibilityTitle
    }

    private func applySortToggleAlpha(expanded: Bool) {
        sortToggleButton.alpha = expanded ? SortToggleLayout.expandedAlpha : SortToggleLayout.collapsedAlpha
    }

    private func applySortToggleJellyAnimation(expanded: Bool) {
        sortToggleButton.layer.removeAnimation(forKey: SortToggleLayout.jellyAnimationKey)

        let scaleX = CAKeyframeAnimation(keyPath: "transform.scale.x")
        scaleX.values = expanded
            ? [1, 1.08, 0.98, 1.02, 1]
            : [1, 0.94, 1.04, 0.99, 1]
        scaleX.keyTimes = SortToggleLayout.jellyKeyTimes
        scaleX.timingFunctions = SortToggleLayout.jellyTimingFunctions

        let scaleY = CAKeyframeAnimation(keyPath: "transform.scale.y")
        scaleY.values = expanded
            ? [1, 0.96, 1.03, 0.99, 1]
            : [1, 1.04, 0.97, 1.01, 1]
        scaleY.keyTimes = SortToggleLayout.jellyKeyTimes
        scaleY.timingFunctions = SortToggleLayout.jellyTimingFunctions

        let animationGroup = CAAnimationGroup()
        animationGroup.animations = [scaleX, scaleY]
        animationGroup.duration = SortToggleLayout.jellyDuration
        animationGroup.isRemovedOnCompletion = true
        sortToggleButton.layer.add(animationGroup, forKey: SortToggleLayout.jellyAnimationKey)
    }

    private func installSideMenuController() {
        sideMenuViewController.onLoginTapped = { [weak self] in
            self?.presenter.didTapLogin()
        }
        #if DEBUG
        sideMenuViewController.onDetailTestTapped = { [weak self] in
            self?.presenter.didTapDetailTest()
        }
        #endif
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

// MARK: - View Protocol
extension PostListViewController: PostListViewProtocol {
    
    func showLoading() {
        pageContainerView.showLoadingSkeleton(for: selectedCategory)
        loadingIndicator.stopAnimating()
    }
    
    func hideLoading() {
        pageContainerView.hideLoadingSkeleton(for: selectedCategory)
        loadingIndicator.stopAnimating()
    }

    func showRefreshing() {
        pageContainerView.showRefreshing(for: selectedCategory)
    }

    func hideRefreshing() {
        pageContainerView.hideRefreshing(for: selectedCategory)
    }

    func showLoadingMore() {
        pageContainerView.showLoadingMore(for: selectedCategory)
    }

    func hideLoadingMore() {
        pageContainerView.hideLoadingMore(for: selectedCategory)
    }
    
    func showError(message: String) {
        let alert = UIAlertController(title: "错误", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    #if DEBUG
    func showDetailTestInput() {
        guard NodeSeekDebugConfig.enablePostDetailTestEntry else { return }
        let alert = UIAlertController(
            title: "详情测试",
            message: "输入 NodeSeek 帖子详情链接",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "https://www.nodeseek.com/post-705039-1"
            textField.keyboardType = .URL
            textField.textContentType = .URL
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
            textField.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "打开", style: .default) { [weak self, weak alert] _ in
            let rawURL = alert?.textFields?.first?.text ?? ""
            self?.presenter.didSubmitDetailTestURL(rawURL)
        })
        present(alert, animated: true)
    }
    #endif

    func renderCategories(_ categories: [PostListCategory], selected: PostListCategory) {
        let categoriesChanged = categories != self.categories
        if categoriesChanged {
            self.categories = categories
            rebuildCategoryButtons()
            pageContainerView.configure(categories: categories)
        }
        selectedCategory = selected
        applySelectedCategory(selected, syncPage: categoriesChanged, pageAnimated: false)
    }

    func renderSortMode(_ sortMode: PostListSortMode) {
        currentSortMode = sortMode
        applySortTogglePresentation(expanded: isSortToggleExpanded)
        if isSortToggleExpanded {
            sortToggleWidthConstraint?.constant = SortToggleLayout.expandedWidth(for: sortMode.accessibilityTitle)
        }
    }
    func render(posts: [PostSummary]) {
        pageContainerView.setPosts(posts, for: selectedCategory)
    }
}

private enum SortToggleLayout {
    static let collapsedWidth: CGFloat = 58
    static let minimumExpandedWidth: CGFloat = 168
    static let height: CGFloat = 42
    static let cornerRadius: CGFloat = 14
    static let collapsedAlpha: CGFloat = 0.62
    static let expandedAlpha: CGFloat = 1
    static let collapsedTrailing: CGFloat = 12
    static let expandedTrailing: CGFloat = 0
    static let transitionDuration: TimeInterval = 0.34
    static let transitionDamping: CGFloat = 0.68
    static let transitionVelocity: CGFloat = 0.6
    static let jellyAnimationKey = "sortToggleJelly"
    static let jellyDuration: TimeInterval = 0.42
    static let jellyKeyTimes: [NSNumber] = [0, 0.28, 0.58, 0.82, 1]
    static let jellyTimingFunctions = [
        CAMediaTimingFunction(name: .easeOut),
        CAMediaTimingFunction(name: .easeInEaseOut),
        CAMediaTimingFunction(name: .easeInEaseOut),
        CAMediaTimingFunction(name: .easeOut)
    ]
    static let expandedImagePadding: CGFloat = 6
    static let expandedInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 16)
    static let collapsedInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
    static let titleFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
    static let titleAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var outgoing = incoming
        outgoing.font = titleFont
        return outgoing
    }

    static func expandedWidth(for title: String) -> CGFloat {
        let titleWidth = ceil((title as NSString).size(withAttributes: [.font: titleFont]).width)
        let imageWidth: CGFloat = 18
        let measuredWidth = expandedInsets.leading
            + imageWidth
            + expandedImagePadding
            + titleWidth
            + expandedInsets.trailing
        return max(minimumExpandedWidth, ceil(measuredWidth))
    }
}

private extension PostListSortMode {
    var symbolName: String {
        switch self {
        case .postTime:
            return "line.3.horizontal.decrease.circle.fill"
        case .replyTime:
            return "arrow.up.arrow.down.circle.fill"
        }
    }
}

private final class CategoryTabButton: UIButton {
    var category: PostListCategory?
    private let indicatorView: UIView = {
        let view = UIView()
        view.backgroundColor = .label
        view.layer.cornerRadius = 1
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        contentEdgeInsets = UIEdgeInsets(top: 0, left: 3, bottom: 0, right: 3)
        titleLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        setTitleColor(.secondaryLabel, for: .normal)
        addSubview(indicatorView)
        NSLayoutConstraint.activate([
            indicatorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            indicatorView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            indicatorView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            indicatorView.heightAnchor.constraint(equalToConstant: 3)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applySelectedStyle(isSelected: Bool) {
        titleLabel?.font = isSelected ? .systemFont(ofSize: 17, weight: .semibold) : .systemFont(ofSize: 17, weight: .regular)
        setTitleColor(isSelected ? .label : .secondaryLabel, for: .normal)
        indicatorView.isHidden = !isSelected
    }
}

extension PostListViewController: PostTexturePageContainerViewDelegate {
    func postTexturePageContainerView(
        _ containerView: PostTexturePageContainerView,
        didSelectPostAt index: Int,
        category: PostListCategory
    ) {
        if category != selectedCategory {
            selectedCategory = category
            applySelectedCategory(category, syncPage: false, pageAnimated: false)
            presenter.didSelectCategory(category)
        }
        presenter.didSelectPost(at: index)
    }

    func postTexturePageContainerView(
        _ containerView: PostTexturePageContainerView,
        didApproachBottomAt index: Int,
        totalCount: Int,
        category: PostListCategory
    ) {
        if category != selectedCategory {
            selectedCategory = category
            applySelectedCategory(category, syncPage: false, pageAnimated: false)
            presenter.didSelectCategory(category)
        }
        presenter.didApproachBottom(currentIndex: index, totalCount: totalCount)
    }

    func postTexturePageContainerViewDidRequestRefresh(
        _ containerView: PostTexturePageContainerView,
        category: PostListCategory
    ) {
        if category != selectedCategory {
            selectedCategory = category
            applySelectedCategory(category, syncPage: false, pageAnimated: false)
            presenter.didSelectCategory(category)
        }
        presenter.didPullToRefresh()
    }

    func postTexturePageContainerView(_ containerView: PostTexturePageContainerView, didScrollTo category: PostListCategory) {
        guard category != selectedCategory else { return }
        selectedCategory = category
        applySelectedCategory(category, syncPage: false, pageAnimated: false)
        presenter.didSelectCategory(category)
    }

    func postTexturePageContainerViewDidRequestLeadingSideMenu(_ containerView: PostTexturePageContainerView) {
        menuButtonFeedbackGenerator.impactOccurred()
        sideMenuViewController.show(animated: true)
    }
}
