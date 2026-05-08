//
//  SearchViewControllerTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/5/3.
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct SearchViewControllerTests {
    @Test func defaultServiceUsesHTTPFirstLoadingStrategy() throws {
        let service = SearchViewController.makeDefaultService()
        let htmlClient = try #require(Mirror(reflecting: service).descendant("htmlClient"))

        #expect(String(describing: type(of: htmlClient)).contains("WebViewFallbackHTMLClient"))
    }

    @Test func searchControlsUseSingleRowWithCategoryMenu() throws {
        let viewController = SearchViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        let categoryButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "search-category-selector-button"))
        let keywordTextField = try #require(viewController.view.firstTextField(accessibilityIdentifier: "search-keyword-text-field"))
        let searchButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "search-submit-button"))

        #expect(categoryButton.configuration?.title == "全部")
        #expect(categoryButton.configuration?.image == nil)
        #expect(categoryButton.menu != nil)
        #expect(categoryButton.showsMenuAsPrimaryAction == true)
        #expect(viewController.view.firstButton(title: "日常") == nil)
        let menuTitles = categoryButton.menu?.children.compactMap { ($0 as? UIAction)?.title } ?? []
        #expect(menuTitles.contains("DF") == false)
        #expect(menuTitles.contains("推荐阅读") == false)
        #expect(abs(categoryButton.frame.midY - keywordTextField.frame.midY) < 1)
        #expect(abs(searchButton.frame.midY - keywordTextField.frame.midY) < 1)
        #expect(categoryButton.frame.maxX < keywordTextField.frame.minX)
        #expect(keywordTextField.frame.maxX < searchButton.frame.minX)
        #expect(try inputRowTop(in: viewController.view) < 160)
        #expect(abs(searchButton.bounds.width - 68) < 0.5)
        #expect(searchButton.configuration?.title == "搜索")
        #expect(searchButton.configuration?.image == nil)
        #expect(searchButton.configuration?.titleLineBreakMode == .byTruncatingTail)
        #expect(keywordTextField.borderStyle == .none)
        #expect(keywordTextField.layer.borderWidth >= 1.2)
        #expect(keywordTextField.layer.borderColor != nil)
    }

    @Test func recentSearchesRenderStoredTopTenAndClearButton() throws {
        let store = makeSearchHistoryStore()
        for index in 1...12 {
            store.record(query: "keyword-\(index)", category: .all)
        }
        let viewController = SearchViewController(searchHistoryStore: store)
        viewController.loadViewIfNeeded()

        _ = try #require(viewController.view.firstLabel(text: "最近搜索"))
        _ = try #require(viewController.view.firstButton(accessibilityIdentifier: "search-history-clear-button"))
        let historyButtons = viewController.view.allButtons(accessibilityIdentifierPrefix: "search-history-record-button-")

        #expect(historyButtons.count == 10)
        #expect(historyButtons.first?.configuration?.title == "keyword-12")
        #expect(historyButtons.last?.configuration?.title == "keyword-3")
    }

    @Test func recentSearchesUseWrappingTagLayout() throws {
        let store = makeSearchHistoryStore()
        ["iOS", "Swift", "美西", "美国", "Kanna"].forEach { query in
            store.record(query: query, category: .all)
        }
        let viewController = SearchViewController(searchHistoryStore: store)
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        let historyButtons = viewController.view.allButtons(accessibilityIdentifierPrefix: "search-history-record-button-")

        #expect(historyButtons.count == 5)
        #expect(abs(historyButtons[0].frame.midY - historyButtons[1].frame.midY) < 1)
        #expect(historyButtons[0].frame.maxX < historyButtons[1].frame.minX)
    }

    @Test func searchPageUsesRememberedCategoryAsDefault() throws {
        let preferenceStore = makeSearchPreferenceStore()
        preferenceStore.rememberCategory(.tech)

        let viewController = SearchViewController(searchPreferenceStore: preferenceStore)
        viewController.loadViewIfNeeded()

        let categoryButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "search-category-selector-button"))
        #expect(categoryButton.configuration?.title == PostListCategory.tech.title)
    }

    @Test func searchPageFallsBackToAllForUnsupportedRememberedCategory() throws {
        let preferenceStore = makeSearchPreferenceStore()
        preferenceStore.rememberCategory(.df)

        let viewController = SearchViewController(searchPreferenceStore: preferenceStore)
        viewController.loadViewIfNeeded()

        let categoryButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "search-category-selector-button"))
        #expect(categoryButton.configuration?.title == PostListCategory.all.title)
    }

    @Test func clearingRecentSearchesRemovesStoredRecordsAndSection() throws {
        let store = makeSearchHistoryStore()
        store.record(query: "美西", category: .all)
        let viewController = SearchViewController(searchHistoryStore: store)
        viewController.loadViewIfNeeded()

        let clearButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "search-history-clear-button"))
        clearButton.sendActions(for: .touchUpInside)

        #expect(store.records().isEmpty)
        #expect(viewController.view.allButtons(accessibilityIdentifierPrefix: "search-history-record-button-").isEmpty)
    }

    @Test func submittingSearchStoresRecentSearchRecord() throws {
        let store = makeSearchHistoryStore()
        let preferenceStore = makeSearchPreferenceStore()
        let htmlClient = StaticSearchHTMLClient(html: """
        <html><body><div class="post-list"></div></body></html>
        """)
        let service = NodeSeekService(
            htmlClient: htmlClient,
            parser: EmptyPostListParser()
        )
        let viewController = SearchViewController(
            service: service,
            searchHistoryStore: store,
            searchPreferenceStore: preferenceStore
        )
        viewController.loadViewIfNeeded()
        let keywordTextField = try #require(viewController.view.firstTextField(accessibilityIdentifier: "search-keyword-text-field"))
        let searchButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "search-submit-button"))

        keywordTextField.text = "美西"
        searchButton.sendActions(for: .touchUpInside)

        #expect(store.records().map(\.query) == ["美西"])
        #expect(store.records().first?.category == .all)
        #expect(preferenceStore.category() == .all)
    }
}

private func makeSearchHistoryStore() -> SearchHistoryStore {
    let suiteName = "search-history-tests-\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    return SearchHistoryStore(userDefaults: userDefaults, storageKey: "history")
}

private func makeSearchPreferenceStore() -> SearchPreferenceStore {
    let suiteName = "search-preference-tests-\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    return SearchPreferenceStore(userDefaults: userDefaults, categoryStorageKey: "category")
}

private struct StaticSearchHTMLClient: HTMLClient {
    let html: String

    func get(_ url: URL) async throws -> HTMLResponse {
        HTMLResponse(
            statusCode: 200,
            headers: [:],
            finalURL: url,
            html: html
        )
    }

    func post(_ url: URL, formFields: [String: String]) async throws -> HTMLResponse {
        try await get(url)
    }
}

private struct EmptyPostListParser: NodeSeekParser {
    func parsePostList(html: String) throws -> [PostSummary] { [] }
    func parsePostDetail(html: String, url: URL) throws -> PostDetail {
        throw NSError(domain: "EmptyPostListParser", code: 1)
    }
    func parseCheckInState(html: String, pageURL: URL) throws -> CheckInState {
        CheckInState(isCheckedIn: false, message: "", actionURL: nil, hiddenFields: [:])
    }
    func parseAccount(html: String) throws -> AccountResponse {
        AccountResponse(displayName: "未登录", isLoggedIn: false)
    }
}

private extension UIView {
    func firstButton(accessibilityIdentifier: String) -> UIButton? {
        if let button = self as? UIButton, button.accessibilityIdentifier == accessibilityIdentifier {
            return button
        }

        for subview in subviews {
            if let matched = subview.firstButton(accessibilityIdentifier: accessibilityIdentifier) {
                return matched
            }
        }

        return nil
    }

    func firstButton(title: String) -> UIButton? {
        if let button = self as? UIButton, button.title(for: .normal) == title || button.configuration?.title == title {
            return button
        }

        for subview in subviews {
            if let matched = subview.firstButton(title: title) {
                return matched
            }
        }

        return nil
    }

    func allButtons(accessibilityIdentifierPrefix prefix: String) -> [UIButton] {
        var matches: [UIButton] = []
        if let button = self as? UIButton,
           button.accessibilityIdentifier?.hasPrefix(prefix) == true {
            matches.append(button)
        }

        for subview in subviews {
            matches.append(contentsOf: subview.allButtons(accessibilityIdentifierPrefix: prefix))
        }

        return matches
    }

    func firstTextField(accessibilityIdentifier: String) -> UITextField? {
        if let textField = self as? UITextField, textField.accessibilityIdentifier == accessibilityIdentifier {
            return textField
        }

        for subview in subviews {
            if let matched = subview.firstTextField(accessibilityIdentifier: accessibilityIdentifier) {
                return matched
            }
        }

        return nil
    }

    func firstLabel(text: String) -> UILabel? {
        if let label = self as? UILabel, label.text == text {
            return label
        }

        for subview in subviews {
            if let matched = subview.firstLabel(text: text) {
                return matched
            }
        }

        return nil
    }
}

private func inputRowTop(in view: UIView) throws -> CGFloat {
    let categoryButton = try #require(view.firstButton(accessibilityIdentifier: "search-category-selector-button"))
    let keywordTextField = try #require(view.firstTextField(accessibilityIdentifier: "search-keyword-text-field"))
    let searchButton = try #require(view.firstButton(accessibilityIdentifier: "search-submit-button"))
    return min(categoryButton.frame.minY, keywordTextField.frame.minY, searchButton.frame.minY)
}
