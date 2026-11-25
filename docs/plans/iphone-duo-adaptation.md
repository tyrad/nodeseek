# iPhone Duo 适配

参考：[Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo)、[HIG: Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)。

## 关键事实

- 外屏 466×678pt，状态栏、导航栏、Tab 栏竖排在右侧；实测详情页 safe area 右侧 84pt。
- 内屏宽高均为 regular size class；半折叠时折痕是 reserved region。
- 开合只触发 trait / 尺寸变化，不重建 scene。
- 只有系统管理的 `navigationItem` / `toolbarItems` / `UITabBar` 会竖排；`customView` 和纯文字按钮不会。
- 自定义 `navigationItem.titleView` 会让系统在顶部保留一条横向导航栏（实测顶部 safe area 82pt，去掉后 24pt）。
- 判断是否竖排：`traitCollection.verticalBarEdge`（iOS 27.1），监听 `UITraitCollection.systemTraitsAffectingVerticalBarEdge`。

## 模拟器操作

- 设备：`iPhone Duo`，`simctl io <UDID> screenshot --display=1` 截外屏。
- `axe tap` 在 Duo 上经常不生效，改用 `axe touch -x X -y Y --down --up --udid <UDID>`。
- 打开帖子：`xcrun simctl openurl <UDID> "nsconnect://post/<id>-<page>"`，再点系统确认框的“打开”。
- 开合屏只能在 Device Hub 里手动操作，命令行没有对应接口。
- 依赖普通 iPhone 布局的单测（如导航栏作者标题）不要在 Duo 模拟器上跑。

## P0 实测（外屏）

| 页面 | 结果 |
|---|---|
| 首页 | 正常，Tab 栏自动竖排 |
| 详情 | 已修：正文被右侧导航栏遮挡；顶部多出 58pt 空白 |
| 通知 | 已修：分段控件被状态栏遮挡，登录提示偏心 |
| 我的 | 已修：卡片和登录按钮被状态栏 / Tab 栏遮挡 |
| 设置 | 正常 |
| 用户评论列表 | 正常（分割线延伸到侧栏下方，可接受） |
| 探针空状态 | 按全宽居中，略偏左，待处理 |

未验证：内屏、半折叠、开合过程中的布局和滚动位置、站内信、发帖页、搜索页。

## 后续

### P2 外屏操作栏（需确认交互）

1. 已做：首页“发帖”在竖排时改为系统栏按钮，进右侧栏；首页此时显示导航栏（竖排，不占顶部）。
2. 已做：详情页竖排时隐藏底部评论栏，右侧栏最下方加“写评论”，复用原登录检查和编辑器。`rightBarButtonItems` 首项竖排时在最下方。
3. 待做：页码胶囊进侧栏；站内信写信页的自定义 `UIToolbar` 改用系统 `toolbarItems`。
4. 待验证：登录后从侧栏打开编辑器的键盘布局；开合屏时入口切换。

### 其他

- 内屏阅读宽度：帖子列表、详情在 regular 宽度下限制正文最大宽度。
- 内屏双栏（`UISplitViewController`）：改动根路由，单独立项。
- 其余 30 多个页面也有“内容贴 view 边缘 + 固定边距”的写法，逐页实测后再修。
