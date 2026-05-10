//
//  PostListContract.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

// MARK: - View Protocol (Presenter -> View)
protocol PostListViewProtocol: AnyObject {
    func showError(message: String)
    #if DEBUG
    func openDetailTestURLFromPasteboard()
    #endif
    func renderCategories(_ categories: [PostListCategory], selected: PostListCategory)
    func renderSortMode(_ sortMode: PostListSortMode)
    func reloadSelectedCategory()
}

// MARK: - Presenter Protocol (View -> Presenter)
protocol PostListPresenterProtocol: AnyObject {
    func viewDidLoad()
    func didSelectCategory(_ category: PostListCategory)
    func didReselectCategory(_ category: PostListCategory)
    func didTapLogin()
    func didTapAccountProfile(profileURL: URL)
    func didTapNewDiscussion()
    func didTapCheckIn()
    func didTapNotification(url: URL)
    func didTapRecentVisited()
    func didTapSearch()
    func didTapSettings()
    func didTapLogFile()
    #if DEBUG
    func didTapDetailTest()
    func didSubmitDetailTestURL(_ rawURL: String)
    #endif
    func didSelectPost(_ post: PostSummary)
}

// MARK: - Router Protocol (Presenter -> Router)
protocol PostListRouterProtocol: AnyObject {
    func navigateToPostDetail(post: PostSummary)
    func navigateToPostDetail(post: PostSummary, page: Int)
    func navigateToPostDetail(post: PostSummary, page: Int, initialAnchorID: String?)
    func navigateToLogin(onClose: @escaping @MainActor () -> Void)
    func navigateToUserProfile(profileURL: URL)
    func navigateToNewDiscussion()
    func navigateToCheckIn(boardURL: URL)
    func navigateToNotification(notificationURL: URL)
    func navigateToRecentVisitedPosts(visitedStore: VisitedPostStoreProtocol)
    func navigateToSearch()
    func navigateToSettings(
        onLogout: @escaping @MainActor () -> Void,
        onLogFile: @escaping @MainActor () -> Void,
        onDetailTest: (@MainActor () -> Void)?
    )
    func navigateToLogFile()
}
