//
//  PostListViewController+PageContainerDelegate.swift
//  nodeseek
//

import UIKit

extension PostListViewController: PostPageContainerViewControllerDelegate {
    func postPageContainerViewController(
        _ containerView: PostPageContainerViewController,
        didSelectPost post: PostSummary,
        category: PostListCategoryItem
    ) {
        syncSelectedCategoryFromPageContainerIfNeeded(category)
        presenter.didSelectPost(post)
    }

    func postPageContainerViewController(
        _ containerView: PostPageContainerViewController,
        didChangeSortMode sortMode: PostListSortMode,
        category: PostListCategoryItem
    ) {
        syncSelectedCategoryFromPageContainerIfNeeded(category)
        renderSortMode(sortMode)
    }

    func postPageContainerViewController(
        _ containerView: PostPageContainerViewController,
        didScrollTo category: PostListCategoryItem
    ) {
        syncSelectedCategoryFromPageContainerIfNeeded(category)
        renderSortMode(containerView.sortMode(for: category))
    }

    func postPageContainerViewController(
        _ containerView: PostPageContainerViewController,
        didLoadFirstPageFor category: PostListCategoryItem
    ) {
        guard category.isAll else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await autoCheckInRunner(self)
        }
    }

    func postPageContainerViewControllerDidRequestLeadingSideMenu(_ containerView: PostPageContainerViewController) {
        menuButtonFeedbackGenerator.impactOccurred()
        sideMenuViewController.show(animated: true)
    }

    private func syncSelectedCategoryFromPageContainerIfNeeded(_ category: PostListCategoryItem) {
        guard category != selectedCategory else { return }
        selectedCategory = category
        applySelectedCategory(category, syncPage: false, pageAnimated: false)
        presenter.didSelectCategory(category)
    }
}
