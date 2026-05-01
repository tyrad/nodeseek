//
//  PostTexturePageContainerView.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit

protocol PostTexturePageContainerViewDelegate: AnyObject {
    func postTexturePageContainerView(_ containerView: PostTexturePageContainerView, didSelectPostAt index: Int, category: PostListCategory)
    func postTexturePageContainerViewDidRequestRefresh(_ containerView: PostTexturePageContainerView, category: PostListCategory)
    func postTexturePageContainerView(_ containerView: PostTexturePageContainerView, didApproachBottomAt index: Int, totalCount: Int, category: PostListCategory)
    func postTexturePageContainerView(_ containerView: PostTexturePageContainerView, didScrollTo category: PostListCategory)
}

final class PostTexturePageContainerView: UIView {

    weak var delegate: PostTexturePageContainerViewDelegate?

    private weak var parentViewController: UIViewController?
    private var pageViewController: UIPageViewController?
    private var categories: [PostListCategory] = []
    private var hostViewControllers: [PostListCategory: PostTextureListHostViewController] = [:]
    private var currentCategory: PostListCategory?

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(to parentViewController: UIViewController) {
        guard self.parentViewController !== parentViewController else { return }
        self.parentViewController = parentViewController

        let pageVC = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 0]
        )
        pageVC.dataSource = self
        pageVC.delegate = self
        self.pageViewController = pageVC

        parentViewController.addChild(pageVC)
        addSubview(pageVC.view)
        pageVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageVC.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            pageVC.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            pageVC.view.topAnchor.constraint(equalTo: topAnchor),
            pageVC.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        pageVC.didMove(toParent: parentViewController)

        if let pagingScrollView = pageVC.view.subviews.compactMap({ $0 as? UIScrollView }).first {
            pagingScrollView.isDirectionalLockEnabled = true
            pagingScrollView.showsHorizontalScrollIndicator = false
        }

        showInitialPageIfNeeded()
    }

    func configure(categories: [PostListCategory]) {
        guard self.categories != categories else { return }
        self.categories = categories

        var newHosts: [PostListCategory: PostTextureListHostViewController] = [:]
        for category in categories {
            if let existing = hostViewControllers[category] {
                newHosts[category] = existing
            } else {
                let host = PostTextureListHostViewController(category: category)
                host.delegate = self
                newHosts[category] = host
            }
        }
        hostViewControllers = newHosts

        if let current = currentCategory, !categories.contains(current) {
            currentCategory = nil
        }
        showInitialPageIfNeeded()
    }

    func setCurrentCategory(_ category: PostListCategory, animated: Bool) {
        guard categories.contains(category) else { return }
        guard currentCategory != category else { return }
        setCurrentCategory(category, animated: animated, notifyDelegate: false)
    }

    func setPosts(_ posts: [PostSummary], for category: PostListCategory) {
        hostViewControllers[category]?.setPosts(posts)
    }

    func scrollToTop(for category: PostListCategory, animated: Bool) {
        hostViewControllers[category]?.scrollToTop(animated: animated)
    }

    func showLoadingSkeleton(for category: PostListCategory) {
        hostViewControllers[category]?.showLoadingSkeleton()
    }

    func hideLoadingSkeleton(for category: PostListCategory) {
        hostViewControllers[category]?.hideLoadingSkeleton()
    }

    func showLoadingMore(for category: PostListCategory) {
        hostViewControllers[category]?.showLoadingMore()
    }

    func hideLoadingMore(for category: PostListCategory) {
        hostViewControllers[category]?.hideLoadingMore()
    }

    func showRefreshing(for category: PostListCategory) {
        hostViewControllers[category]?.showRefreshing()
    }

    func hideRefreshing(for category: PostListCategory) {
        hostViewControllers[category]?.hideRefreshing()
    }

    private func showInitialPageIfNeeded() {
        guard let category = currentCategory ?? categories.first else { return }
        setCurrentCategory(category, animated: false, notifyDelegate: false)
    }

    private func setCurrentCategory(_ category: PostListCategory, animated: Bool, notifyDelegate: Bool) {
        guard let pageVC = pageViewController else {
            currentCategory = category
            return
        }
        guard let targetVC = hostViewControllers[category] else { return }

        let direction: UIPageViewController.NavigationDirection = {
            guard let current = currentCategory,
                  let fromIndex = categories.firstIndex(of: current),
                  let toIndex = categories.firstIndex(of: category) else {
                return .forward
            }
            return toIndex >= fromIndex ? .forward : .reverse
        }()

        currentCategory = category
        pageVC.setViewControllers([targetVC], direction: direction, animated: animated) { [weak self] completed in
            guard let self else { return }
            if notifyDelegate, completed || !animated {
                self.delegate?.postTexturePageContainerView(self, didScrollTo: category)
            }
        }
    }
}

extension PostTexturePageContainerView: UIPageViewControllerDataSource {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let host = viewController as? PostTextureListHostViewController,
              let index = categories.firstIndex(of: host.category),
              index > 0 else {
            return nil
        }
        return hostViewControllers[categories[index - 1]]
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let host = viewController as? PostTextureListHostViewController,
              let index = categories.firstIndex(of: host.category),
              index < categories.count - 1 else {
            return nil
        }
        return hostViewControllers[categories[index + 1]]
    }
}

extension PostTexturePageContainerView: UIPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard finished, completed,
              let current = pageViewController.viewControllers?.first as? PostTextureListHostViewController else {
            return
        }
        currentCategory = current.category
        delegate?.postTexturePageContainerView(self, didScrollTo: current.category)
    }
}

extension PostTexturePageContainerView: PostTextureListHostViewControllerDelegate {
    func postTextureListHostViewController(
        _ viewController: PostTextureListHostViewController,
        didSelectPostAt index: Int
    ) {
        let category = viewController.category
        delegate?.postTexturePageContainerView(self, didSelectPostAt: index, category: category)
    }

    func postTextureListHostViewController(
        _ viewController: PostTextureListHostViewController,
        didApproachBottomAt index: Int,
        totalCount: Int
    ) {
        let category = viewController.category
        delegate?.postTexturePageContainerView(self, didApproachBottomAt: index, totalCount: totalCount, category: category)
    }

    func postTextureListHostViewControllerDidRequestRefresh(_ viewController: PostTextureListHostViewController) {
        let category = viewController.category
        delegate?.postTexturePageContainerViewDidRequestRefresh(self, category: category)
    }
}

protocol PostTextureListHostViewControllerDelegate: AnyObject {
    func postTextureListHostViewController(_ viewController: PostTextureListHostViewController, didSelectPostAt index: Int)
    func postTextureListHostViewControllerDidRequestRefresh(_ viewController: PostTextureListHostViewController)
    func postTextureListHostViewController(_ viewController: PostTextureListHostViewController, didApproachBottomAt index: Int, totalCount: Int)
}

final class PostTextureListHostViewController: UIViewController {
    let category: PostListCategory
    weak var delegate: PostTextureListHostViewControllerDelegate?

    private let listView = PostTextureListView()

    init(category: PostListCategory) {
        self.category = category
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
    }

    func setPosts(_ posts: [PostSummary]) {
        loadViewIfNeeded()
        listView.setPosts(posts)
    }

    func showLoadingSkeleton() {
        loadViewIfNeeded()
        listView.showLoadingSkeleton()
    }

    func hideLoadingSkeleton() {
        loadViewIfNeeded()
        listView.hideLoadingSkeleton()
    }

    func showLoadingMore() {
        loadViewIfNeeded()
        listView.showLoadingMore()
    }

    func hideLoadingMore() {
        loadViewIfNeeded()
        listView.hideLoadingMore()
    }

    func showRefreshing() {
        loadViewIfNeeded()
        listView.showRefreshing()
    }

    func hideRefreshing() {
        loadViewIfNeeded()
        listView.hideRefreshing()
    }

    func scrollToTop(animated: Bool) {
        loadViewIfNeeded()
        listView.scrollToTop(animated: animated)
    }
}

extension PostTextureListHostViewController: PostTextureListViewDelegate {
    func postTextureListView(_ textureListView: PostTextureListView, didSelectPostAt index: Int) {
        delegate?.postTextureListHostViewController(self, didSelectPostAt: index)
    }

    func postTextureListViewDidRequestRefresh(_ textureListView: PostTextureListView) {
        delegate?.postTextureListHostViewControllerDidRequestRefresh(self)
    }

    func postTextureListView(_ textureListView: PostTextureListView, didApproachBottomAt index: Int, totalCount: Int) {
        delegate?.postTextureListHostViewController(self, didApproachBottomAt: index, totalCount: totalCount)
    }
}
