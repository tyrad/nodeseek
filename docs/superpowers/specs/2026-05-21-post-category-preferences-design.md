# 首页分类自定义设计

## 背景

首页顶部 tab 当前直接使用 `PostListCategory.allCases` 生成，顺序固定，所有分类都显示。每个分类对应一个独立的 `PostTextureListHostViewController`，由 `PostPageContainerViewController` 负责横向分页和缓存。设置页已经有“阅读”分组，也有基于 `UserDefaults` 的设置对象和变更通知模式。

本次要让用户在设置里调整首页顶部 tab 的分类顺序，并控制哪些分类显示。

## 目标

- 用户可以在设置里管理首页顶部分类。
- `全部` 永远显示、不能隐藏、固定第一位。
- 其它分类可以调整顺序，也可以隐藏或重新显示。
- 首页在设置变更后自动刷新顶部 tab。
- 当前分类被隐藏时，首页自动切回 `全部`。
- 配置要能兼容未来新增或删除的 `PostListCategory`。

## 非目标

- 不在首页顶部 tab 里直接提供编辑入口。
- 不改变列表排序模式 `replyTime/postTime` 的现有规则。
- 不持久化每个分类列表数据；仍由现有 host 和 presenter 管理。
- 不支持隐藏 `全部`，也不支持把 `全部` 拖到其它位置。

## 用户体验

在 `设置 > 阅读` 中新增一行：

- 标题：`首页分类`
- 副标题：显示摘要，例如 `全部、日常、技术等 10 个`；如果有隐藏分类，显示 `显示 8 个，隐藏 2 个`。
- 点击进入 `PostCategoryPreferencesViewController`。

子页面标题为 `首页分类`，使用 `UITableViewController(style: .insetGrouped)`，分为两个 section：

1. `显示`
   - 第一行固定为 `全部`，不可删除、不可移动。
   - 其它显示分类支持拖拽排序。
   - 其它显示分类支持左滑隐藏，隐藏后移入 `隐藏` section。

2. `隐藏`
   - 展示当前隐藏分类。
   - 点击隐藏分类或使用行操作 `显示`，将其恢复到 `显示` section 末尾。
   - 隐藏 section 不需要排序；恢复后再在显示 section 调整顺序。

footer 文案：

`“全部”始终显示并固定在第一位。隐藏分类不会删除内容，只是不显示在首页顶部。`

## 数据模型

新增 `PostCategoryPreferenceStore`：

```swift
final class PostCategoryPreferenceStore {
    static let didChangeNotification = Notification.Name("PostCategoryPreferenceStore.didChange")
    static let shared = PostCategoryPreferenceStore()

    var visibleCategories: [PostListCategory] { get }
    var hiddenCategories: [PostListCategory] { get }

    func moveVisibleCategory(from sourceIndex: Int, to destinationIndex: Int)
    func hideCategory(_ category: PostListCategory)
    func showCategory(_ category: PostListCategory)
    func resetToDefault()
}
```

持久化结构：

```swift
struct PostCategoryPreferences: Codable, Equatable {
    var orderedVisibleCategories: [PostListCategory]
    var hiddenCategories: [PostListCategory]
}
```

存储位置使用 `UserDefaults.standard`，key 建议为 `postCategoryPreferences.v1`。使用 JSON 编码，便于以后迁移。

## 归一化规则

读取和保存前都执行 normalize：

- 如果没有配置，默认 visible 为 `PostListCategory.allCases`，hidden 为空。
- `.all` 必须存在于 visible，并强制放在第 0 位。
- `.all` 必须从 hidden 中移除。
- 过滤重复分类。
- 过滤当前 enum 中不存在的旧分类值。
- 新增分类默认追加到 visible 末尾。
- hidden 中的分类不能同时出现在 visible 中。
- 如果 visible 异常为空，回退为 `[.all]`。

移动规则：

- `全部` 的 source 或 destination 都不允许移动。
- 其它分类只能在 visible section 内移动，目标下标不能小于 1。

隐藏规则：

- `hideCategory(.all)` 直接忽略。
- 隐藏当前 visible 分类后，该分类进入 hidden 末尾。

显示规则：

- `showCategory(_:)` 从 hidden 移除，并追加到 visible 末尾。
- `showCategory(.all)` 直接忽略，因为 `全部` 已经强制 visible。

## 首页集成

`PostListPresenter` 增加一个可注入的 `PostCategoryPreferenceStore`，初始化时默认使用 `.shared`。`viewDidLoad()` 不再直接渲染 `PostListCategory.allCases`，而是渲染 `store.visibleCategories`。

首页 view 或 presenter 监听 `PostCategoryPreferenceStore.didChangeNotification`。收到通知后：

1. 读取新的 visible categories。
2. 如果当前分类仍可见，保持当前分类。
3. 如果当前分类已不可见，切换到 `.all`。
4. 调用 `renderCategories(_:selected:)` 重新构建 tab。

`PostPageContainerViewController.configure(categories:)` 已经会复用仍可见的 host，并移除不再可见的 host。当前分类不再可见时，它会清空内部 `currentCategory`，上层应传入 `.all` 作为 selected，确保 UI 和容器状态一致。

左边界右滑打开侧栏的逻辑依赖“当前是否在第一个分类”。由于 `全部` 固定第一位，这个交互规则保持不变。

## 设置页集成

`SettingsViewController.ReadingRow` 新增 `.categoryPreferences`，建议放在字体大小预览之后、显示帖子签名之前：

1. 字体大小
2. 字体预览
3. 首页分类
4. 显示帖子签名

新增 cell 使用 `.subtitle`：

- `textLabel`: `首页分类`
- `detailTextLabel`: 基于 store 当前状态生成摘要
- `imageView`: `UIImage(systemName: "list.bullet.rectangle")`
- `accessoryType`: `.disclosureIndicator`

设置页监听 store 变更通知，刷新阅读 section 或对应 row，保证返回设置页后摘要同步。

## 测试

新增 store 单测：

- 默认配置返回 `PostListCategory.allCases`。
- `.all` 永远 visible 且固定第一位。
- 隐藏普通分类后 visible/hidden 正确。
- 显示隐藏分类后追加到 visible 末尾。
- 移动普通分类不能越过 `.all`。
- 损坏或过期配置会 normalize。
- 新增分类默认进入 visible。

新增设置页单测：

- 阅读 section 出现 `首页分类` 入口。
- 入口副标题能反映显示和隐藏数量。
- 子页面 `显示` section 第一行是 `全部`，且不能隐藏或移动。
- 普通分类可以隐藏到 `隐藏` section。
- 隐藏分类可以恢复到 `显示` section 末尾。

新增首页集成单测：

- presenter 首次渲染使用 store 的 visible categories。
- store 变更后首页重新渲染分类。
- 当前分类被隐藏后 selected 回到 `.all`。
- 当前分类仍可见时保持选中状态。

## 风险和边界

- `PostPageContainerViewController` 当前用字典缓存 host。隐藏分类后 host 会从字典移除，对应列表状态会丢失；这是合理行为，因为用户主动隐藏了该 tab。
- 如果用户在子页面调整设置时首页不在导航栈顶，通知仍会触发。首页应只做轻量状态刷新，不主动弹出或打断用户。
- 如果未来分类数量变多，双 section 模式仍可扩展；新增分类默认显示，避免用户旧配置吞掉新入口。

## 验收标准

- `全部` 在设置页和首页都固定第一位，无法隐藏。
- 用户可以隐藏除 `全部` 外的任意分类。
- 用户可以恢复隐藏分类。
- 用户可以调整显示分类顺序，且不能把任何分类移动到 `全部` 前面。
- 首页顶部 tab 顺序和可见性与设置一致。
- 设置变更后无需重启 App 即可生效。
