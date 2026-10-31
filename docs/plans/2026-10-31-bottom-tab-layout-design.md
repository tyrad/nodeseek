# 底部 Tab 布局（可选）

设计稿：
- 多 Tab 布局：`docs/plans/assets/bottom-tab-mockup.png`（第四版）
- 我的页：`docs/plans/assets/me-page-mockup.png`、`docs/plans/assets/me-page-v2-mockup.png`
- 悬浮发帖：`docs/plans/assets/compose-button-mockup.png`
- 布局选择页：`docs/plans/assets/layout-chooser-mockup.png`

## 目标

- 新增「多 Tab 模式」：底部 首页 / 通知 / 我的，首页右下角悬浮发帖。
- 保留现有「阅读模式」（侧边栏），两种布局功能一致，用户自选。
- 升级后弹一次选择页（带缩略图和说明）；选择后**立即切换**，不需要退出登录；设置里可再改。

## 现状

- 根界面：`AppRouter.makeRootViewController()` 返回以帖子列表为根的 `UINavigationController`；开屏结束后 `SceneDelegate` 设置根界面并调用 `WhatsNewModule.presentIfNeeded`。
- 侧边栏 `PostListSideMenuViewController` 收纳：账号头部、帖子 / 评论 / 收藏、设置、最近浏览、搜一搜、发帖、签到、通知；回调都转到 `PostListPresenter` → `PostListRouter`。
- 通知已有原生页 `NotificationViewController`，直接复用，不改。
- 登录态在 WebKit Cookie 中，与根界面无关，所以替换根界面不影响登录。

## 设置项

- `NavigationLayout`：`reading`（阅读模式，默认）/ `tabs`（多 Tab 模式），存 UserDefaults。
- 另存「是否已做过选择」，用于决定是否弹选择页。

## 多 Tab 模式

- 根界面 `UITabBarController`，三个 Tab 各自一个 `UINavigationController`：
  - 首页：现有帖子列表模块；隐藏左上角菜单键与侧边栏（含首个分类右滑打开侧边栏的手势）；保留分类编辑、搜索、排序按钮。
  - 通知：现有 `NotificationViewController`；Tab 角标显示未读数（复用 `PostListNotificationUnreadCountInteractor` 的结果）。
  - 我的：新页面，复用个人页定稿的头部 + 五格数字 + 我的帖子 / 评论 / 收藏；另加 每日签到（行内按钮）、最近浏览；右上角齿轮进设置。未登录时头部显示「登录」。
- 进入二级页面隐藏 Tab 栏（`hidesBottomBarWhenPushed`）。
- iOS 26 起系统自动呈现浮动玻璃底栏；iOS 15–18 为传统底栏，样式用系统默认 + `.label` 选中色。
- 发帖悬浮钮：只在首页；向下滚动隐藏，向上滚动或回到顶部时出现；未登录点按走登录。排序按钮默认位置上移避让。
- 推送深链：多 Tab 模式下在当前选中 Tab 的导航栈中 push（`AppRouter.push` 改为取当前可见导航栈）。

## 布局选择页

- 原生 UIKit 页，全屏呈现，不可下滑关闭。两张卡片：缩略图 + 名称 + 一句说明 + 单选圈，选中卡片 `.label` 描边；底部「开始使用」。
- 缩略图用真机截图放 Assets（浅 / 深两套），实现完成后在模拟器截取。
- 弹出时机：开屏动画结束后，当前版本需要选择且未选过时弹；推送冷启动不弹；与「新功能」页同一次启动不叠加（先弹选择页，新功能页下次启动再弹）。
- 默认选中当前布局（老用户即阅读模式），直接点「开始使用」体验不变。
- 新安装用户同样弹出（与新功能页规则一致）。

## 切换

- `AppRouter` 根据设置构建根界面；切换时替换 `window.rootViewController`，用淡入淡出过渡。
- 切换前关闭已弹出的页面；首页数据重新加载（列表有缓存，影响小）。
- 设置 › 阅读 第一行「界面布局」，进入同款两张卡片页，点选即切换，切换后停留在新布局的「我的」或首页（待定，倾向首页）。

## 影响范围

- `App/AppRouter.swift`、`App/SceneDelegate.swift`
- `Features/PostList`（菜单键、侧边栏、悬浮发帖、排序避让按布局开关）
- `Features/SideMenu`（只在阅读模式挂载，代码不改）
- 新增 `Features/Layout/`（设置项、选择页）、`Features/Me/`（我的页）
- `Features/Settings/SettingsViewController.swift`（新增一行）
- `Features/WhatsNew/WhatsNewModule.swift`（与选择页互斥）

## 分步

1. 设置项 + `AppRouter` 按布局构建根界面 + 运行时替换（先只用设置页切换验证）。
2. 多 Tab 根界面：首页 / 通知接入，角标，二级页隐藏底栏，推送深链。
3. 我的页。
4. 首页悬浮发帖 + 滚动隐藏 + 排序避让。
5. 布局选择页 + 升级弹出 + 与新功能页互斥；截缩略图。

每步单独提交；跑 `make xcode-build-tests` 和相关测试类，浅 / 深色截图确认。

## 已确认

- 选择页从 1.2.0 起弹出（`AppNavigationLayoutSettings.choicePromptVersion`）。
- 设置里切换后落在新布局的首页。

## 实现备注（2026-10-31）

- 「我的」页定稿方案 B（`docs/plans/assets/me-page-v2-mockup.png` 第三张）：资料卡合并账号、五格数字（等级 / 鸡腿 / 星辰 / 粉丝 / 关注）与升级进度条，今日 评论 / 发帖 进度做成进度条旁的一行摘要，避免与个人页重复；我的内容行右侧显示数量；签到行未签到显示描边「签到」，已签到显示「今日 +N 鸡腿」，点按进入现有签到页。
- 悬浮发帖定稿方案 C（`docs/plans/assets/compose-button-mockup.png`）：玻璃胶囊 + 图标与「发帖」文字，iOS 26 用系统液态玻璃，更早系统用模糊材质 + 细描边。
- 选择页缩略图暂用设计稿渲染图（`docs/plans/assets/layout-preview-render.html`），后续可换成真机截图。
- 1.2.0 的「新功能」条目在版本号升到 1.2.0 时再补。
