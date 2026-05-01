# Visited Post Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist and render visited post state so clicked posts immediately turn gray and stay gray across refreshes and app restarts.

**Architecture:** `PostListPresenter` owns list-state composition and receives an injected `VisitedPostStoreProtocol`. Store keeps recent visited records in memory for fast `Set.contains` checks and writes each access asynchronously to a lightweight SQLite persistence backend. Texture list views receive `PostListItem` values and reload only the selected row after a new visit.

**Tech Stack:** Swift, UIKit, Texture, Swift Testing, system `SQLite3/libsqlite3`.

---

### Task 1: Add Display Model And Store Contract

**Files:**
- Create: `nodeseek/Features/PostList/VisitedPostStore.swift`
- Modify: `nodeseekTests/Features/PostListPresenterTests.swift`

- [ ] **Step 1: Write failing presenter tests for visited composition and single-row update**

Add a fake store to `PostListPresenterTests.swift`:

```swift
@MainActor
private final class FakeVisitedPostStore: VisitedPostStoreProtocol {
    var visitedIDs: Set<String> = []
    var markedPosts: [PostSummary] = []

    func isVisited(postID: String) -> Bool {
        visitedIDs.contains(postID)
    }

    func markVisited(post: PostSummary, visitedAt: Date) {
        visitedIDs.insert(post.id)
        markedPosts.append(post)
    }

    func recentRecords(limit: Int) -> [VisitedPostRecord] {
        []
    }
}
```

Add tests:

```swift
@Test func loadingPostsComposesVisitedStateBeforeRendering() {
    let view = SpyPostListView()
    let interactor = SpyPostListInteractor()
    let router = SpyPostListRouter()
    let visitedStore = FakeVisitedPostStore()
    visitedStore.visitedIDs = ["2"]
    let presenter = PostListPresenter(interactor: interactor, router: router, visitedStore: visitedStore)
    presenter.setView(view)
    let first = makePost(id: "1", title: "未访问")
    let second = makePost(id: "2", title: "已访问")

    presenter.didLoadPosts([first, second], category: .all)

    #expect(view.lastRenderedPostIDs == ["1", "2"])
    #expect(view.lastRenderedVisitedFlags == [false, true])
}

@Test func selectingUnvisitedPostMarksVisitedAndReloadsOnlySelectedRowBeforeNavigation() {
    let view = SpyPostListView()
    let interactor = SpyPostListInteractor()
    let router = SpyPostListRouter()
    let visitedStore = FakeVisitedPostStore()
    let presenter = PostListPresenter(interactor: interactor, router: router, visitedStore: visitedStore)
    presenter.setView(view)
    let post = makePost(id: "1", title: "标题")

    presenter.didLoadPosts([post], category: .all)
    presenter.didSelectPost(at: 0)

    #expect(visitedStore.markedPosts.map(\.id) == ["1"])
    #expect(view.updatedVisitedRows == [0])
    #expect(view.updatedVisitedFlags == [true])
    #expect(router.selectedPost?.id == "1")
}

@Test func selectingAlreadyVisitedPostDoesNotReloadRowAgain() {
    let view = SpyPostListView()
    let interactor = SpyPostListInteractor()
    let router = SpyPostListRouter()
    let visitedStore = FakeVisitedPostStore()
    visitedStore.visitedIDs = ["1"]
    let presenter = PostListPresenter(interactor: interactor, router: router, visitedStore: visitedStore)
    presenter.setView(view)
    let post = makePost(id: "1", title: "标题")

    presenter.didLoadPosts([post], category: .all)
    presenter.didSelectPost(at: 0)

    #expect(visitedStore.markedPosts.map(\.id) == ["1"])
    #expect(view.updatedVisitedRows.isEmpty)
    #expect(router.selectedPost?.id == "1")
}
```

Add this helper in the test file:

```swift
private func makePost(id: String, title: String) -> PostSummary {
    PostSummary(
        id: id,
        title: title,
        url: URL(string: "https://www.nodeseek.com/post-\(id)")!,
        authorName: "mist",
        nodeName: "开发",
        replyCount: 1,
        lastActivityText: "刚刚"
    )
}
```

- [ ] **Step 2: Run test and verify it fails**

Run: `make xcode-test-class TEST=PostListPresenterTests`

Expected: FAIL because `VisitedPostStoreProtocol`, `VisitedPostRecord`, `PostListItem`, presenter injection, `render(items:)`, and row update APIs do not exist yet.

- [ ] **Step 3: Add minimal model and protocol**

Create `VisitedPostStore.swift`:

```swift
import Foundation

struct VisitedPostRecord: Equatable, Sendable {
    let postID: String
    let title: String
    let url: URL
    let visitedAt: Date
}

struct PostListItem: Equatable, Sendable {
    let post: PostSummary
    let isVisited: Bool
}

protocol VisitedPostStoreProtocol: AnyObject {
    func isVisited(postID: String) -> Bool
    func markVisited(post: PostSummary, visitedAt: Date)
    func recentRecords(limit: Int) -> [VisitedPostRecord]
}
```

- [ ] **Step 4: Update presenter and test spy APIs**

Change `PostListViewProtocol.render(posts:)` to `render(items:)` and add `renderVisitedState(at:isVisited:)`. Update presenter state to store `[PostListItem]`, compose items after every first-page and load-more response, and update only the selected row before navigation.

- [ ] **Step 5: Run test and verify it passes**

Run: `make xcode-test-class TEST=PostListPresenterTests`

Expected: PASS.

### Task 2: Propagate PostListItem Through Texture List Views

**Files:**
- Modify: `nodeseek/Features/PostList/PostListViewController.swift`
- Modify: `nodeseek/Features/PostList/TextureList/PostTexturePageContainerView.swift`
- Modify: `nodeseek/Features/PostList/TextureList/PostTextureListView.swift`
- Modify: `nodeseek/Features/PostList/Nodes/PostSummaryCellNode.swift`
- Modify: `nodeseekTests/Features/PostSummaryCellNodeTests.swift`

- [ ] **Step 1: Write failing cell test for visited title color**

Add:

```swift
@Test func visitedPostTitleUsesSecondaryColor() {
    let post = PostSummary(
        id: "6",
        title: "已访问标题",
        url: URL(string: "https://www.nodeseek.com/post-6")!,
        authorName: "mist",
        nodeName: "NodeSeek",
        replyCount: 1,
        lastActivityText: "just now"
    )

    let titleText = PostSummaryCellNode.titleAttributedText(for: post, isVisited: true)

    #expect(titleText.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor == .secondaryLabel)
}
```

- [ ] **Step 2: Run cell test and verify it fails**

Run: `make xcode-test-class TEST=PostSummaryCellNodeTests`

Expected: FAIL because `titleAttributedText(for:isVisited:)` does not exist.

- [ ] **Step 3: Update cell and list view APIs**

`PostSummaryCellNode` should accept `PostListItem`, store `post` and `isVisited`, and use `.secondaryLabel` for visited title text. `PostTextureListView` should store `[PostListItem]`, create cells with items, and add:

```swift
func updateVisitedState(at index: Int, isVisited: Bool) {
    guard displayMode == .content else { return }
    guard posts.indices.contains(index) else { return }
    let existing = posts[index]
    posts[index] = PostListItem(post: existing.post, isVisited: isVisited)
    tableNode.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
}
```

Propagate equivalent methods through `PostTextureListHostViewController`, `PostTexturePageContainerView`, and `PostListViewController`.

- [ ] **Step 4: Run presenter and cell tests**

Run:

```bash
make xcode-test-class TEST=PostListPresenterTests
make xcode-test-class TEST=PostSummaryCellNodeTests
```

Expected: PASS.

### Task 3: Add In-Memory Store Behavior

**Files:**
- Modify: `nodeseek/Features/PostList/VisitedPostStore.swift`
- Create or modify: `nodeseekTests/Features/VisitedPostStoreTests.swift`

- [ ] **Step 1: Write failing store tests**

Add tests for loading latest 1500, updating duplicate visits, and immediate memory visibility after mark.

- [ ] **Step 2: Implement store with injected persistence**

`VisitedPostStore` should load `persistence.loadRecent(limit: 1500)` during init, keep `records` and `visitedIDs`, update memory synchronously in `markVisited`, and call persistence asynchronously on a serial queue.

- [ ] **Step 3: Run store tests**

Run: `make xcode-test-class TEST=VisitedPostStoreTests`

Expected: PASS.

### Task 4: Add SQLite Persistence

**Files:**
- Create: `nodeseek/AppRuntime/Storage/SQLiteVisitedPostPersistence.swift`
- Modify: `nodeseek.xcodeproj/project.pbxproj`
- Create or modify: `nodeseekTests/AppRuntime/SQLiteVisitedPostPersistenceTests.swift`

- [ ] **Step 1: Write failing SQLite tests**

Use a temporary database URL. Verify `upsert`, `loadRecent(limit:)`, duplicate update, and `trim(keepingLatest:)`.

- [ ] **Step 2: Link system SQLite**

Add `OTHER_LDFLAGS = "$(inherited) -lsqlite3";` to app target Debug and Release build settings.

- [ ] **Step 3: Implement SQLite persistence**

Use `import SQLite3`, `sqlite3_open_v2`, prepared statements, bound text/double values, and `INSERT ... ON CONFLICT(post_id) DO UPDATE`.

- [ ] **Step 4: Run SQLite tests**

Run: `make xcode-test-class TEST=SQLiteVisitedPostPersistenceTests`

Expected: PASS.

### Task 5: Wire Production Defaults And Final Verification

**Files:**
- Modify: `nodeseek/Features/PostList/PostListRouter.swift`
- Modify: `nodeseek/Features/PostList/VisitedPostStore.swift`

- [ ] **Step 1: Add default shared store**

Use `VisitedPostStore.shared` backed by `SQLiteVisitedPostPersistence.default`.

- [ ] **Step 2: Inject default store from router**

`PostListRouter.createModule()` should pass the shared store into `PostListPresenter`.

- [ ] **Step 3: Run focused tests**

Run:

```bash
make xcode-test-class TEST=PostListPresenterTests
make xcode-test-class TEST=PostSummaryCellNodeTests
make xcode-test-class TEST=VisitedPostStoreTests
make xcode-test-class TEST=SQLiteVisitedPostPersistenceTests
```

Expected: PASS.

- [ ] **Step 4: Run build-for-testing**

Run: `make xcode-build-tests`

Expected: PASS.

