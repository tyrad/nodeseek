//
//  PostCategoryPreferencesViewControllerTests.swift
//  nodeseekTests
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct PostCategoryPreferencesViewControllerTests {
    @Test func editorShowsVisibleAndHiddenSectionsWithAllFixedFirst() throws {
        let store = makeStore()
        let viewController = PostCategoryPreferencesViewController(store: store)
        viewController.loadViewIfNeeded()

        #expect(viewController.title == "首页分类")
        #expect(viewController.tableView.style == .insetGrouped)
        #expect(viewController.tableView.accessibilityIdentifier == "post-category-preferences-table-view")
        #expect(viewController.tableView.isEditing == false)
        #expect(viewController.navigationItem.rightBarButtonItems?.count == 1)
        #expect(viewController.tableView.numberOfSections == 3)
        #expect(viewController.tableView.numberOfRows(inSection: 0) == PostListCategory.allCases.count)
        #expect(viewController.tableView.numberOfRows(inSection: 1) == 0)
        #expect(viewController.tableView.numberOfRows(inSection: 2) == 1)
        #expect(viewController.tableView.dataSource?.tableView?(viewController.tableView, titleForHeaderInSection: 0) == "显示")
        #expect(viewController.tableView.dataSource?.tableView?(viewController.tableView, titleForHeaderInSection: 1) == "隐藏")

        let allCell = try #require(viewController.tableView.dataSource?.tableView(
            viewController.tableView,
            cellForRowAt: IndexPath(row: 0, section: 0)
        ))
        #expect(allCell.textLabel?.text == "全部")
        #expect(allCell.detailTextLabel?.text == "固定第一位")
        #expect(viewController.tableView.dataSource?.tableView?(viewController.tableView, canMoveRowAt: IndexPath(row: 0, section: 0)) == false)
        #expect(viewController.tableView.dataSource?.tableView?(viewController.tableView, canEditRowAt: IndexPath(row: 0, section: 0)) == false)

        let visibleCell = try #require(viewController.tableView.dataSource?.tableView(
            viewController.tableView,
            cellForRowAt: IndexPath(row: 1, section: 0)
        ))
        #expect(visibleCell.textLabel?.text == "日常")
        #expect(visibleCell.detailTextLabel?.text == nil)
        #expect(viewController.tableView.dataSource?.tableView?(viewController.tableView, canMoveRowAt: IndexPath(row: 1, section: 0)) == true)
        #expect(viewController.tableView.dataSource?.tableView?(viewController.tableView, canEditRowAt: IndexPath(row: 1, section: 0)) == true)
        #expect(viewController.tableView.delegate?.tableView?(viewController.tableView, editingStyleForRowAt: IndexPath(row: 1, section: 0)) == .some(.delete))
        #expect(viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            titleForDeleteConfirmationButtonForRowAt: IndexPath(row: 1, section: 0)
        ) == "隐藏")

        viewController.setEditing(true, animated: false)

        #expect(viewController.tableView.isEditing == true)
    }

    @Test func editorMovesVisibleCategoriesWithoutCrossingAll() throws {
        let store = makeStore()
        let viewController = PostCategoryPreferencesViewController(store: store)
        viewController.loadViewIfNeeded()
        let source = IndexPath(row: 2, section: 0)

        let target = viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            targetIndexPathForMoveFromRowAt: source,
            toProposedIndexPath: IndexPath(row: 0, section: 0)
        )
        let crossSectionTarget = viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            targetIndexPathForMoveFromRowAt: source,
            toProposedIndexPath: IndexPath(row: 0, section: 1)
        )

        #expect(target == IndexPath(row: 1, section: 0))
        #expect(crossSectionTarget == source)

        viewController.tableView.dataSource?.tableView?(
            viewController.tableView,
            moveRowAt: IndexPath(row: 2, section: 0),
            to: IndexPath(row: 1, section: 0)
        )

        #expect(Array(store.visibleCategories.prefix(3)) == [.all, .tech, .daily])
    }

    @Test func editorHidesAndRestoresCategories() throws {
        let store = makeStore()
        let viewController = PostCategoryPreferencesViewController(store: store)
        viewController.loadViewIfNeeded()

        #expect(viewController.tableView.allowsSelectionDuringEditing == true)

        viewController.tableView.dataSource?.tableView?(
            viewController.tableView,
            commit: .delete,
            forRowAt: IndexPath(row: 1, section: 0)
        )

        #expect(store.visibleCategories.contains(.daily) == false)
        #expect(store.hiddenCategories == [.daily])
        #expect(viewController.tableView.numberOfRows(inSection: 1) == 1)

        let hiddenCell = try #require(viewController.tableView.dataSource?.tableView(
            viewController.tableView,
            cellForRowAt: IndexPath(row: 0, section: 1)
        ))
        #expect(hiddenCell.textLabel?.text == "日常")
        #expect(hiddenCell.detailTextLabel?.text == nil)

        viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            didSelectRowAt: IndexPath(row: 0, section: 1)
        )

        #expect(store.hiddenCategories.isEmpty)
        #expect(store.visibleCategories.last == .daily)
    }

    @Test func editorRestoresHiddenCategoryWithInsertAction() {
        let store = makeStore()
        let viewController = PostCategoryPreferencesViewController(store: store)
        viewController.loadViewIfNeeded()

        store.hideCategory(.tech)

        viewController.tableView.dataSource?.tableView?(
            viewController.tableView,
            commit: .insert,
            forRowAt: IndexPath(row: 0, section: 1)
        )

        #expect(store.hiddenCategories.isEmpty)
        #expect(store.visibleCategories.last == .tech)
    }

    @Test func editorIgnoresStaleIndexPaths() {
        let store = makeStore()
        let viewController = PostCategoryPreferencesViewController(store: store)
        viewController.loadViewIfNeeded()

        viewController.tableView.dataSource?.tableView?(
            viewController.tableView,
            commit: .delete,
            forRowAt: IndexPath(row: 999, section: 0)
        )
        viewController.tableView.dataSource?.tableView?(
            viewController.tableView,
            commit: .insert,
            forRowAt: IndexPath(row: 0, section: 1)
        )
        viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            didSelectRowAt: IndexPath(row: 0, section: 1)
        )

        #expect(store.visibleCategories == PostListCategory.allCases)
        #expect(store.hiddenCategories.isEmpty)
    }

    @Test func editorRefreshesWhenStoreChangesExternally() throws {
        let store = makeStore()
        let viewController = PostCategoryPreferencesViewController(store: store)
        viewController.loadViewIfNeeded()

        #expect(viewController.tableView.numberOfRows(inSection: 0) == PostListCategory.allCases.count)
        #expect(viewController.tableView.numberOfRows(inSection: 1) == 0)

        store.hideCategory(.tech)

        #expect(viewController.tableView.numberOfRows(inSection: 1) == 1)
        let hiddenCell = try #require(viewController.tableView.dataSource?.tableView(
            viewController.tableView,
            cellForRowAt: IndexPath(row: 0, section: 1)
        ))
        #expect(hiddenCell.textLabel?.text == "技术")
    }

    @Test func editorFooterExplainsAllCategoryRule() throws {
        let viewController = PostCategoryPreferencesViewController(store: makeStore())
        viewController.loadViewIfNeeded()

        let footer = viewController.tableView.dataSource?.tableView?(
            viewController.tableView,
            titleForFooterInSection: 0
        )

        #expect(footer == "拖动可排序，左滑可隐藏；隐藏分类点按后恢复。“全部”始终显示并固定在第一位。")
    }

    @Test func editorResetsToDefaultOrderFromResetRow() throws {
        let store = makeStore()
        store.hideCategory(.tech)
        store.moveVisibleCategory(from: 2, to: 1)
        let viewController = PostCategoryPreferencesViewController(store: store)
        viewController.loadViewIfNeeded()

        let resetCell = try #require(viewController.tableView.dataSource?.tableView(
            viewController.tableView,
            cellForRowAt: IndexPath(row: 0, section: 2)
        ))
        #expect(resetCell.textLabel?.text == "恢复默认顺序")

        viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            didSelectRowAt: IndexPath(row: 0, section: 2)
        )

        #expect(store.visibleCategoryItems == PostListCategory.allCases.map(PostListCategoryItem.builtin))
        #expect(store.hiddenCategoryItems.isEmpty)
    }
}

private func makeStore() -> PostCategoryPreferenceStore {
    let suiteName = "post-category-preferences-view-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return PostCategoryPreferenceStore(userDefaults: defaults, storageKey: "categories")
}
