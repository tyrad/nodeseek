//
//  PostPageContainerViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit

protocol PostPageContainerViewControllerDelegate: AnyObject {
    func postPageContainerViewController(_ viewController: PostPageContainerViewController, didSelectPost post: PostSummary, category: PostListCategoryItem)
    func postPageContainerViewController(_ viewController: PostPageContainerViewController, didChangeSortMode sortMode: PostListSortMode, category: PostListCategoryItem)
    func postPageContainerViewController(_ viewController: PostPageContainerViewController, didScrollTo category: PostListCategoryItem)
    func postPageContainerViewControllerDidRequestLeadingSideMenu(_ viewController: PostPageContainerViewController)
}

final class PostPageContainerViewController: UIPageViewController {

    weak var eventDelegate: PostPageContainerViewControllerDelegate?

    var categories: [PostListCategoryItem] = []
    var hostViewControllers: [PostListCategoryItem: PostTextureListHostViewController] = [:]
    private(set) var currentCategory: PostListCategoryItem?
    weak var pagingScrollView: UIScrollView?
    var maximumLeadingBoundaryPullDistance: CGFloat = 0
    private let visitedStore: VisitedPostStoreProtocol

    init(
        visitedStore: VisitedPostStoreProtocol
    ) {
        self.visitedStore = visitedStore
        super.init(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 0]
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupPaging()
        showCurrentOrFirstPage()
    }

    func configure(categories: [PostListCategoryItem]) {
        guard self.categories != categories else { return }
        self.categories = categories

        var newHosts: [PostListCategoryItem: PostTextureListHostViewController] = [:]
        for category in categories {
            if let existing = hostViewControllers[category] {
                newHosts[category] = existing
            } else {
                let host = PostTextureListHostRouter.createModule(
                    category: category,
                    visitedStore: visitedStore,
                    delegate: self
                )
                newHosts[category] = host
            }
        }
        hostViewControllers = newHosts

        if let current = currentCategory, !categories.contains(current) {
            currentCategory = nil
        }
        showCurrentOrFirstPage()
    }

    func setCurrentCategory(_ category: PostListCategoryItem, animated: Bool) {
        guard categories.contains(category) else { return }
        guard currentCategory != category else { return }
        setCurrentCategory(category, animated: animated, notifyDelegate: false)
    }

    func sortMode(for category: PostListCategoryItem) -> PostListSortMode {
        hostViewControllers[category]?.currentSortMode ?? .replyTime
    }

    @discardableResult
    func toggleSortMode(for category: PostListCategoryItem) -> PostListSortMode {
        guard let host = hostViewControllers[category] else { return .replyTime }
        return host.toggleSortMode()
    }

    func reloadFirstPage(for category: PostListCategoryItem) {
        hostViewControllers[category]?.reloadFirstPage()
    }

    func scrollToTop(for category: PostListCategoryItem, animated: Bool) {
        hostViewControllers[category]?.scrollToTop(animated: animated)
    }

    func refreshVisibleAppearanceForCurrentTraits() {
        hostViewControllers.values.forEach { $0.refreshVisibleAppearanceForCurrentTraits() }
    }

    private func setupPaging() {
        dataSource = self
        delegate = self

        if let pagingScrollView = view.subviews.compactMap({ $0 as? UIScrollView }).first {
            pagingScrollView.isDirectionalLockEnabled = true
            pagingScrollView.showsHorizontalScrollIndicator = false
            installLeadingBoundaryPanListener(on: pagingScrollView)
        }
    }

    private func showCurrentOrFirstPage() {
        guard let category = currentCategory ?? categories.first else { return }
        setCurrentCategory(category, animated: false, notifyDelegate: false)
    }

    private func setCurrentCategory(_ category: PostListCategoryItem, animated: Bool, notifyDelegate: Bool) {
        guard let targetVC = hostViewControllers[category] else { return }
        if currentCategory == category,
           viewControllers?.first === targetVC {
            return
        }

        let direction: UIPageViewController.NavigationDirection = {
            guard let current = currentCategory,
                  let fromIndex = categories.firstIndex(of: current),
                  let toIndex = categories.firstIndex(of: category) else {
                return .forward
            }
            return toIndex >= fromIndex ? .forward : .reverse
        }()

        currentCategory = category
        setViewControllers([targetVC], direction: direction, animated: animated) { [weak self] completed in
            guard let self else { return }
            if notifyDelegate, completed || !animated {
                self.eventDelegate?.postPageContainerViewController(self, didScrollTo: category)
            }
        }
    }

    func updateCurrentCategoryAfterPaging(_ category: PostListCategoryItem) {
        currentCategory = category
    }
}

extension PostPageContainerViewController: PostTextureListHostPresenterDelegate {
    func postTextureListHostDidSelectPost(_ post: PostSummary, category: PostListCategoryItem) {
        eventDelegate?.postPageContainerViewController(self, didSelectPost: post, category: category)
    }

    func postTextureListHostDidChangeSortMode(_ sortMode: PostListSortMode, category: PostListCategoryItem) {
        eventDelegate?.postPageContainerViewController(self, didChangeSortMode: sortMode, category: category)
    }
}
