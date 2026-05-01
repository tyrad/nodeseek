# 已访问帖子缓存设计

## 背景

帖子列表当前只展示服务端返回的 `PostSummary`。用户点进帖子详情后，返回列表时列表项没有任何“已访问”反馈；刷新列表后也无法知道哪些帖子已经看过。

目标是在本地维护一个轻量访问记录，让列表项在点击后立即变灰，并且在后续刷新、分页、切分类和 App 重启后继续生效。

## 目标

- 点击帖子时，当前 row 立即变成已访问样式。
- 返回列表时不依赖整表刷新来更新已访问状态。
- 列表刷新、分页、切分类时，已访问状态根据本地缓存生效。
- 本地只保留最近 1500 条访问记录。
- 持久化实现隐藏在 Store 后面，后续可以替换存储方案。
- 为后续“最近访问帖子”功能保留基础数据。

## 非目标

- 不做完整阅读进度。
- 不同步账号或云端状态。
- 不引入 Core Data 或 SwiftData。
- 不让 cell 直接访问 Store、SQLite 或任何持久化实现。

## 数据模型

访问记录按“最近访问帖子”建模，而不是只保存一个帖子 ID 集合。

```swift
struct VisitedPostRecord: Equatable, Sendable {
    let postID: String
    let title: String
    let url: URL
    let visitedAt: Date
}
```

列表进入 UI 前由 presenter 合成展示模型：

```swift
struct PostListItem: Equatable, Sendable {
    let post: PostSummary
    let isVisited: Bool
}
```

`PostSummary` 继续表示服务端原始列表数据，不加入本地访问状态。

## Store 设计

新增轻量 Store 协议，通过 `PostListPresenter` 初始化参数注入，默认使用共享实例。

```swift
protocol VisitedPostStoreProtocol: AnyObject {
    func isVisited(postID: String) -> Bool
    func markVisited(post: PostSummary, visitedAt: Date)
    func recentRecords(limit: Int) -> [VisitedPostRecord]
}
```

默认实现维护两份内存状态：

- `records`: 最近访问记录，按 `visitedAt` 倒序，最多 1500 条。
- `visitedIDs`: 从 `records` 构建出的 `Set<String>`，用于列表刷新时快速判断。

Store 初始化时从 SQLite 加载最近 1500 条记录并构建内存状态。之后列表加载和 cell 构造不再查询 SQLite。

## 持久化设计

默认持久化使用轻量 SQLite，不使用 `UserDefaults`、JSON 文件、Core Data 或 SwiftData。项目当前没有 SQLite ORM 依赖；第一版优先使用系统 `SQLite3/libsqlite3`，不为这 1500 条访问记录新增第三方数据库框架。

数据库文件放在 App 沙盒的 Application Support 目录下，例如 `Application Support/NodeSeek/visited-posts.sqlite3`。目录创建和路径拼接封装在 persistence 实现内部。

只需要一张表：

```sql
CREATE TABLE IF NOT EXISTS visited_posts (
    post_id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    url TEXT NOT NULL,
    visited_at REAL NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_visited_posts_visited_at
ON visited_posts(visited_at DESC);
```

持久化接口隐藏 SQLite 细节：

```swift
protocol VisitedPostPersistence {
    func loadRecent(limit: Int) throws -> [VisitedPostRecord]
    func upsert(_ record: VisitedPostRecord) throws
    func trim(keepingLatest limit: Int) throws
}
```

点击帖子时，Store 同步更新内存，然后把 `upsert + trim` 投递到串行后台执行上下文。SQLite 写入不阻塞 row 更新和详情页跳转。如果同一个帖子已存在，更新标题、URL 和 `visitedAt`；如果不存在，插入新记录。

App 进入后台时触发 flush 或等待已排队写入收敛，降低最近点击记录未落盘的概率。

## 列表刷新流程

网络返回 `[PostSummary]` 后，presenter 在进入 view 前统一合成 `[PostListItem]`：

1. 读取 Store 当前内存 `visitedIDs`。
2. 对每条 `PostSummary` 执行内存 `Set.contains(post.id)`。
3. 写入当前分类 state。
4. 调用 `view.render(items:)`。

分页追加同样只对新增数据合成 visited 状态。cell 只消费 `PostListItem.isVisited`，不做任何缓存判断。

## 点击流程

点击某个 row 时：

1. presenter 从当前分类 state 中取出 `PostListItem`。
2. 调用 `visitedStore.markVisited(post: item.post, visitedAt: Date())`。
3. 如果该 item 原本不是 visited，只更新 state 中这一条为 `isVisited = true`。
4. 调用 view 的单条更新接口，例如 `renderVisitedState(at:isVisited:)`。
5. `PostTextureListView` reload 当前 row。
6. router 正常 push 到详情页。

这里不刷新整个列表。

## UI 表现

`PostSummaryCellNode` 接收 `PostListItem` 或 `post + isVisited`。已访问时只弱化标题文字颜色，例如从 `.label` 改为 `.secondaryLabel`。

头像、元信息、分割线不变。置顶图标和锁图标沿用现有颜色，避免破坏列表的扫描效率。

## 并发与线程

内存状态由 Store 统一持有。presenter 调用 `markVisited` 时必须立即看到最新内存状态。

SQLite 写入使用串行后台执行，避免并发写入带来的顺序问题。写入失败不回滚 UI 状态，只记录日志；下次启动时以已成功落盘的数据为准。

## 验证计划

- Presenter 测试：加载列表时根据 fake Store 合成 visited 状态。
- Presenter 测试：点击未访问帖子会 mark store、更新单条 item、触发单 row reload、继续导航详情。
- Presenter 测试：点击已访问帖子不重复触发单条 visited 更新，但仍导航详情。
- Presenter 测试：刷新或分页返回同 ID 帖子时自动带 visited 状态。
- Store 测试：初始化只加载最近 1500 条。
- Store 测试：重复访问同一帖子会更新 `visitedAt` 并移动到最近位置。
- Cell 测试：visited 标题颜色变灰，普通标题保持 `.label`。
