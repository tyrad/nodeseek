//
//  PostTextureListHostViewController.swift
//  nodeseek
//

import UIKit

final class PostTextureListHostViewController: UIViewController {
    let category: PostListCategoryItem

    private let presenter: PostTextureListHostPresenterProtocol
    private let listView = PostTextureListView()
    /// 再次点按 Tab 刷新时弹出的加载提示，刷新结束时收起。
    private weak var tabRefreshToast: UIView?

    var onListScroll: ((UIScrollView) -> Void)? {
        get { listView.onScroll }
        set { listView.onScroll = newValue }
    }

    init(
        category: PostListCategoryItem,
        presenter: PostTextureListHostPresenterProtocol
    ) {
        self.category = category
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBackground
        listView.delegate = self
        listView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(listView)
        NSLayoutConstraint.activate([
            listView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listView.topAnchor.constraint(equalTo: view.topAnchor),
            listView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        presenter.viewDidLoad()
    }

    var currentSortMode: PostListSortMode {
        presenter.currentSortMode
    }

    func toggleSortMode() -> PostListSortMode {
        presenter.toggleSortMode()
    }

    func reloadFirstPage() {
        presenter.reloadFirstPage()
    }

    func scrollToTop(animated: Bool) {
        loadViewIfNeeded()
        listView.scrollToTop(animated: animated)
    }

    /// 底部 Tab 再次点按：回到顶部，并在后台静默重新拉第一页。
    func refreshFromTabReselect() {
        scrollToTop(animated: true)
        presenter.didRequestTabReselectRefresh()
    }

    func refreshVisibleAppearanceForCurrentTraits() {
        guard isViewLoaded else { return }
        listView.refreshVisibleAppearanceForCurrentTraits()
    }
}

extension PostTextureListHostViewController: PostTextureListViewDelegate {
    func postTextureListView(_ textureListView: PostTextureListView, didSelectPostAt index: Int) {
        presenter.didSelectPost(at: index)
    }

    func postTextureListViewDidRequestRefresh(_ textureListView: PostTextureListView) {
        presenter.didRequestRefresh()
    }

    func postTextureListViewDidRequestFirstPageRetry(_ textureListView: PostTextureListView) {
        presenter.didRequestFirstPageRetry()
    }

    func postTextureListView(_ textureListView: PostTextureListView, didApproachBottomAt index: Int, totalCount: Int) {
        presenter.didApproachBottom(at: index, totalCount: totalCount)
    }
}

extension PostTextureListHostViewController: PostTextureListHostViewProtocol {
    func setItems(_ items: [PostListItem]) {
        listView.setItems(items)
    }

    func showLoadingSkeleton() {
        listView.showLoadingSkeleton()
    }

    func hideLoadingSkeleton() {
        listView.hideLoadingSkeleton()
    }

    func showFirstPageError(message: String) {
        listView.showFirstPageError(message: message)
    }

    func hideFirstPageError() {
        listView.hideFirstPageError()
    }

    func showTabRefreshLoading() {
        listView.playRefreshFeedback()
        // 时长只是兜底，正常由刷新结束时收起
        tabRefreshToast = BottomToast.show("正在刷新…", style: .progress, in: view, duration: 15)
    }

    func hideTabRefreshLoading(failureMessage: String?) {
        if isViewLoaded {
            listView.settleAtTopIfIdle()
        }
        if let tabRefreshToast {
            BottomToast.dismiss(tabRefreshToast)
        }
        tabRefreshToast = nil
        // 已切到别的 Tab 时不再弹失败提示，避免出现在不相关的页面上
        guard let failureMessage, isViewLoaded, view.window != nil else { return }
        BottomToast.show(failureMessage, style: .failure, in: view)
    }

    func hideRefreshing() {
        listView.hideRefreshing()
    }

    func showLoadingMore() {
        listView.showLoadingMore()
    }

    func hideLoadingMore() {
        listView.hideLoadingMore()
    }

    func updateVisitedState(at index: Int, isVisited: Bool) {
        listView.updateVisitedState(at: index, isVisited: isVisited)
    }
}
