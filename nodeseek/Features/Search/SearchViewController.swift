//
//  SearchViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/5/3.
//

import SafariServices
import UIKit

final class SearchViewController: UIViewController {
    private struct SearchRequest: Equatable {
        let query: String
        let category: PostListCategory
    }

    private let service: NodeSeekService
    private let sessionStore: NodeSeekSessionStore
    private let visitedStore: VisitedPostStoreProtocol
    private let searchHistoryStore: SearchHistoryStore
    private let searchPreferenceStore: SearchPreferenceStore
    private let userSearcher: any UserSearchLoading
    private let isLoggedIn: @MainActor () async -> Bool
    private let categories = PostListCategory.allCases.filter { category in
        category != .df && category != .award
    }

    private var selectedScope: SearchScope = .post
    private var selectedCategory: PostListCategory = .all
    private var activeRequest: SearchRequest?
    private var activeUserQuery: String?
    private var userSearchTask: Task<Void, Never>?
    private var items: [PostListItem] = []
    private var loadedIDs: Set<String> = []
    private var nextPage = 2
    private var hasMorePages = true
    private var isLoadingFirstPage = false
    private var isRefreshing = false
    private var isLoadingMore = false
    private var loadTask: Task<Void, Never>?

    private let formContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let scopeControl: SearchScopeTabsView = {
        let control = SearchScopeTabsView(titles: SearchScope.allCases.map(\.title))
        control.accessibilityIdentifier = "search-scope-control"
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    /// 分类嵌在搜索框左侧，带下拉箭头，一眼能看出可切换；只在帖子搜索时出现。
    private let categorySelectorButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.title = "全部"
        configuration.image = UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        )
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 4
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 15, weight: .semibold)
            return outgoing
        }

        let button = UIButton(type: .system)
        button.configuration = configuration
        button.showsMenuAsPrimaryAction = true
        button.accessibilityIdentifier = "search-category-selector-button"
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let categoryDividerView: UIView = {
        let view = UIView()
        view.backgroundColor = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let searchIconView: UIImageView = {
        let imageView = UIImageView(image: UIImage(
            systemName: "magnifyingglass",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        ))
        imageView.tintColor = .secondaryLabel
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let keywordTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "输入关键字"
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.font = .systemFont(ofSize: 16)
        textField.clearButtonMode = .whileEditing
        textField.returnKeyType = .search
        textField.textContentType = .none
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.accessibilityIdentifier = "search-keyword-text-field"
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    /// 搜索框整体：分类 | 放大镜 + 输入框，填充底色代替描边。
    private lazy var searchFieldContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .tertiarySystemFill
        view.layer.cornerRadius = 12
        view.layer.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var searchFieldStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [categorySelectorButton, categoryDividerView, searchIconView, keywordTextField])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.setCustomSpacing(12, after: categorySelectorButton)
        stack.setCustomSpacing(12, after: categoryDividerView)
        stack.setCustomSpacing(6, after: searchIconView)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let searchButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "搜索"
        configuration.baseBackgroundColor = .label
        configuration.baseForegroundColor = .systemBackground
        configuration.cornerStyle = .fixed
        configuration.background.cornerRadius = 12
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 15, weight: .semibold)
            return outgoing
        }

        let button = UIButton(type: .system)
        button.configuration = configuration
        button.accessibilityIdentifier = "search-submit-button"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var inputRowStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [searchFieldContainerView, searchButton])
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// 导航条隐藏后自带的返回按钮；Tab 根页面没有上一页时隐藏。
    private let backButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: "chevron.left",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        )
        configuration.baseForegroundColor = .label
        configuration.contentInsets = .zero

        let button = UIButton(type: .system)
        button.configuration = configuration
        // 箭头贴左，和下方分类按钮左边缘对齐，点击区域仍保持 44pt
        button.contentHorizontalAlignment = .leading
        button.isHidden = true
        button.accessibilityLabel = "返回"
        button.accessibilityIdentifier = "search-back-button"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var topRowStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [backButton, scopeControl])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var formStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [topRowStackView, inputRowStackView])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let recentSearchesTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "最近搜索"
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = ReadingColors.text
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let clearRecentSearchesButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.title = "清空"
        configuration.baseForegroundColor = .secondaryLabel
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 14, weight: .regular)
            return outgoing
        }

        let button = UIButton(type: .system)
        button.configuration = configuration
        button.accessibilityIdentifier = "search-history-clear-button"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let collapseRecentSearchesButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.title = "收起"
        configuration.image = UIImage(
            systemName: "chevron.up",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        )
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 2
        configuration.baseForegroundColor = .secondaryLabel
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 0)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 14, weight: .regular)
            return outgoing
        }

        let button = UIButton(type: .system)
        button.configuration = configuration
        button.isHidden = true
        button.accessibilityLabel = "收起搜索历史"
        button.accessibilityIdentifier = "search-history-collapse-button"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let historySeparatorView: UIView = {
        let view = UIView()
        view.backgroundColor = .separator
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// 有结果时历史默认收成一行；每次新搜索都恢复收起。
    private var isHistoryExpanded = false
    /// 接管侧滑手势前系统原本的代理，离开页面时还回去
    private weak var originalPopGestureDelegate: UIGestureRecognizerDelegate?
    private var historyTopConstraint: NSLayoutConstraint?
    private var resultsBelowHistoryConstraints: [NSLayoutConstraint] = []
    private var resultsBelowFormConstraints: [NSLayoutConstraint] = []

    private lazy var recentSearchesHeaderStackView: UIStackView = {
        let spacer = UIView()
        let stack = UIStackView(arrangedSubviews: [recentSearchesTitleLabel, spacer, clearRecentSearchesButton, collapseRecentSearchesButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let recentSearchesTagCloudView = SearchHistoryTagCloudView()

    private lazy var recentSearchesContainerView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [recentSearchesHeaderStackView, recentSearchesTagCloudView])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 8
        stack.isHidden = true
        stack.accessibilityIdentifier = "search-history-container"
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let listView: PostTextureListView = {
        let view = PostTextureListView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let userResultsView: SearchUserResultsView = {
        let view = SearchUserResultsView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    init(
        service: NodeSeekService = SearchViewController.makeDefaultService(),
        sessionStore: NodeSeekSessionStore = .shared,
        visitedStore: VisitedPostStoreProtocol? = nil,
        searchHistoryStore: SearchHistoryStore = SearchHistoryStore(),
        searchPreferenceStore: SearchPreferenceStore = SearchPreferenceStore(),
        userSearcher: (any UserSearchLoading)? = nil,
        isLoggedIn: (@MainActor () async -> Bool)? = nil
    ) {
        self.service = service
        self.sessionStore = sessionStore
        self.visitedStore = visitedStore ?? VisitedPostStore.shared
        self.searchHistoryStore = searchHistoryStore
        self.searchPreferenceStore = searchPreferenceStore
        self.userSearcher = userSearcher ?? NodeSeekUserContentClient()
        self.isLoggedIn = isLoggedIn ?? { await TabLayoutAccountGate.isLoggedIn() }
        super.init(nibName: nil, bundle: nil)
    }

    static func makeDefaultService() -> NodeSeekService {
        NodeSeekService(htmlClient: HTMLLoadingStrategyFactory.makeDefaultClient())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
        userSearchTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        let rememberedCategory = searchPreferenceStore.category()
        applySelectedCategory(categories.contains(rememberedCategory) ? rememberedCategory : .all)
        applyScope(.post)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 隐藏导航条把空间让给结果列表；进入下一页时在 viewWillDisappear 里恢复。
        navigationController?.setNavigationBarHidden(true, animated: animated)
        backButton.isHidden = !canGoBack
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 导航条隐藏后系统默认不响应左边缘侧滑返回，页面显示期间由本页决定是否放行
        if let popGesture = navigationController?.interactivePopGestureRecognizer, popGesture.delegate !== self {
            originalPopGestureDelegate = popGesture.delegate
            popGesture.delegate = self
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        if let popGesture = navigationController?.interactivePopGestureRecognizer, popGesture.delegate === self {
            popGesture.delegate = originalPopGestureDelegate
        }
    }

    /// 从首页推入或模态弹出时可返回；作为 Tab 根页面时没有上一页。
    private var canGoBack: Bool {
        if let navigationController, navigationController.viewControllers.first !== self {
            return true
        }
        return presentingViewController != nil
    }

    @objc private func backButtonTapped() {
        if let navigationController, navigationController.viewControllers.first !== self {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    private func setupUI() {
        title = "搜一搜"
        view.backgroundColor = UIColor.systemBackground
        keywordTextField.delegate = self
        keywordTextField.addTarget(self, action: #selector(keywordTextChanged), for: .editingChanged)
        listView.delegate = self
        userResultsView.onSelectUser = { [weak self] record in
            self?.navigationController?.pushViewController(UserProfileViewController(uid: record.uid), animated: true)
        }
        scopeControl.addTarget(self, action: #selector(scopeControlChanged), for: .valueChanged)
        searchButton.addTarget(self, action: #selector(searchButtonTapped), for: .touchUpInside)
        clearRecentSearchesButton.addTarget(self, action: #selector(clearRecentSearchesButtonTapped), for: .touchUpInside)
        collapseRecentSearchesButton.addTarget(self, action: #selector(collapseRecentSearchesButtonTapped), for: .touchUpInside)
        backButton.addTarget(self, action: #selector(backButtonTapped), for: .touchUpInside)
        recentSearchesTagCloudView.onExpand = { [weak self] in
            self?.isHistoryExpanded = true
            self?.renderRecentSearches()
        }

        view.addSubview(formContainerView)
        view.addSubview(recentSearchesContainerView)
        view.addSubview(historySeparatorView)
        view.addSubview(listView)
        view.addSubview(userResultsView)
        formContainerView.addSubview(formStackView)
        searchFieldContainerView.addSubview(searchFieldStackView)

        let historyTopConstraint = recentSearchesContainerView.topAnchor.constraint(equalTo: formContainerView.bottomAnchor, constant: 18)
        self.historyTopConstraint = historyTopConstraint
        resultsBelowHistoryConstraints = [
            listView.topAnchor.constraint(equalTo: historySeparatorView.bottomAnchor),
            userResultsView.topAnchor.constraint(equalTo: historySeparatorView.bottomAnchor)
        ]
        resultsBelowFormConstraints = [
            listView.topAnchor.constraint(equalTo: formContainerView.bottomAnchor, constant: 12),
            userResultsView.topAnchor.constraint(equalTo: formContainerView.bottomAnchor, constant: 12)
        ]
        NSLayoutConstraint.activate(resultsBelowFormConstraints)

        NSLayoutConstraint.activate([
            // 搜索框固定在顶部：搜索时不再移动布局，避免和键盘收起动画叠在一起。
            formContainerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            formContainerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            formContainerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),

            formStackView.leadingAnchor.constraint(equalTo: formContainerView.leadingAnchor),
            formStackView.trailingAnchor.constraint(equalTo: formContainerView.trailingAnchor),
            formStackView.topAnchor.constraint(equalTo: formContainerView.topAnchor),
            formStackView.bottomAnchor.constraint(equalTo: formContainerView.bottomAnchor),

            searchFieldContainerView.heightAnchor.constraint(equalToConstant: 44),
            searchFieldStackView.leadingAnchor.constraint(equalTo: searchFieldContainerView.leadingAnchor, constant: 14),
            searchFieldStackView.trailingAnchor.constraint(equalTo: searchFieldContainerView.trailingAnchor, constant: -8),
            searchFieldStackView.topAnchor.constraint(equalTo: searchFieldContainerView.topAnchor),
            searchFieldStackView.bottomAnchor.constraint(equalTo: searchFieldContainerView.bottomAnchor),
            categoryDividerView.widthAnchor.constraint(equalToConstant: 1),
            categoryDividerView.heightAnchor.constraint(equalToConstant: 18),
            keywordTextField.heightAnchor.constraint(equalToConstant: 44),
            searchButton.widthAnchor.constraint(equalToConstant: 64),
            topRowStackView.heightAnchor.constraint(equalToConstant: 44),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            recentSearchesContainerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            recentSearchesContainerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            historyTopConstraint,

            historySeparatorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            historySeparatorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            historySeparatorView.topAnchor.constraint(equalTo: recentSearchesContainerView.bottomAnchor, constant: 10),
            historySeparatorView.heightAnchor.constraint(equalToConstant: 0.5),

            listView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            userResultsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            userResultsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            userResultsView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// 无结果时完整展示历史；有结果时历史收成一行放在结果上方，可展开。
    private func renderRecentSearches() {
        recentSearchesTagCloudView.setButtons([])

        // 有结果时去掉正在搜的那条：关键词已经在搜索框里，不必重复展示
        let records = searchHistoryStore.records().filter { record in
            categories.contains(record.category) && !isCurrentRecord(record)
        }
        let showingResults = isShowingResults
        let hasHistory = !records.isEmpty
        recentSearchesContainerView.isHidden = !hasHistory
        historySeparatorView.isHidden = !(showingResults && hasHistory)

        // 有历史时结果列表排在历史下方，否则直接接在搜索框下
        NSLayoutConstraint.deactivate(hasHistory ? resultsBelowFormConstraints : resultsBelowHistoryConstraints)
        NSLayoutConstraint.activate(hasHistory ? resultsBelowHistoryConstraints : resultsBelowFormConstraints)
        guard hasHistory else { return }

        let isCollapsed = showingResults && !isHistoryExpanded
        historyTopConstraint?.constant = showingResults ? 12 : 22
        recentSearchesHeaderStackView.isHidden = isCollapsed
        collapseRecentSearchesButton.isHidden = !(showingResults && isHistoryExpanded)
        recentSearchesTagCloudView.isCollapsed = isCollapsed

        let buttons = records.enumerated().map { index, record in
            makeRecentSearchButton(record: record, index: index)
        }
        recentSearchesTagCloudView.setButtons(buttons)
    }

    /// 当前 Tab 正在展示结果的那条历史。
    private func isCurrentRecord(_ record: SearchHistoryRecord) -> Bool {
        switch selectedScope {
        case .post:
            guard let request = activeRequest else { return false }
            return record.scope == .post && record.query == request.query && record.category == request.category
        case .user:
            return record.scope == .user && record.query == activeUserQuery
        case .google:
            return false
        }
    }

    private func makeRecentSearchButton(record: SearchHistoryRecord, index: Int) -> UIButton {
        let button = SearchHistoryChipButton(
            title: record.query,
            tag: record.tagTitle
        )
        button.accessibilityIdentifier = "search-history-record-button-\(index)"
        button.addAction(UIAction { [weak self] _ in
            self?.submitSearch(record: record)
        }, for: .touchUpInside)
        return button
    }

    private func applySelectedCategory(_ category: PostListCategory) {
        selectedCategory = category
        var configuration = categorySelectorButton.configuration ?? UIButton.Configuration.bordered()
        configuration.title = category.title
        categorySelectorButton.configuration = configuration
        categorySelectorButton.menu = makeCategoryMenu()
    }

    /// 当前 Tab 有搜索结果时展示结果，否则展示搜索历史；切换 Tab 不丢已有结果。
    private var isShowingResults: Bool {
        switch selectedScope {
        case .post: return activeRequest != nil
        case .user: return activeUserQuery != nil
        case .google: return false
        }
    }

    private func updateContentVisibility() {
        listView.isHidden = !(selectedScope == .post && activeRequest != nil)
        userResultsView.isHidden = !(selectedScope == .user && activeUserQuery != nil)
        renderRecentSearches()
    }

    private func applyScope(_ scope: SearchScope) {
        selectedScope = scope
        if let index = SearchScope.allCases.firstIndex(of: scope) {
            scopeControl.selectedSegmentIndex = index
        }
        // 分类只对帖子搜索生效，其他 Tab 隐藏分类按钮，输入框自动占满
        categorySelectorButton.isHidden = scope != .post
        categoryDividerView.isHidden = scope != .post
        switch scope {
        case .post: keywordTextField.placeholder = "输入关键字"
        case .user: keywordTextField.placeholder = "输入用户名"
        case .google: keywordTextField.placeholder = "用谷歌搜索本站"
        }
        updateContentVisibility()
    }

    /// 与网页一致：site 限定本站后交给谷歌搜索
    static func googleSearchURL(query: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        let host = NodeSeekSite.baseURL.host ?? "www.nodeseek.com"
        components?.queryItems = [URLQueryItem(name: "q", value: "site:\(host) \(query)")]
        return components?.url
    }

    private func makeCategoryMenu() -> UIMenu {
        let actions = categories.map { category in
            UIAction(
                title: category.title,
                state: category == selectedCategory ? .on : .off
            ) { [weak self] _ in
                self?.applySelectedCategory(category)
            }
        }
        return UIMenu(title: "选择分类", options: .singleSelection, children: actions)
    }

    @objc private func scopeControlChanged() {
        let index = scopeControl.selectedSegmentIndex
        guard SearchScope.allCases.indices.contains(index) else { return }
        applyScope(SearchScope.allCases[index])
    }

    @objc private func keywordTextChanged() {
        let query = keywordTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if query.isEmpty {
            clearResultsForCurrentScope()
        }
    }

    /// 输入框清空后回到初始状态：收起当前 Tab 的结果，重新完整展示搜索历史。
    private func clearResultsForCurrentScope() {
        switch selectedScope {
        case .post:
            guard activeRequest != nil else { return }
            loadTask?.cancel()
            activeRequest = nil
            items = []
            loadedIDs = []
            isLoadingFirstPage = false
            isLoadingMore = false
            if isRefreshing {
                isRefreshing = false
                listView.hideRefreshing()
            }
            listView.setItems([])
            listView.hideLoadingSkeleton()
            listView.hideFirstPageError()
            listView.hideLoadingMore()
        case .user:
            guard activeUserQuery != nil else { return }
            userSearchTask?.cancel()
            activeUserQuery = nil
        case .google:
            return
        }
        isHistoryExpanded = false
        updateContentVisibility()
    }

    @objc private func searchButtonTapped() {
        submitSearch()
    }

    @objc private func clearRecentSearchesButtonTapped() {
        searchHistoryStore.clear()
        isHistoryExpanded = false
        renderRecentSearches()
    }

    @objc private func collapseRecentSearchesButtonTapped() {
        isHistoryExpanded = false
        renderRecentSearches()
    }

    private func submitSearch() {
        let query = keywordTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else {
            // 空关键字只聚焦输入框，不在键盘弹起时弹窗，减少键盘视图切换。
            keywordTextField.becomeFirstResponder()
            return
        }

        keywordTextField.resignFirstResponder()
        isHistoryExpanded = false
        searchHistoryStore.record(query: query, category: selectedCategory, scope: selectedScope)
        switch selectedScope {
        case .post:
            searchPreferenceStore.rememberCategory(selectedCategory)
            startFirstPageLoad(request: SearchRequest(query: query, category: selectedCategory))
        case .user:
            startUserSearch(query: query)
        case .google:
            if let url = Self.googleSearchURL(query: query) {
                present(SFSafariViewController(url: url), animated: true)
            }
        }
        updateContentVisibility()
    }

    private func submitSearch(record: SearchHistoryRecord) {
        keywordTextField.text = record.query
        if record.scope == .post {
            applySelectedCategory(record.category)
        }
        applyScope(record.scope)
        submitSearch()
    }

    private func startUserSearch(query: String) {
        userSearchTask?.cancel()
        activeUserQuery = query
        userResultsView.setState(.loading)
        userSearchTask = Task { [weak self, userSearcher] in
            do {
                let records = try await userSearcher.findMembers(keyword: query)
                guard let self, !Task.isCancelled, self.activeUserQuery == query else { return }
                self.userResultsView.setState(.loaded(records))
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled, self.activeUserQuery == query else { return }
                // 游客请求时站点直接返回 HTTP 500，这里换成可理解的提示
                let message = await self.isLoggedIn() ? error.localizedDescription : "登录后才能搜索用户"
                guard !Task.isCancelled, self.activeUserQuery == query else { return }
                // 限流等接口提示原样展示，不弹窗打断
                self.userResultsView.setState(.failed(message))
            }
        }
    }

    private func startFirstPageLoad(request: SearchRequest) {
        loadTask?.cancel()
        activeRequest = request
        items = []
        loadedIDs = []
        nextPage = 2
        hasMorePages = true
        isLoadingFirstPage = true
        isRefreshing = false
        isLoadingMore = false
        listView.setItems([])
        listView.hideFirstPageError()
        listView.hideLoadingMore()
        listView.showLoadingSkeleton()
        load(page: 1, request: request, isLoadMore: false, isRefresh: false)
    }

    private func reloadFirstPageForActiveRequest(isRefresh: Bool) {
        guard let request = activeRequest else { return }
        guard !isLoadingFirstPage else { return }
        guard !isLoadingMore else { return }
        loadTask?.cancel()
        if isRefresh {
            isRefreshing = true
        } else {
            items = []
            loadedIDs = []
            nextPage = 2
            hasMorePages = true
            isLoadingFirstPage = true
            listView.setItems([])
            listView.hideFirstPageError()
            listView.showLoadingSkeleton()
        }
        load(page: 1, request: request, isLoadMore: false, isRefresh: isRefresh)
    }

    private func loadMoreIfNeeded(currentIndex: Int, totalCount: Int) {
        guard totalCount > 0 else { return }
        guard hasMorePages else { return }
        guard !isLoadingMore else { return }
        guard !isLoadingFirstPage else { return }
        guard let request = activeRequest else { return }

        AppLog.info(.postList, "触发搜索结果加载更多: page=\(nextPage), currentIndex=\(currentIndex), totalCount=\(totalCount)")
        isLoadingMore = true
        listView.showLoadingMore()
        load(page: nextPage, request: request, isLoadMore: true, isRefresh: false)
    }

    private func load(page: Int, request: SearchRequest, isLoadMore: Bool, isRefresh: Bool) {
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let searchPage = try await self.loadPosts(page: page, request: request)
                await MainActor.run {
                    self.handleLoadedPosts(searchPage, page: page, request: request, isLoadMore: isLoadMore, isRefresh: isRefresh)
                }
            } catch is CancellationError {
                // 被新请求取消，状态由新请求负责更新。
                return
            } catch {
                await MainActor.run {
                    self.handleLoadFailure(error.localizedDescription, request: request, isLoadMore: isLoadMore, isRefresh: isRefresh)
                }
            }
        }
    }

    private func loadPosts(page: Int, request: SearchRequest) async throws -> NodeSeekSearchPage {
        let result = try await service.loadSearchResults(
            query: request.query,
            page: page,
            category: request.category
        )
        switch result {
        case .value(let searchPage):
            await sessionStore.recordSuccess()
            return searchPage
        case .challenge(let challenge):
            let message = await sessionStore.recordChallenge(challenge)
            throw SearchLoadError.challengeRequired(message)
        }
    }

    private func handleLoadedPosts(
        _ searchPage: NodeSeekSearchPage,
        page: Int,
        request: SearchRequest,
        isLoadMore: Bool,
        isRefresh: Bool
    ) {
        guard request == activeRequest else { return }
        let posts = searchPage.posts
        if isLoadMore {
            isLoadingMore = false
            appendPosts(posts, page: page)
            listView.hideLoadingMore()
            return
        }

        isLoadingFirstPage = false
        isRefreshing = false
        items = posts.map(item(for:))
        loadedIDs = Set(posts.map(\.id))
        nextPage = 2
        hasMorePages = !posts.isEmpty
        listView.setItems(items)
        listView.hideFirstPageError()
        listView.hideLoadingSkeleton()
        if isRefresh {
            listView.hideRefreshing()
        }
        if posts.isEmpty {
            // 站点对过短、含违规字符或无结果的搜索只返回一句提示，原样展示给用户
            listView.showEmptyMessage(searchPage.notice ?? "未找到相关帖子，换个关键词试试")
        }
    }

    private func appendPosts(_ posts: [PostSummary], page: Int) {
        guard !posts.isEmpty else {
            hasMorePages = false
            return
        }

        nextPage = page + 1
        var appended = false
        for post in posts where loadedIDs.insert(post.id).inserted {
            items.append(item(for: post))
            appended = true
        }
        if appended {
            listView.setItems(items)
        }
    }

    private func handleLoadFailure(_ message: String, request: SearchRequest, isLoadMore: Bool, isRefresh: Bool) {
        guard request == activeRequest else { return }
        if isLoadMore {
            isLoadingMore = false
            listView.hideLoadingMore()
            showError(message: message)
            return
        }

        isLoadingFirstPage = false
        isRefreshing = false
        if isRefresh {
            listView.hideRefreshing()
            showError(message: message)
        } else {
            listView.hideLoadingSkeleton()
            listView.showFirstPageError(message: message)
        }
    }

    private func item(for post: PostSummary) -> PostListItem {
        PostListItem(post: post, isVisited: visitedStore.isVisited(postID: post.id))
    }

    private func showError(message: String) {
        let alert = UIAlertController(title: "错误", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

extension SearchViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigationController, gestureRecognizer === navigationController.interactivePopGestureRecognizer else {
            return true
        }
        // 有上一页且没有正在进行的转场时才允许侧滑，避免 Tab 根页面或转场中误触发
        return navigationController.viewControllers.count > 1
            && navigationController.topViewController === self
            && navigationController.transitionCoordinator == nil
    }
}

extension SearchViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submitSearch()
        return true
    }

    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        clearResultsForCurrentScope()
        return true
    }
}

extension SearchViewController: PostTextureListViewDelegate {
    func postTextureListView(_ textureListView: PostTextureListView, didSelectPostAt index: Int) {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        visitedStore.markVisited(post: item.post, visitedAt: Date())
        if !item.isVisited {
            items[index] = PostListItem(post: item.post, isVisited: true)
            listView.updateVisitedState(at: index, isVisited: true)
        }

        let route = NodeSeekPostRouteResolver.route(for: item.post.url, baseURL: NodeSeekSite.baseURL)
        let detailViewController = PostDetailRouter.createModule(
            post: item.post,
            page: route?.page ?? 1,
            initialAnchorID: route?.anchorID
        )
        navigationController?.pushViewController(detailViewController, animated: true)
    }

    func postTextureListViewDidRequestRefresh(_ textureListView: PostTextureListView) {
        reloadFirstPageForActiveRequest(isRefresh: true)
    }

    func postTextureListViewDidRequestFirstPageRetry(_ textureListView: PostTextureListView) {
        reloadFirstPageForActiveRequest(isRefresh: false)
    }

    func postTextureListView(_ textureListView: PostTextureListView, didApproachBottomAt index: Int, totalCount: Int) {
        loadMoreIfNeeded(currentIndex: index, totalCount: totalCount)
    }
}

private enum SearchLoadError: LocalizedError {
    case challengeRequired(String)

    var errorDescription: String? {
        switch self {
        case .challengeRequired(let message):
            return message
        }
    }
}
