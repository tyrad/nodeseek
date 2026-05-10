//
//  PostTextureListHostViewController.swift
//  nodeseek
//

import UIKit

final class PostTextureListHostViewController: UIViewController {
    let category: PostListCategory

    private let presenter: PostTextureListHostPresenterProtocol
    private let listView = PostTextureListView()

    init(
        category: PostListCategory,
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
        view.backgroundColor = .systemBackground
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
