# 多 Tab 模式：导航栈移到底栏外层

## 背景

多 Tab 模式现在是「底栏在外、每个 Tab 各一个导航栈」，进入二级页面靠 `hidesBottomBarWhenPushed` 收起底栏。
底栏的收起 / 放回是系统额外做的一段动画，和页面转场是两套东西：手势返回一半松手、快速连续返回、转场同时显隐导航条（首页就是）时容易对不上，底栏会闪一下或残留。iOS 26 的悬浮玻璃底栏单独淡入淡出，更明显。

在现有结构上只能逐个场景排查和修补。

## 方案

导航栈放到最外层，底部 Tab 控制器作为它的根页面：

```
阅读模式：UINavigationController → PostListViewController
多 Tab 模式：UINavigationController → MainTabBarController → 首页 / 通知 / 我的 …
```

- 进入二级页面时整个 Tab 界面（含底栏）一起被推走，返回时一起滑回；不再依赖 `hidesBottomBarWhenPushed` 单独收起底栏。模拟器已测场景（进详情、手势返回、切 Tab、设置里增减 Tab）未再出现残留，但不代表所有转场都有系统保证。
- 两种模式都是「一个导航栈」，只是根页面不同；`AppRouter.navigationController`、推送深链不再区分 Tab。
- 不损失功能：现在二级页面本来就看不到底栏、不能切 Tab，各 Tab 独立导航栈实际没用上。

## 改动清单

1. `MainTabBarController`
   - Tab 子页面直接是各根页面，不再包 `TabRootNavigationController`；删除该类。
   - 子页面写在自己 `navigationItem` 上的标题、左右按钮、返回按钮设置，切 Tab 时同步到 Tab 控制器自己的 `navigationItem`（外层导航条显示的是它）。
   - 再次点按 Tab：直接取选中的根页面判断 `TabReselectHandling`。
   - 未读角标、底栏增减 Tab 复用已建好的根页面，逻辑不变。
2. `AppRouter`
   - 多 Tab 模式根界面改为 `UINavigationController(rootViewController: MainTabBarController())`。
   - `navigationController` 两种模式都直接取根导航栈。
3. `MeViewController.reloadHomeList()`：首页不再包导航栈，直接取 Tab 的第一个子页面。
4. 各页面里的 `navigationController?.pushViewController` 不用改：子页面的 `navigationController` 会向上找到外层导航栈。
5. 测试：删除 `hidesBottomBarWhenPushed` 的用例；「增减 Tab 保留已有页面」改为断言根页面复用。

## 阅读模式

不改结构、不改代码路径：仍是 `UINavigationController(rootViewController: PostListRouter.createModule())`。

## 风险与验证点

- 导航条内容是切 Tab、回到 Tab 界面、增减 Tab 时一次性复制的：页面之后若异步改标题或换成新的按钮对象，需要主动通知 Tab 控制器重新同步（修改原按钮的 `isEnabled` 等不受影响）。

- 导航条内容同步：「通知」右上角两个按钮、「我的」设置按钮、「最近浏览」清扫按钮、各页标题，切 Tab 后是否正确。
- 首页隐藏导航条：首页出现时隐藏外层导航条、离开时显示；切 Tab、进出详情都要看一遍。
- 返回按钮文字：从各 Tab 进入二级页面后左上角返回文字是否合理。
- 苹果建议 Tab 控制器放最外层；放进导航栈能用，但导航条滚动时的透明渐变、大标题等系统联动可能失灵（本项目未用大标题）。
- 在「我的 › 设置 › 自定义底部栏」里增减 Tab：此时 Tab 控制器在导航栈底部，改动要实时生效。
- 推送深链：两种模式都推到外层导航栈。

## 验证

- `make xcode-build-tests`、`make xcode-test-class TEST=AppNavigationLayoutTests`
- 真机：两种模式各走一遍 进详情 / 手势返回 / 切 Tab / 推送跳转 / 设置里切换布局。
