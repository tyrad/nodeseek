//
//  SearchViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/5/3.
//

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
    private let categories = PostListCategory.allCases.filter { category in
        category != .df && category != .award
    }

    private var selectedCategory: PostListCategory = .all
    private var activeRequest: SearchRequest?
    private var items: [PostListItem] = []
    private var loadedIDs: Set<String> = []
    private var nextPage = 2
    private var hasMorePages = true
    private var hasSearched = false
    private var isLoadingFirstPage = false
    private var isRefreshing = false
    private var isLoadingMore = false
    private var formTopConstraint: NSLayoutConstraint?
    private var loadTask: Task<Void, Never>?

    private let formContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let categorySelectorButton: UIButton = {
        var configuration = UIButton.Configuration.bordered()
        configuration.title = "全部"
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .fixed
        configuration.background.cornerRadius = 8
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 14, weight: .semibold)
            return outgoing
        }

        let button = UIButton(type: .system)
        button.configuration = configuration
        button.showsMenuAsPrimaryAction = true
        button.accessibilityIdentifier = "search-category-selector-button"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let keywordTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "输入关键字"
        textField.borderStyle = .none
        textField.backgroundColor = .systemBackground
        textField.layer.cornerRadius = 8
        textField.layer.borderWidth = 1.2
        textField.layer.borderColor = UIColor.systemGray3.cgColor
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        textField.leftViewMode = .always
        textField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 1))
        textField.rightViewMode = .unlessEditing
        textField.clearButtonMode = .whileEditing
        textField.returnKeyType = .search
        textField.textContentType = .none
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.accessibilityIdentifier = "search-keyword-text-field"
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    private let searchButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "搜索"
        configuration.baseBackgroundColor = .label
        configuration.baseForegroundColor = .systemBackground
        configuration.cornerStyle = .fixed
        configuration.background.cornerRadius = 8
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 8, bottom: 9, trailing: 8)
        configuration.titleLineBreakMode = .byTruncatingTail

        let button = UIButton(type: .system)
        button.configuration = configuration
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.85
        button.accessibilityIdentifier = "search-submit-button"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var inputRowStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [categorySelectorButton, keywordTextField, searchButton])
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var formStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [inputRowStackView])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let recentSearchesTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "最近搜索"
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .label
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

    private lazy var recentSearchesHeaderStackView: UIStackView = {
        let spacer = UIView()
        let stack = UIStackView(arrangedSubviews: [recentSearchesTitleLabel, spacer, clearRecentSearchesButton])
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

    init(
        service: NodeSeekService = SearchViewController.makeDefaultService(),
        sessionStore: NodeSeekSessionStore = .shared,
        visitedStore: VisitedPostStoreProtocol? = nil,
        searchHistoryStore: SearchHistoryStore = SearchHistoryStore(),
        searchPreferenceStore: SearchPreferenceStore = SearchPreferenceStore()
    ) {
        self.service = service
        self.sessionStore = sessionStore
        self.visitedStore = visitedStore ?? VisitedPostStore.shared
        self.searchHistoryStore = searchHistoryStore
        self.searchPreferenceStore = searchPreferenceStore
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
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        let rememberedCategory = searchPreferenceStore.category()
        applySelectedCategory(categories.contains(rememberedCategory) ? rememberedCategory : .all)
        renderRecentSearches()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    private func setupUI() {
        title = "搜一搜"
        view.backgroundColor = .systemBackground
        keywordTextField.delegate = self
        listView.delegate = self
        searchButton.addTarget(self, action: #selector(searchButtonTapped), for: .touchUpInside)
        clearRecentSearchesButton.addTarget(self, action: #selector(clearRecentSearchesButtonTapped), for: .touchUpInside)

        view.addSubview(formContainerView)
        view.addSubview(recentSearchesContainerView)
        view.addSubview(listView)
        formContainerView.addSubview(formStackView)

        let formTopConstraint = formContainerView.topAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.topAnchor,
            constant: 104
        )
        formTopConstraint.isActive = true
        self.formTopConstraint = formTopConstraint

        NSLayoutConstraint.activate([
            formContainerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            formContainerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),

            formStackView.leadingAnchor.constraint(equalTo: formContainerView.leadingAnchor),
            formStackView.trailingAnchor.constraint(equalTo: formContainerView.trailingAnchor),
            formStackView.topAnchor.constraint(equalTo: formContainerView.topAnchor),
            formStackView.bottomAnchor.constraint(equalTo: formContainerView.bottomAnchor),

            categorySelectorButton.widthAnchor.constraint(equalToConstant: 94),
            searchButton.widthAnchor.constraint(equalToConstant: 68),
            keywordTextField.heightAnchor.constraint(equalToConstant: 40),

            recentSearchesContainerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            recentSearchesContainerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            recentSearchesContainerView.topAnchor.constraint(equalTo: formContainerView.bottomAnchor, constant: 18),

            listView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listView.topAnchor.constraint(equalTo: formContainerView.bottomAnchor, constant: 12),
            listView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func renderRecentSearches() {
        recentSearchesTagCloudView.setButtons([])

        let records = searchHistoryStore.records().filter { record in
            categories.contains(record.category)
        }
        recentSearchesContainerView.isHidden = hasSearched || records.isEmpty
        guard !recentSearchesContainerView.isHidden else { return }

        let buttons = records.enumerated().map { index, record in
            makeRecentSearchButton(record: record, index: index)
        }
        recentSearchesTagCloudView.setButtons(buttons)
    }

    private func makeRecentSearchButton(record: SearchHistoryRecord, index: Int) -> UIButton {
        var configuration = UIButton.Configuration.bordered()
        configuration.title = record.displayTitle
        configuration.baseForegroundColor = .label
        configuration.background.backgroundColor = .secondarySystemBackground
        configuration.background.cornerRadius = 8
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 15, weight: .regular)
            return outgoing
        }

        let button = UIButton(type: .system)
        button.configuration = configuration
        button.contentHorizontalAlignment = .leading
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

    private func pinFormToTopIfNeeded() {
        guard !hasSearched else { return }
        hasSearched = true
        formTopConstraint?.constant = 16
        listView.isHidden = false
        recentSearchesContainerView.isHidden = true

        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.view.layoutIfNeeded()
        }
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

    @objc private func searchButtonTapped() {
        submitSearch()
    }

    @objc private func clearRecentSearchesButtonTapped() {
        searchHistoryStore.clear()
        renderRecentSearches()
    }

    private func submitSearch() {
        let query = keywordTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else {
            showError(message: "请输入搜索关键字。")
            return
        }

        view.endEditing(true)
        searchHistoryStore.record(query: query, category: selectedCategory)
        searchPreferenceStore.rememberCategory(selectedCategory)
        renderRecentSearches()
        pinFormToTopIfNeeded()
        startFirstPageLoad(request: SearchRequest(query: query, category: selectedCategory))
    }

    private func submitSearch(record: SearchHistoryRecord) {
        keywordTextField.text = record.query
        applySelectedCategory(record.category)
        submitSearch()
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
            listView.showRefreshing()
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
                let posts = try await self.loadPosts(page: page, request: request)
                await MainActor.run {
                    self.handleLoadedPosts(posts, page: page, request: request, isLoadMore: isLoadMore, isRefresh: isRefresh)
                }
            } catch {
                await MainActor.run {
                    self.handleLoadFailure(error.localizedDescription, request: request, isLoadMore: isLoadMore, isRefresh: isRefresh)
                }
            }
        }
    }

    private func loadPosts(page: Int, request: SearchRequest) async throws -> [PostSummary] {
        let result = try await service.loadSearchResults(
            query: request.query,
            page: page,
            category: request.category
        )
        switch result {
        case .value(let posts):
            await sessionStore.recordSuccess()
            return posts
        case .challenge(let challenge):
            let message = await sessionStore.recordChallenge(challenge)
            throw SearchLoadError.challengeRequired(message)
        }
    }

    private func handleLoadedPosts(
        _ posts: [PostSummary],
        page: Int,
        request: SearchRequest,
        isLoadMore: Bool,
        isRefresh: Bool
    ) {
        guard request == activeRequest else { return }
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

extension SearchViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submitSearch()
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
