# Post Category Preferences Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users reorder visible home category tabs and hide or restore categories from Settings, while keeping `全部` visible and fixed first.

**Architecture:** Add a small `UserDefaults` preference store that normalizes category order and visibility, then consume it from the post list presenter. Settings gets a new `首页分类` entry and a focused `UITableViewController` editor with visible and hidden sections. The existing page container continues to own per-category list hosts and receives the normalized visible category list.

**Tech Stack:** Swift, UIKit, Swift Testing, `UserDefaults`, `NotificationCenter`, existing Xcode test target.

---

## File Structure

- Create `nodeseek/Features/PostList/PostCategoryPreferences.swift`
  - Owns `PostCategoryPreferences` and `PostCategoryPreferenceStore`.
  - Contains normalization, persistence, mutation methods, and change notification.

- Create `nodeseek/Features/Settings/PostCategoryPreferencesViewController.swift`
  - Owns the Settings subpage for visible and hidden category management.
  - Uses the store as its only dependency.

- Modify `nodeseek/Features/Settings/SettingsViewController.swift`
  - Adds `首页分类` row in the `阅读` section.
  - Pushes `PostCategoryPreferencesViewController`.
  - Refreshes the row summary when preferences change.

- Modify `nodeseek/Features/PostList/PostListPresenter.swift`
  - Reads visible categories from `PostCategoryPreferenceStore`.
  - Observes preference changes and re-renders categories.
  - Falls back to `.all` when the current category becomes hidden.

- Tests:
  - Create `nodeseekTests/Features/PostCategoryPreferenceStoreTests.swift`.
  - Create `nodeseekTests/Features/PostCategoryPreferencesViewControllerTests.swift`.
  - Modify `nodeseekTests/Features/SettingsViewControllerTests.swift`.
  - Modify `nodeseekTests/Features/PostListPresenterTests.swift`.

---

### Task 1: Preference Store

**Files:**
- Create: `nodeseek/Features/PostList/PostCategoryPreferences.swift`
- Create: `nodeseekTests/Features/PostCategoryPreferenceStoreTests.swift`

- [ ] **Step 1: Write the failing store tests**

Create `nodeseekTests/Features/PostCategoryPreferenceStoreTests.swift`:

```swift
//
//  PostCategoryPreferenceStoreTests.swift
//  nodeseekTests
//

import Foundation
import Testing
@testable import nodeseek

struct PostCategoryPreferenceStoreTests {
    @Test func defaultPreferencesShowAllCategoriesInDefaultOrder() throws {
        let store = makeStore()

        #expect(store.visibleCategories == PostListCategory.allCases)
        #expect(store.hiddenCategories.isEmpty)
    }

    @Test func hidingAndShowingCategoryKeepsAllVisibleAndFixedFirst() throws {
        let store = makeStore()

        store.hideCategory(.all)
        #expect(store.visibleCategories.first == .all)
        #expect(store.hiddenCategories.contains(.all) == false)

        store.hideCategory(.tech)
        #expect(store.visibleCategories.first == .all)
        #expect(store.visibleCategories.contains(.tech) == false)
        #expect(store.hiddenCategories == [.tech])

        store.showCategory(.tech)
        #expect(store.visibleCategories.first == .all)
        #expect(store.visibleCategories.last == .tech)
        #expect(store.hiddenCategories.isEmpty)
    }

    @Test func movingVisibleCategoryCannotMoveAnythingBeforeAll() throws {
        let store = makeStore()

        store.moveVisibleCategory(from: 2, to: 0)

        #expect(Array(store.visibleCategories.prefix(3)) == [.all, .tech, .daily])
    }

    @Test func storedPreferencesNormalizeDuplicatesUnknownValuesAndHiddenOverlap() throws {
        let suiteName = "post-category-preferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageKey = "categories"
        let rawJSON = """
        {
          "orderedVisibleCategories": ["trade", "all", "removed", "trade"],
          "hiddenCategories": ["all", "tech", "removed", "trade"]
        }
        """.data(using: .utf8)!
        defaults.set(rawJSON, forKey: storageKey)

        let store = PostCategoryPreferenceStore(userDefaults: defaults, storageKey: storageKey)

        #expect(Array(store.visibleCategories.prefix(2)) == [.all, .trade])
        #expect(store.hiddenCategories == [.tech])
        #expect(store.visibleCategories.contains(.daily))
        #expect(store.visibleCategories.contains(.tech) == false)
    }

    @Test func invalidStoredDataFallsBackToDefaultPreferences() throws {
        let suiteName = "post-category-preferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageKey = "categories"
        defaults.set(Data("not-json".utf8), forKey: storageKey)

        let store = PostCategoryPreferenceStore(userDefaults: defaults, storageKey: storageKey)

        #expect(store.visibleCategories == PostListCategory.allCases)
        #expect(store.hiddenCategories.isEmpty)
    }

    @Test func resetRestoresDefaultOrderAndVisibility() throws {
        let store = makeStore()
        store.hideCategory(.tech)
        store.moveVisibleCategory(from: 3, to: 1)

        store.resetToDefault()

        #expect(store.visibleCategories == PostListCategory.allCases)
        #expect(store.hiddenCategories.isEmpty)
    }
}

private func makeStore() -> PostCategoryPreferenceStore {
    let suiteName = "post-category-preferences-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return PostCategoryPreferenceStore(userDefaults: defaults, storageKey: "categories")
}
```

- [ ] **Step 2: Run the store tests to verify they fail**

Run:

```bash
make xcode-test-class TEST=PostCategoryPreferenceStoreTests SIMULATOR_OS=
```

Expected: build fails with `Cannot find 'PostCategoryPreferenceStore' in scope`.

- [ ] **Step 3: Implement the preference store**

Create `nodeseek/Features/PostList/PostCategoryPreferences.swift`:

```swift
//
//  PostCategoryPreferences.swift
//  nodeseek
//

import Foundation

struct PostCategoryPreferences: Codable, Equatable {
    var orderedVisibleCategories: [PostListCategory]
    var hiddenCategories: [PostListCategory]

    init(
        orderedVisibleCategories: [PostListCategory],
        hiddenCategories: [PostListCategory]
    ) {
        self.orderedVisibleCategories = orderedVisibleCategories
        self.hiddenCategories = hiddenCategories
    }

    private enum CodingKeys: String, CodingKey {
        case orderedVisibleCategories
        case hiddenCategories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let visibleRawValues = try container.decodeIfPresent([String].self, forKey: .orderedVisibleCategories) ?? []
        let hiddenRawValues = try container.decodeIfPresent([String].self, forKey: .hiddenCategories) ?? []
        orderedVisibleCategories = visibleRawValues.compactMap(PostListCategory.init(rawValue:))
        hiddenCategories = hiddenRawValues.compactMap(PostListCategory.init(rawValue:))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(orderedVisibleCategories.map(\.rawValue), forKey: .orderedVisibleCategories)
        try container.encode(hiddenCategories.map(\.rawValue), forKey: .hiddenCategories)
    }
}

final class PostCategoryPreferenceStore {
    static let didChangeNotification = Notification.Name("PostCategoryPreferenceStore.didChange")
    static let shared = PostCategoryPreferenceStore()

    private let userDefaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "postCategoryPreferences.v1"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    var visibleCategories: [PostListCategory] {
        preferences.orderedVisibleCategories
    }

    var hiddenCategories: [PostListCategory] {
        preferences.hiddenCategories
    }

    var preferences: PostCategoryPreferences {
        normalizedPreferences(from: storedPreferences())
    }

    func moveVisibleCategory(from sourceIndex: Int, to destinationIndex: Int) {
        var next = preferences
        guard next.orderedVisibleCategories.indices.contains(sourceIndex) else { return }
        guard sourceIndex > 0 else { return }

        let category = next.orderedVisibleCategories.remove(at: sourceIndex)
        let clampedDestination = max(1, min(destinationIndex, next.orderedVisibleCategories.count))
        next.orderedVisibleCategories.insert(category, at: clampedDestination)
        persist(normalizedPreferences(from: next))
    }

    func hideCategory(_ category: PostListCategory) {
        guard category != .all else { return }
        var next = preferences
        guard let index = next.orderedVisibleCategories.firstIndex(of: category) else { return }

        next.orderedVisibleCategories.remove(at: index)
        if !next.hiddenCategories.contains(category) {
            next.hiddenCategories.append(category)
        }
        persist(normalizedPreferences(from: next))
    }

    func showCategory(_ category: PostListCategory) {
        guard category != .all else { return }
        var next = preferences
        next.hiddenCategories.removeAll { $0 == category }
        if !next.orderedVisibleCategories.contains(category) {
            next.orderedVisibleCategories.append(category)
        }
        persist(normalizedPreferences(from: next))
    }

    func resetToDefault() {
        persist(PostCategoryPreferences(
            orderedVisibleCategories: PostListCategory.allCases,
            hiddenCategories: []
        ))
    }

    private func storedPreferences() -> PostCategoryPreferences? {
        guard let data = userDefaults.data(forKey: storageKey) else { return nil }
        return try? decoder.decode(PostCategoryPreferences.self, from: data)
    }

    private func normalizedPreferences(from stored: PostCategoryPreferences?) -> PostCategoryPreferences {
        guard let stored else {
            return PostCategoryPreferences(
                orderedVisibleCategories: PostListCategory.allCases,
                hiddenCategories: []
            )
        }

        let validCategories = Set(PostListCategory.allCases)
        var visible: [PostListCategory] = [.all]
        var hidden: [PostListCategory] = []

        for category in stored.orderedVisibleCategories {
            guard category != .all else { continue }
            guard validCategories.contains(category) else { continue }
            guard !visible.contains(category) else { continue }
            visible.append(category)
        }

        for category in stored.hiddenCategories {
            guard category != .all else { continue }
            guard validCategories.contains(category) else { continue }
            guard !visible.contains(category) else { continue }
            guard !hidden.contains(category) else { continue }
            hidden.append(category)
        }

        let configuredCategories = Set(visible).union(hidden)
        for category in PostListCategory.allCases {
            guard category != .all else { continue }
            guard !configuredCategories.contains(category) else { continue }
            visible.append(category)
        }

        if visible.isEmpty {
            visible = [.all]
        }

        return PostCategoryPreferences(
            orderedVisibleCategories: visible,
            hiddenCategories: hidden
        )
    }

    private func persist(_ preferences: PostCategoryPreferences) {
        guard let data = try? encoder.encode(preferences) else { return }
        userDefaults.set(data, forKey: storageKey)
        let postNotification = {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
        if Thread.isMainThread {
            postNotification()
        } else {
            DispatchQueue.main.async(execute: postNotification)
        }
    }
}
```

- [ ] **Step 4: Run the store tests to verify they pass**

Run:

```bash
make xcode-test-class TEST=PostCategoryPreferenceStoreTests SIMULATOR_OS=
```

Expected: `PostCategoryPreferenceStoreTests` passes.

- [ ] **Step 5: Commit**

```bash
git add nodeseek/Features/PostList/PostCategoryPreferences.swift nodeseekTests/Features/PostCategoryPreferenceStoreTests.swift
git commit -m "feat: add post category preference store"
```

---

### Task 2: Settings Entry

**Files:**
- Modify: `nodeseek/Features/Settings/SettingsViewController.swift`
- Modify: `nodeseekTests/Features/SettingsViewControllerTests.swift`

- [ ] **Step 1: Write failing Settings entry tests**

In `nodeseekTests/Features/SettingsViewControllerTests.swift`, update the existing row-count and signature row expectations:

```swift
#expect(tableView.numberOfRows(inSection: 0) == 4)
```

In `settingsPageShowsCacheActionAndLogoutAtBottomWhenLoggedIn`, read the new category cell and the shifted signature cell:

```swift
let categoryPreferencesCell = try #require(tableView.dataSource?.tableView(
    tableView,
    cellForRowAt: IndexPath(row: 2, section: 0)
))
let signatureCell = try #require(tableView.dataSource?.tableView(
    tableView,
    cellForRowAt: IndexPath(row: 3, section: 0)
))
```

Add these expectations near the other reading-section assertions:

```swift
#expect(categoryPreferencesCell.textLabel?.text == "首页分类")
#expect(categoryPreferencesCell.detailTextLabel?.text == "全部、日常、技术等 10 个")
#expect(categoryPreferencesCell.accessoryType == .disclosureIndicator)
```

In `togglingSignatureDisplaySwitchPersistsPreference`, change the signature index path to row `3`:

```swift
cellForRowAt: IndexPath(row: 3, section: 0)
```

Add this test inside `SettingsViewControllerTests`:

```swift
@Test func settingsPageShowsPostCategoryPreferencesSummaryAndPushesEditor() throws {
    let categoryStore = makeCategoryPreferenceStore()
    categoryStore.hideCategory(.tech)
    let viewController = SettingsViewController(
        cacheManager: FakeSettingsCacheManager(cacheByteSize: 0),
        sessionManager: FakeSettingsSessionManager(),
        nodeImageAPIKeyStore: FakeNodeImageAPIKeyStore(),
        categoryPreferenceStore: categoryStore
    )
    let navigationController = UINavigationController(rootViewController: viewController)
    viewController.loadViewIfNeeded()

    let cell = try #require(viewController.tableView.dataSource?.tableView(
        viewController.tableView,
        cellForRowAt: IndexPath(row: 2, section: 0)
    ))
    #expect(cell.textLabel?.text == "首页分类")
    #expect(cell.detailTextLabel?.text == "显示 9 个，隐藏 1 个")
    #expect(cell.accessoryType == .disclosureIndicator)

    viewController.tableView.delegate?.tableView?(
        viewController.tableView,
        didSelectRowAt: IndexPath(row: 2, section: 0)
    )

    #expect(navigationController.topViewController is PostCategoryPreferencesViewController)
}
```

Add this helper near `makeSpecialFollowStore()`:

```swift
private func makeCategoryPreferenceStore() -> PostCategoryPreferenceStore {
    let suiteName = "settings-category-preferences-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return PostCategoryPreferenceStore(userDefaults: defaults, storageKey: "categories")
}
```

- [ ] **Step 2: Run the Settings tests to verify they fail**

Run:

```bash
make xcode-test-class TEST=SettingsViewControllerTests SIMULATOR_OS=
```

Expected: build fails with `Cannot find 'PostCategoryPreferencesViewController' in scope` or `Extra argument 'categoryPreferenceStore' in call`.

- [ ] **Step 3: Add the Settings entry**

In `nodeseek/Features/Settings/SettingsViewController.swift`, replace `ReadingRow` with:

```swift
private enum ReadingRow: Int, CaseIterable {
    case adjustment
    case preview
    case categoryPreferences
    case signatureDisplay
}
```

Add a stored property near the other settings stores:

```swift
private let categoryPreferenceStore: PostCategoryPreferenceStore
```

Add an init parameter after `signatureDisplaySettings`:

```swift
categoryPreferenceStore: PostCategoryPreferenceStore = .shared,
```

Assign it in the initializer:

```swift
self.categoryPreferenceStore = categoryPreferenceStore
```

In `viewDidLoad()`, add an observer after the special-follow observer:

```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(postCategoryPreferencesDidChange(_:)),
    name: PostCategoryPreferenceStore.didChangeNotification,
    object: categoryPreferenceStore
)
```

Replace the `.reading` case in `didSelectRowAt` with:

```swift
case .reading:
    handleReadingSelection(at: indexPath)
```

In `readingCell(for:)`, add the new switch case before `.signatureDisplay`:

```swift
case .categoryPreferences:
    return categoryPreferencesCell(for: indexPath)
```

Add these methods near `signatureDisplayCell(for:)`:

```swift
private func categoryPreferencesCell(for indexPath: IndexPath) -> UITableViewCell {
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    cell.textLabel?.text = "首页分类"
    cell.detailTextLabel?.text = categoryPreferenceDetailText
    cell.detailTextLabel?.textColor = .secondaryLabel
    cell.detailTextLabel?.numberOfLines = 2
    cell.imageView?.image = UIImage(systemName: "list.bullet.rectangle")
    cell.accessoryType = .disclosureIndicator
    cell.accessibilityIdentifier = "settings-post-category-preferences-cell"
    return cell
}

private var categoryPreferenceDetailText: String {
    let visible = categoryPreferenceStore.visibleCategories
    let hiddenCount = categoryPreferenceStore.hiddenCategories.count
    guard hiddenCount == 0 else {
        return "显示 \(visible.count) 个，隐藏 \(hiddenCount) 个"
    }

    let prefix = visible.prefix(3).map(\.title).joined(separator: "、")
    if visible.count > 3 {
        return "\(prefix)等 \(visible.count) 个"
    }
    return prefix
}
```

Add this method near `handleFeatureSelection(at:)`:

```swift
private func handleReadingSelection(at indexPath: IndexPath) {
    switch ReadingRow(rawValue: indexPath.row) {
    case .categoryPreferences:
        showPostCategoryPreferences()
    case .adjustment, .preview, .signatureDisplay, .none:
        break
    }
}
```

Add this method near `showSpecialFollowKeywords()`:

```swift
private func showPostCategoryPreferences() {
    let viewController = PostCategoryPreferencesViewController(store: categoryPreferenceStore)
    navigationController?.pushViewController(viewController, animated: true)
}
```

Add this notification handler near `specialFollowKeywordsDidChange(_:)`:

```swift
@objc private func postCategoryPreferencesDidChange(_ notification: Notification) {
    let indexPath = IndexPath(row: ReadingRow.categoryPreferences.rawValue, section: Section.reading.rawValue)
    tableView.reloadRows(at: [indexPath], with: .none)
}
```

- [ ] **Step 4: Add a temporary shell editor controller so Settings compiles**

Create `nodeseek/Features/Settings/PostCategoryPreferencesViewController.swift` with this temporary implementation:

```swift
//
//  PostCategoryPreferencesViewController.swift
//  nodeseek
//

import UIKit

final class PostCategoryPreferencesViewController: UITableViewController {
    private let store: PostCategoryPreferenceStore

    init(store: PostCategoryPreferenceStore = .shared) {
        self.store = store
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "首页分类"
        tableView.accessibilityIdentifier = "post-category-preferences-table-view"
        _ = store.visibleCategories
    }
}
```

- [ ] **Step 5: Run the Settings tests to verify they pass**

Run:

```bash
make xcode-test-class TEST=SettingsViewControllerTests SIMULATOR_OS=
```

Expected: `SettingsViewControllerTests` passes.

- [ ] **Step 6: Commit**

```bash
git add nodeseek/Features/Settings/SettingsViewController.swift nodeseek/Features/Settings/PostCategoryPreferencesViewController.swift nodeseekTests/Features/SettingsViewControllerTests.swift
git commit -m "feat: add post category settings entry"
```

---

### Task 3: Category Preferences Editor

**Files:**
- Modify: `nodeseek/Features/Settings/PostCategoryPreferencesViewController.swift`
- Create: `nodeseekTests/Features/PostCategoryPreferencesViewControllerTests.swift`

- [ ] **Step 1: Write failing editor tests**

Create `nodeseekTests/Features/PostCategoryPreferencesViewControllerTests.swift`:

```swift
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
        #expect(viewController.tableView.numberOfSections == 2)
        #expect(viewController.tableView.numberOfRows(inSection: 0) == PostListCategory.allCases.count)
        #expect(viewController.tableView.numberOfRows(inSection: 1) == 0)
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
    }

    @Test func editorMovesVisibleCategoriesWithoutCrossingAll() throws {
        let store = makeStore()
        let viewController = PostCategoryPreferencesViewController(store: store)
        viewController.loadViewIfNeeded()

        let target = viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            targetIndexPathForMoveFromRowAt: IndexPath(row: 2, section: 0),
            toProposedIndexPath: IndexPath(row: 0, section: 0)
        )

        #expect(target == IndexPath(row: 1, section: 0))

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
        #expect(hiddenCell.detailTextLabel?.text == "点按显示")

        viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            didSelectRowAt: IndexPath(row: 0, section: 1)
        )

        #expect(store.hiddenCategories.isEmpty)
        #expect(store.visibleCategories.last == .daily)
    }

    @Test func editorFooterExplainsAllCategoryRule() throws {
        let viewController = PostCategoryPreferencesViewController(store: makeStore())
        viewController.loadViewIfNeeded()

        let footer = viewController.tableView.dataSource?.tableView?(
            viewController.tableView,
            titleForFooterInSection: 0
        )

        #expect(footer == "“全部”始终显示并固定在第一位。隐藏分类不会删除内容，只是不显示在首页顶部。")
    }
}

private func makeStore() -> PostCategoryPreferenceStore {
    let suiteName = "post-category-preferences-view-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return PostCategoryPreferenceStore(userDefaults: defaults, storageKey: "categories")
}
```

- [ ] **Step 2: Run the editor tests to verify they fail**

Run:

```bash
make xcode-test-class TEST=PostCategoryPreferencesViewControllerTests SIMULATOR_OS=
```

Expected: tests fail because the temporary controller has no sections, cells, editing, or move behavior.

- [ ] **Step 3: Implement the editor controller**

Replace `nodeseek/Features/Settings/PostCategoryPreferencesViewController.swift` with:

```swift
//
//  PostCategoryPreferencesViewController.swift
//  nodeseek
//

import UIKit

final class PostCategoryPreferencesViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case visible
        case hidden
    }

    private let store: PostCategoryPreferenceStore
    private var visibleCategories: [PostListCategory] = []
    private var hiddenCategories: [PostListCategory] = []

    init(store: PostCategoryPreferenceStore = .shared) {
        self.store = store
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "首页分类"
        tableView.accessibilityIdentifier = "post-category-preferences-table-view"
        tableView.setEditing(true, animated: false)
        reloadPreferences()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange(_:)),
            name: PostCategoryPreferenceStore.didChangeNotification,
            object: store
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .visible:
            return visibleCategories.count
        case .hidden:
            return hiddenCategories.count
        case .none:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .visible:
            return "显示"
        case .hidden:
            return "隐藏"
        case .none:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard Section(rawValue: section) == .visible else { return nil }
        return "“全部”始终显示并固定在第一位。隐藏分类不会删除内容，只是不显示在首页顶部。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.textColor = .label
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 1

        switch Section(rawValue: indexPath.section) {
        case .visible:
            let category = visibleCategories[indexPath.row]
            cell.textLabel?.text = category.title
            cell.detailTextLabel?.text = category == .all ? "固定第一位" : "拖动排序，左滑隐藏"
            cell.accessibilityIdentifier = "post-category-preferences-visible-cell-\(indexPath.row)"
        case .hidden:
            let category = hiddenCategories[indexPath.row]
            cell.textLabel?.text = category.title
            cell.detailTextLabel?.text = "点按显示"
            cell.accessibilityIdentifier = "post-category-preferences-hidden-cell-\(indexPath.row)"
        case .none:
            break
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        Section(rawValue: indexPath.section) == .visible && indexPath.row > 0
    }

    override func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        guard Section(rawValue: proposedDestinationIndexPath.section) == .visible else {
            return sourceIndexPath
        }
        guard proposedDestinationIndexPath.row > 0 else {
            return IndexPath(row: 1, section: Section.visible.rawValue)
        }
        return proposedDestinationIndexPath
    }

    override func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        store.moveVisibleCategory(from: sourceIndexPath.row, to: destinationIndexPath.row)
        reloadPreferences()
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        switch Section(rawValue: indexPath.section) {
        case .visible:
            return indexPath.row > 0
        case .hidden:
            return true
        case .none:
            return false
        }
    }

    override func tableView(
        _ tableView: UITableView,
        editingStyleForRowAt indexPath: IndexPath
    ) -> UITableViewCell.EditingStyle {
        switch Section(rawValue: indexPath.section) {
        case .visible:
            return indexPath.row == 0 ? .none : .delete
        case .hidden:
            return .insert
        case .none:
            return .none
        }
    }

    override func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        switch (Section(rawValue: indexPath.section), editingStyle) {
        case (.visible, .delete):
            store.hideCategory(visibleCategories[indexPath.row])
            reloadPreferences()
        case (.hidden, .insert):
            store.showCategory(hiddenCategories[indexPath.row])
            reloadPreferences()
        default:
            break
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard Section(rawValue: indexPath.section) == .hidden else { return }
        store.showCategory(hiddenCategories[indexPath.row])
        reloadPreferences()
    }

    private func reloadPreferences() {
        visibleCategories = store.visibleCategories
        hiddenCategories = store.hiddenCategories
        tableView.reloadData()
    }

    @objc private func preferencesDidChange(_ notification: Notification) {
        reloadPreferences()
    }
}
```

- [ ] **Step 4: Run the editor and Settings tests to verify they pass**

Run:

```bash
make xcode-test-class TEST=PostCategoryPreferencesViewControllerTests SIMULATOR_OS=
make xcode-test-class TEST=SettingsViewControllerTests SIMULATOR_OS=
```

Expected: both test classes pass.

- [ ] **Step 5: Commit**

```bash
git add nodeseek/Features/Settings/PostCategoryPreferencesViewController.swift nodeseekTests/Features/PostCategoryPreferencesViewControllerTests.swift
git commit -m "feat: add post category preferences editor"
```

---

### Task 4: Home Tab Integration

**Files:**
- Modify: `nodeseek/Features/PostList/PostListPresenter.swift`
- Modify: `nodeseekTests/Features/PostListPresenterTests.swift`

- [ ] **Step 1: Write failing presenter tests**

In `nodeseekTests/Features/PostListPresenterTests.swift`, update `makePresenter` to accept a category store:

```swift
private func makePresenter(
    view: SpyPostListView? = nil,
    router: SpyPostListRouter? = nil,
    visitedStore: VisitedPostStoreProtocol = EmptyVisitedPostStore(),
    categoryPreferenceStore: PostCategoryPreferenceStore = makeCategoryPreferenceStore()
) -> PostListPresenter {
    let router = router ?? SpyPostListRouter()
    let presenter = PostListPresenter(
        router: router,
        visitedStore: visitedStore,
        categoryPreferenceStore: categoryPreferenceStore
    )
    if let view {
        presenter.setView(view)
    }
    return presenter
}
```

Add this helper near `makePost(id:title:)`:

```swift
private func makeCategoryPreferenceStore() -> PostCategoryPreferenceStore {
    let suiteName = "post-list-presenter-categories-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return PostCategoryPreferenceStore(userDefaults: defaults, storageKey: "categories")
}
```

Add these tests inside `PostListPresenterTests`:

```swift
@Test func viewDidLoadRendersVisibleCategoriesFromPreferences() {
    let view = SpyPostListView()
    let store = makeCategoryPreferenceStore()
    store.hideCategory(.tech)
    let presenter = makePresenter(view: view, categoryPreferenceStore: store)

    presenter.viewDidLoad()

    #expect(view.renderedCategories == store.visibleCategories)
    #expect(view.renderedCategories.contains(.tech) == false)
    #expect(view.selectedCategory == .all)
}

@Test func categoryPreferenceChangeKeepsCurrentCategoryWhenStillVisible() {
    let view = SpyPostListView()
    let store = makeCategoryPreferenceStore()
    let presenter = makePresenter(view: view, categoryPreferenceStore: store)
    presenter.viewDidLoad()
    presenter.didSelectCategory(.tech)

    store.hideCategory(.daily)

    #expect(view.selectedCategory == .tech)
    #expect(view.renderedCategories.contains(.daily) == false)
}

@Test func categoryPreferenceChangeFallsBackToAllWhenCurrentCategoryIsHidden() {
    let view = SpyPostListView()
    let store = makeCategoryPreferenceStore()
    let presenter = makePresenter(view: view, categoryPreferenceStore: store)
    presenter.viewDidLoad()
    presenter.didSelectCategory(.tech)

    store.hideCategory(.tech)

    #expect(view.selectedCategory == .all)
    #expect(view.renderedCategories.contains(.tech) == false)
}
```

- [ ] **Step 2: Run presenter tests to verify they fail**

Run:

```bash
make xcode-test-class TEST=PostListPresenterTests SIMULATOR_OS=
```

Expected: build fails with `Extra argument 'categoryPreferenceStore' in call`.

- [ ] **Step 3: Integrate preferences into `PostListPresenter`**

In `nodeseek/Features/PostList/PostListPresenter.swift`, replace these properties:

```swift
private let categories = PostListCategory.allCases
private var currentCategory: PostListCategory = .all
```

with:

```swift
private let categoryPreferenceStore: PostCategoryPreferenceStore
private var categoryPreferenceObserver: NSObjectProtocol?
private var currentCategory: PostListCategory = .all
```

Update the initializer signature:

```swift
init(
    router: PostListRouterProtocol,
    visitedStore: VisitedPostStoreProtocol = EmptyVisitedPostStore(),
    categoryPreferenceStore: PostCategoryPreferenceStore = .shared
) {
    self.router = router
    self.visitedStore = visitedStore
    self.categoryPreferenceStore = categoryPreferenceStore
}
```

Add a deinitializer:

```swift
deinit {
    if let categoryPreferenceObserver {
        NotificationCenter.default.removeObserver(categoryPreferenceObserver)
    }
}
```

Replace `viewDidLoad()` with:

```swift
func viewDidLoad() {
    observeCategoryPreferencesIfNeeded()
    renderCurrentCategories()
    view?.renderSortMode(.replyTime)
}
```

Replace `didSelectCategory(_:)` with:

```swift
func didSelectCategory(_ category: PostListCategory) {
    guard category != currentCategory else { return }
    guard categoryPreferenceStore.visibleCategories.contains(category) else { return }
    currentCategory = category
}
```

Add these private methods inside the existing `private extension PostListPresenter`:

```swift
func observeCategoryPreferencesIfNeeded() {
    guard categoryPreferenceObserver == nil else { return }
    categoryPreferenceObserver = NotificationCenter.default.addObserver(
        forName: PostCategoryPreferenceStore.didChangeNotification,
        object: categoryPreferenceStore,
        queue: nil
    ) { [weak self] _ in
        self?.categoryPreferencesDidChange()
    }
}

func categoryPreferencesDidChange() {
    renderCurrentCategories()
}

func renderCurrentCategories() {
    let categories = categoryPreferenceStore.visibleCategories
    if !categories.contains(currentCategory) {
        currentCategory = .all
    }
    view?.renderCategories(categories, selected: currentCategory)
}
```

- [ ] **Step 4: Run presenter tests to verify they pass**

Run:

```bash
make xcode-test-class TEST=PostListPresenterTests SIMULATOR_OS=
```

Expected: `PostListPresenterTests` passes.

- [ ] **Step 5: Commit**

```bash
git add nodeseek/Features/PostList/PostListPresenter.swift nodeseekTests/Features/PostListPresenterTests.swift
git commit -m "feat: apply category preferences to home tabs"
```

---

### Task 5: Focused Regression Verification

**Files:**
- No source edits expected.

- [ ] **Step 1: Run focused affected test classes**

Run:

```bash
make xcode-test-class TEST=PostCategoryPreferenceStoreTests SIMULATOR_OS=
make xcode-test-class TEST=PostCategoryPreferencesViewControllerTests SIMULATOR_OS=
make xcode-test-class TEST=SettingsViewControllerTests SIMULATOR_OS=
make xcode-test-class TEST=PostListPresenterTests SIMULATOR_OS=
make xcode-test-class TEST=PostListViewControllerTests SIMULATOR_OS=
```

Expected: all five test classes pass.

- [ ] **Step 2: Run a build-for-testing pass**

Run:

```bash
make xcode-build-tests
```

Expected: build-for-testing completes without errors.

- [ ] **Step 3: Inspect changed files**

Run:

```bash
git status --short
git diff --stat HEAD
```

Expected: only intentional uncommitted verification artifacts are present. If source changes remain from fixing test or build failures, commit them with:

```bash
git add nodeseek/Features/PostList/PostCategoryPreferences.swift \
  nodeseek/Features/Settings/PostCategoryPreferencesViewController.swift \
  nodeseek/Features/Settings/SettingsViewController.swift \
  nodeseek/Features/PostList/PostListPresenter.swift \
  nodeseekTests/Features/PostCategoryPreferenceStoreTests.swift \
  nodeseekTests/Features/PostCategoryPreferencesViewControllerTests.swift \
  nodeseekTests/Features/SettingsViewControllerTests.swift \
  nodeseekTests/Features/PostListPresenterTests.swift
git commit -m "test: verify post category preferences"
```

Expected: if there are no source changes, skip the commit.

---

## Self-Review

- Spec coverage: Task 1 covers persistence and normalization; Task 2 covers Settings entry and summary; Task 3 covers visible/hidden editor behavior, fixed `全部`, moving, hiding, and restoring; Task 4 covers home tab consumption and fallback to `全部`; Task 5 covers regression verification.
- Placeholder scan: no open-ended implementation placeholders remain.
- Type consistency: all tasks use `PostCategoryPreferenceStore`, `PostCategoryPreferences`, `PostCategoryPreferencesViewController`, and `PostListCategory` consistently.
