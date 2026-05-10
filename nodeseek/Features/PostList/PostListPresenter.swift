//
//  PostListPresenter.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

class PostListPresenter: PostListPresenterProtocol {

    // MARK: - Properties
    private weak var view: PostListViewProtocol?
    private let router: PostListRouterProtocol
    private let visitedStore: VisitedPostStoreProtocol
    private let categories = PostListCategory.allCases
    private var currentCategory: PostListCategory = .all

    // MARK: - Initialization
    init(
        router: PostListRouterProtocol,
        visitedStore: VisitedPostStoreProtocol = EmptyVisitedPostStore()
    ) {
        self.router = router
        self.visitedStore = visitedStore
    }

    // MARK: - Setup
    func setView(_ view: PostListViewProtocol) {
        self.view = view
    }

    // MARK: - Methods
    func viewDidLoad() {
        view?.renderCategories(categories, selected: currentCategory)
        view?.renderSortMode(.replyTime)
    }

    func didSelectCategory(_ category: PostListCategory) {
        guard category != currentCategory else { return }
        currentCategory = category
    }

    func didReselectCategory(_ category: PostListCategory) {
        guard category == currentCategory else {
            didSelectCategory(category)
            return
        }
        view?.reloadSelectedCategory()
    }

    func didTapLogin() {
        router.navigateToLogin { [weak self] in
            self?.view?.reloadSelectedCategory()
        }
    }

    func didTapAccountProfile(profileURL: URL) {
        router.navigateToUserProfile(profileURL: profileURL)
    }

    func didTapNewDiscussion() {
        router.navigateToNewDiscussion()
    }

    func didTapCheckIn() {
        router.navigateToCheckIn(boardURL: NodeSeekSite.boardURL)
    }

    func didTapNotification(url: URL) {
        router.navigateToNotification(notificationURL: url)
    }

    func didTapRecentVisited() {
        router.navigateToRecentVisitedPosts(visitedStore: visitedStore)
    }

    func didTapSearch() {
        router.navigateToSearch()
    }

    func didTapSettings() {
        #if DEBUG
        let detailTestAction: (@MainActor () -> Void)? = { [weak self] in
            self?.didTapDetailTest()
        }
        #else
        let detailTestAction: (@MainActor () -> Void)? = nil
        #endif

        router.navigateToSettings(
            onLogout: { [weak self] in
                self?.view?.reloadSelectedCategory()
            },
            onLogFile: { [weak self] in
                self?.didTapLogFile()
            },
            onDetailTest: detailTestAction
        )
    }

    func didTapLogFile() {
        router.navigateToLogFile()
    }

    #if DEBUG
    func didTapDetailTest() {
        guard NodeSeekDebugConfig.enablePostDetailTestEntry else { return }
        view?.openDetailTestURLFromPasteboard()
    }

    func didSubmitDetailTestURL(_ rawURL: String) {
        guard NodeSeekDebugConfig.enablePostDetailTestEntry else { return }
        guard let target = PostDetailTestTarget(rawValue: rawURL) else {
            view?.showError(message: "剪贴板里没有可打开的 NodeSeek 帖子详情链接，例如 \(NodeSeekSite.postURL(id: "705039", page: 1).absoluteString)")
            return
        }

        router.navigateToPostDetail(
            post: target.post,
            page: target.page,
            initialAnchorID: target.anchorID
        )
    }
    #endif

    func didSelectPost(_ post: PostSummary) {
        routeToPostDetail(post)
    }
}

private extension PostListPresenter {
    func routeToPostDetail(_ post: PostSummary) {
        if let route = NodeSeekPostRouteResolver.route(for: post.url, baseURL: NodeSeekSite.baseURL) {
            router.navigateToPostDetail(
                post: post,
                page: route.page,
                initialAnchorID: route.anchorID
            )
        } else {
            router.navigateToPostDetail(post: post)
        }
    }
}
