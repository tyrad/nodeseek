# 楼层「查看相关对话」开发方案

长按某条评论楼层即可阅读从该楼延伸出来的对话。以选中楼层为根，按回复关系层叠组织分支；同帖切换不同楼层时复用已扫描的数据。本文为实施依据。[产品约定与效果图](https://github.com/tyrad/nodeseek/issues/12) · [测试计划](../testing/threaded-replies.md)

## 从哪里接入

| 现有入口 | 改动内容 |
| --- | --- |
| [楼层 Cell](../../nodeseek/Features/PostDetail/Markdown/DetailFloorListCell.swift) 与 [楼层菜单](../../nodeseek/Features/PostDetail/Markdown/PostDetailCollectionList.swift) | 在有明确正整数楼层号的评论右侧楼号左侧加入极淡单色细线转折图标按钮（`arrow.turn.down.right`，跟随楼号字体 `.small` + light，固定 `.tertiaryLabel`，与楼号合体为宽松单手点击热区，点击直达「查看相关对话」面板；不加底色边框，不抢占阅读注意力）；同时在长按菜单与 VoiceOver 自定义操作中保留「查看相关对话」入口（首版主楼 `#0` 不提供入口）。保留头像预览、链接、复制、引用的原有入口。 |
| [模型与解析](../../nodeseek/SharedCore/Domain/NodeSeekModels.swift) / [页面解析](../../nodeseek/SharedCore/Parsing/KannaNodeSeekParser.swift) | 保持受限页与屏蔽/删除评论不输出 `Comment.markdown` 的约束；建边与面板展示只认 `Comment.markdown`，不再用 `hasVisibleMarkdown` 过滤，也不做 HTML 兜底。从 `temp-script` 的 `postData.postPageCount` 透出 `PostDetail.totalPages` 供进度提示使用。 |
| [详情 Interactor](../../nodeseek/Features/PostDetail/PostDetailInteractor.swift) 与 [分页服务](../../nodeseek/AppRuntime/Services/NodeSeekService.swift) | 引入单帖协调器统一发起分页请求，在响应进入 Presenter 合并前把成功返回的单页写入索引。普通翻页与面板扫描共用按页去重的在途请求；独立扫描绝不驱动主列表分页、操作来源页预热或滚动状态。 |
| [回复文本生成](../../nodeseek/SharedCore/Composer/CommentComposerContentBuilder.swift) 与 [帖子路由](../../nodeseek/SharedCore/Domain/NodeSeekPostRoute.swift) | 将生成器格式作为解析样例，复用 `NodeSeekCore` 已引入的 `swift-markdown` AST 与 `NodeSeekPostRouteResolver`。关系提取、正文裁剪与子树遍历放在 `SharedCore`；扫描调度、会话状态和面板放在 `Features/PostDetail/ThreadedReplies/`。 |

## 从 Markdown 建边与展示处理

对每条评论 C，先提取正整数楼层号（优先 `anchorID`，其次去掉 `#` 的 `floorText`，绝不把数据库 `id` 当作楼层号）。在 `!detail.isRestricted` 下直接读取 `Comment.markdown`，解析直接目标 P 并登记 `P → C`。不解析 HTML，不从 HTML 反推，也不按用户名或相邻楼层猜测。

1. **基于 `swift-markdown` AST 解析前导结构**：从文档开头消费零或多个连续的顶层 `BlockQuote`，随后检查紧邻的首个 `Paragraph` 开头连续的回复前缀。
   - **引用块**：仅检查每个最外层 `BlockQuote` 的第一行标准引用头（形如 `> @Mori [#3](...) 发布于…`），不递归嵌套引用，跳过引文正文。
   - **回复前缀**：识别连续的 `@作者名 [#N](链接)`，之间允许空格、制表符或换行。利用 `NodeSeekPostRouteResolver` 解析链接（支持相对路径与站内完整地址），要求站内、同 `postID`、数字锚点与显示楼层一致、且 `0 <= target < currentFloor`；**不强校验链接里的页码**。遇到非标准前缀的正文立即停止采集；无效目标（外域、跨帖、非数字锚点、文字与锚点不一致、自引用、未来楼号）被忽略，但不阻断同一评论里紧随其后的合法标准前缀。围栏代码、行内代码、正文普通链接和纯 `@用户名` 不生成边。
2. **重复父引用裁剪（纯 Markdown）**：当子楼 C 挂在直接父楼 P 下展示时，从 `C.markdown` 裁剪指向 P 的前导最外层引用块和前导回复前缀，保留其他目标的引用与正文；若裁剪后正文为空则回退保留原 `markdown`。
3. **纯 Markdown 渲染，不做 HTML 兜底**：面板正文直接走 `DetailMarkdownParser` / `DetailFloorRenderer` 的纯 Markdown 路径；遇到暂不支持的 Markdown 语法时按纯文本段落展示，不切回 HTML/WebView。`markdown == nil` 的楼层（屏蔽、删除或无原文的热评副本）显示轻量占位文案，正式页到达拿到原文后自动覆盖。
4. **按页快照聚合与遍历顺序**：索引按页保存每页贡献的评论与分页状态，再聚合出当前帖的楼层和边。同一楼在多页出现时，正式页来源优先于首页热评副本，有 `markdown` 优先于缺失 `markdown`。刷新单页时替换该页快照，天然清理已修改的旧边与已删除评论，同时不会因首页热评掉榜误删正式页楼层。
5. **上游上下文与子树排序**：
   - 若选中的焦点楼本身回复或引用了上级楼层，沿直接目标向上追溯对话祖先（带访问集合防环，按楼号升序排列），展示在焦点楼上方；若某祖先楼所在页尚未加载，扫描器会优先补查该缺失的祖先页，再从焦点楼所在页向后扫描下游回复（已扫完但父楼被删的页不重复请求）。若第 1 页包含主楼原文且某评论显式回复 `#0`，也可将主楼纳入上游展示。
   - 下游兄弟按楼号数值升序，深度优先输出。多目标形成的同一楼在当前根下只展示、计数一次，归入先遇到的分支；换根重算时其他直接关系仍可查到。计数仅统计下游唯一子楼（不含焦点楼和上游祖先），并用访问集合防止重复展开。

## 扫描与缓存

索引作用域限定在当前详情会话内（按帖子 ID 隔离）。面板只订阅当前选中根的快照；关闭面板立即停止后续拉取并保留已完成页。退出登录、游客登录成功、账号切换或帖子受限状态变化时，生成新会话令牌并清空索引，丢弃迟到回调。

- **顺序推进（不考虑重定向）**：若焦点楼存在尚未加载的上游祖先页，先按目标楼层所在页补查缺失祖先页；上游就绪后按 `pagination?.nextPage` 与 `isLastPage` 从焦点楼所在页向后串行补齐缺页。首页热评只归属于第 1 页快照，不标记其原本所属页已完成。
- **在途合并与独立取消**：普通阅读与扫描同时请求同一页时复用同一底层任务。关闭面板仅取消面板订阅：若普通阅读仍在等待则底层请求继续；若无其他等待者则取消请求，取消与失败均不标完成。
- **节流与长帖保护**：参考「只看 TA」，每连续发起 3 页网络请求后停顿 0.8s（停顿响应取消，关闭面板后不再延迟偷发下一页）。单轮自动连扫上限 20 页，达到上限后暂停并显示「继续查找」按钮供用户按需续扫。
- **完成判定与失败恢复**：仅当从根所在页到已确认末页（`isLastPage && nextPage == nil` 且未标脏）连续覆盖时，才进入已完成态并显示最终数量或空态。命中 Cloudflare 或登录挑战时立即暂停扫描，保留已找到的回复，支持重试。
- **新增与编辑**：本地发评成功或正常刷新发现回复增长时，将原末页标脏待复查，再补查新增页；编辑评论后刷新对应页会自动重算该页关系。已完成且无更新信号时，同帖切换根楼的底层请求数为 0。

## 面板与阅读位置

使用系统底部面板展示：顶部固定标题与关闭按钮。若焦点楼本身回复了其他楼，上方沿左侧主轴用垂直细线依次展示上游祖先链（不额外右移缩进，保留下游宽度）；中间以柔和底色与细分隔线高亮当前选中的焦点楼；下方按父子分支缩进展示下游子楼，左侧用动态适配深浅色的细分支线连接，最多缩进三级。超过三级的楼层沿用三级宽度，并在正文前以「回复 `#上级楼层`」标明直接父楼。当焦点楼（或祖先楼）的直接父楼已展示在其上方时，同样剥离指向该父楼的重复引用头和回复前缀。

- **保持阅读位置**：每次应用新快照前，若列表已向下滚动，记录首个可见楼层的稳定标识与相对视口顶部偏移；应用快照并布局后恢复其屏幕内位置，避免前面分支插入新回复时打断阅读。关闭面板后主详情列表仍停留在打开前的位置。
- **底部状态栏**：区分查找中（显示已找到数量与 `第 X/Y 页` 或 `第 X 页`）、达到单轮上限可继续查找、部分结果失败可重试、已完成（最终总数）及完成且为空（仅扫描完成后显示）。
- **主题、字号与多语言**：全部颜色使用系统动态色，字体复用 `AppTypography` 与 `UIFontMetrics`，同步补齐 `zh-Hans`、`zh-Hant`、`en` 三语资源及单复数表达。

## 实施顺序

1. 在 `SharedCore` 补充 `PostDetail.totalPages`、`CommentReplyRelationParser`（AST 建边 + 父引用裁剪 + 纯 Markdown 文档）与 `ThreadedReplyIndex`，用 `make spm-test` 锁死核心规则。
2. 实现 `ThreadedReplyCoordinator` 并接入 `PostDetailInteractor` / `PostDetailPresenter` / `PostDetailRouter`，确保主列表与扫描共享请求但状态解耦。
3. 接入 `PostDetailCollectionList` 长按菜单与 `ThreadedRepliesSheetViewController` 层叠面板及三语资源，完成 Xcode 单元测试验证。
