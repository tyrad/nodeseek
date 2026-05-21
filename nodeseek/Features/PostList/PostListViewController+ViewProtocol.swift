//
//  PostListViewController+ViewProtocol.swift
//  nodeseek
//

import UIKit

extension PostListViewController: PostListViewProtocol {
    func showError(message: String) {
        let alert = UIAlertController(title: "错误", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    #if DEBUG
    func openDetailTestURLFromPasteboard() {
        guard NodeSeekDebugConfig.enablePostDetailTestEntry else { return }
        presenter.didSubmitDetailTestURL(detailTestURLProvider())
    }
    #endif

    func renderCategories(_ categories: [PostListCategoryItem], selected: PostListCategoryItem) {
        let categoriesChanged = categories != self.categories
        if categoriesChanged {
            self.categories = categories
            rebuildCategoryButtons()
            pageContainerViewController.configure(categories: categories)
        }
        selectedCategory = selected
        applySelectedCategory(selected, syncPage: categoriesChanged, pageAnimated: false)
    }

    func renderSortMode(_ sortMode: PostListSortMode) {
        currentSortMode = sortMode
        sortToggleButton.apply(sortMode: sortMode, expanded: isSortToggleExpanded)
        if isSortToggleExpanded {
            sortToggleWidthConstraint?.constant = PostListSortToggleButton.expandedWidth(for: sortMode.accessibilityTitle)
        }
    }

    func reloadSelectedCategory() {
        pageContainerViewController.reloadFirstPage(for: selectedCategory)
    }
}
