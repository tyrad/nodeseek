//
//  PostListViewController+PageContainerDelegate.swift
//  nodeseek
//

import UIKit

extension PostListViewController: PostPageContainerViewControllerDelegate {
    func postPageContainerViewController(
        _ containerView: PostPageContainerViewController,
        didSelectPost post: PostSummary,
        category: PostListCategory
    ) {
        syncSelectedCategoryFromPageContainerIfNeeded(category)
        presenter.didSelectPost(post)
    }

    func postPageContainerViewController(
        _ containerView: PostPageContainerViewController,
        didChangeSortMode sortMode: PostListSortMode,
        category: PostListCategory
    ) {
        syncSelectedCategoryFromPageContainerIfNeeded(category)
        renderSortMode(sortMode)
    }

    func postPageContainerViewController(
        _ containerView: PostPageContainerViewController,
        didScrollTo category: PostListCategory
    ) {
        syncSelectedCategoryFromPageContainerIfNeeded(category)
        renderSortMode(containerView.sortMode(for: category))
    }

    func postPageContainerViewControllerDidRequestLeadingSideMenu(_ containerView: PostPageContainerViewController) {
        menuButtonFeedbackGenerator.impactOccurred()
        sideMenuViewController.show(animated: true)
    }

    private func syncSelectedCategoryFromPageContainerIfNeeded(_ category: PostListCategory) {
        guard category != selectedCategory else { return }
        selectedCategory = category
        applySelectedCategory(category, syncPage: false, pageAnimated: false)
        presenter.didSelectCategory(category)
    }
}
