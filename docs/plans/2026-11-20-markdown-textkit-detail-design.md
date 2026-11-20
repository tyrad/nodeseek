# 详情页 Markdown + TextKit 重写计划

关联：issue #14。样本：`nodeseekTests/Fixtures/post-markdown-pages.json`（13 帖、16 页、47 组同楼层的 Markdown 与网页正文）。

## 目标

- 主帖和回复改为由 Markdown 原文渲染，服务端 HTML 只作逐楼回退。
- 新详情页不再依赖 Texture，改用 UIKit + TextKit 1。
- 正文文字由自绘视图显示，并接入 `UITextInteraction` 实现原地选字（方案 B）。
- 改造前后用同一套测试对比**渲染速度**和**UI 渲染结果**，数据不差于现状才切换。

## 已确认的决定（2026-11-20）

| 问题 | 决定 |
|---|---|
| 文字表面方案 | 最终采用方案 B：TextKit 1 后台排版 + 分块绘制 + `UITextInteraction`。不先做 `UITextView` 版本。 |
| 正文区域长按 | 用于原地选字，出现系统选择手柄和拷贝菜单。 |
| 复制面板 | 保留 `CommentCopySheetViewController`，内容改为该楼的 **Markdown 原文**，复制按钮复制原文。 |
| 选区范围 | 不跨楼层，不越过图片或表格。同一文字块内可跨绘制分块，行内表情作为一个可选附件。 |
| 执行顺序 | 先用旧列表跑基线和截图；新详情页列表完成后，在相同页面场景对比渲染速度。 |
| 回退楼层 | 继续用 DTCoreText 生成富文本，并用现有 `DetailRichTextView`（`DTAttributedTextContentView`）显示，不转换成 TextKit。回退楼层不支持原地选字，只能用复制面板。 |
| 并发隔离 | `SharedCore/Markdown` 的类型和排版快照类型一律显式标注 `nonisolated`；App-hosted 测试断言解析和排版不在主线程执行。 |
| 站点方言 | 以网页（markdown-it）的显示结果为准，逐条对齐 swift-markdown（cmark-gfm）的差异，见「站点 Markdown 方言对齐」。 |

## 非目标

- 不动列表页、`UserContent`、发帖页里的 Texture 使用，详情页稳定后另行评估。
- 不改网络请求和页面抓取方式，Markdown 仍取自页面内嵌配置。
- 不追求与网页 HTML 字符串一致，只验收可见内容、交互和视觉。

## 分层设计

```
SharedCore/Markdown（纯逻辑，SwiftPM 可测）
  可见 Markdown → 识别测评容器边界 → swift-markdown 解析普通块和子页 → 站点规则处理 → DetailDocument
    站点规则：表情、@用户、楼层链接、站内外跳转、标题层级
    测评容器与投票专属解析器 → 标签页、终端、投票内容块
    原文缺失或解析后仍无法完整呈现 → 该楼使用网页正文；受限楼层直接使用网页可见提示

AppRuntime/Rendering（UIKit / TextKit，App-hosted 测试）
  DetailDocument + 宽度 + 字号 + 外观 → DetailLayout（后台线程）
    文本块：NSAttributedString + TextKit 1 布局结果 + 分块绘制结果
    图片、表格、代码、引用块：尺寸和子布局
  回退楼层：网页可见 HTML → DTCoreText → RenderedContentBlock（沿用现有渲染器，不改）
    文本块不转换成 TextKit，由 DetailRichTextView 显示；高度沿用现有 DTCoreText 测量
    表格、代码、终端、标签页等块级内容仍按 RenderedContentBlock 映射到新 UIKit 视图

Features/PostDetail（新页面）
  UICollectionView + diffable data source，行高全部来自 DetailLayout 或回退测量结果
  DetailTextSurfaceView：自绘文字 + UITextInput（只读子集）+ UITextInteraction（仅 Markdown 原生楼层）
  DetailRichTextView：回退楼层的文本显示，无原地选字，长按不触发选字
```

为什么回退不转换成 TextKit：现有正文由 `DetailRichTextView`（继承 `DTAttributedTextContentView`，CoreText 绘制）显示。DTCoreText 用自有属性表达引用块缩进与背景（`DTTextBlocksAttribute`）、列表和附件显示尺寸（`displaySize`），TextKit 1 不识别这些属性，直接交给方案 B 会丢失引用样式、图片尺寸为 0。回退楼层预期很少，保留现有显示链路成本最低，行为也与旧版一致。

要点：

- **缓存 `DetailDocument`，不缓存最终富文本**。字号或暗黑模式变化时只重新排版，不重新解析。颜色用动态色，字体走 AppTypography。
- 每个后台排版任务独占 TextKit 1 对象。主线程使用不可变快照中的 UTF-16 范围、行片段、字符边界和附件矩形完成链接命中与选区查询。楼层内容、宽度、字号或附件尺寸变化时生成新快照；交付前核对楼层标识和布局版本。
- 调度沿用 PerchBoard 对话列表的做法：目标楼层和相邻一屏优先，滑出预取范围的任务取消，位图缓存按字节数限额。
- **并发隔离**：App target 设置了 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`（`project.pbxproj:486`、`:524`），SwiftPM 没有。未标注的 SharedCore 类型在 SwiftPM 测试里跑在后台，到 App 里会被默认隔离到主线程，导致后台解析悄悄退回主线程或编译报错。因此 `SharedCore/Markdown` 的解析器、`DetailDocument` 及其内容块、排版快照类型一律显式标注 `nonisolated` 并满足 `Sendable`，写法参照 `MarkdownPreviewHTMLRenderer.swift:10`、`DetailImageLayout`。App-hosted 测试在解析和排版入口断言 `Thread.isMainThread == false`，在安装 UI 快照处断言主线程。

### 站点 Markdown 方言对齐（阶段 2）

网页由 markdown-it 渲染（见 `docs/plans/2026-10-28-native-new-discussion-design.md` 第 16 行），swift-markdown 基于 cmark-gfm，二者有已知差异。以网页显示结果为准，逐条写断言：

| 差异 | 网页现象 | 处理 |
|---|---|---|
| 单个换行 | 渲染为换行（样本已观察到 `<br>`） | 软换行按硬换行输出 |
| 裸网址自动链接 | 自动加链接 | 核对网址后紧跟中文、全角标点、括号时的链接结束位置 |
| 中文强调 | 待采样 | 核对 `**「强调」**文字`、`**中文**后` 等 CommonMark 边界规则下的写法 |
| 原文中的 HTML | 47 组样本中没有，行为未知 | 先采样确认网页是转义还是渲染；iOS 端一律不执行任意 HTML、脚本或 iframe，无法安全呈现时整楼回退 |
| 标题层级 | 原文 `#` 显示为 `h2` | 按网页层级映射 |

阶段 1 补采上述各类真实样本，并与网页正文配对存入 fixture。

### 测评模板与投票（阶段 2）

- 将 `:::: tabs` 记为 NodeSeek 的站点扩展。实采测评帖 `/post-1067722-1#0` 用 `::: tab-item 标题` 开启子页、`:::` 结束子页、`::::` 结束容器，包含四个标签页和两个 ANSI 围栏代码块。模板作者和其他变体尚未核实。
- 测评解析器在块边界识别容器，保留子页顺序、标题及正文。围栏代码作为内容读取，代码示例里的冒号标记保持字面文本。将 ANSI 块交给终端渲染，保留空格、换行和颜色。
- 投票单独识别。补齐真实投票 Markdown 与网页正文配对样本，复用 `NodeSeekVoteParser.voteID(in:)` 识别已知的 `nsapp://vote?id=…` 引用，生成带 ID 的投票块。选项和投票状态沿用现有投票服务。验证投票前后正文、引用或标签页内的投票，以及代码示例里的同名链接。
- 已知样本必须命中对应专属解析器。另用残缺容器、无法识别的投票结构验证逐楼回退，保留整楼网页内容，避免半楼重复或丢失。受限、屏蔽和删除提示优先于解析原文。

### 方案 B 文字视图的范围

`DetailTextSurfaceView` 只读，需要实现的 `UITextInput` 子集：

- 文档范围与位置：`beginningOfDocument`、`endOfDocument`、`position(from:offset:)`、`offset(from:to:)`、`compare`、`textRange(from:to:)`、`text(in:)`。
- 几何：`firstRect(for:)`、`caretRect(for:)`、`selectionRects(for:)`、`closestPosition(to:)`、`characterRange(at:)`。
- 选择：`selectedTextRange`，`tokenizer` 用 `UITextInputStringTokenizer`（按词、按段选择）。
- 编辑相关方法全部空实现（`insertText`、`deleteBackward`、`markedTextRange` 等），`UITextInteraction(for: .nonEditable)`。

配套处理：

- **拷贝**：复制所选范围的纯文本。选区里的表情复制成它的代码（如 `:xhj003:`），粘贴到回复框里仍然显示为表情。
- **链接点击**：单击手势在布局上命中测试。已有选区时单击先清除选区，不触发链接。
- **表情**：显示为图片，效果与现状一致，规则见下一节。
- **分块绘制**：超过一定高度的文本按行边界切块，在后台绘制成位图。选区高亮由 `UITextInteraction` 绘制在分块之上。
- **无障碍**：整块文字作为 `accessibilityValue`，链接作为独立的无障碍元素。
- **最低版本**：iOS 15。分别在 iOS 15 和当前系统验证第一响应者、系统选择手柄与拷贝命令。
- **原型宿主**：阶段 2 在独立的调试页面验证方案 B，不依赖新列表。

### 表情渲染（与现状一致）

现有效果（DTCoreText 链路）：

- 识别：`sticker` class，或地址包含 `/sticker/`（`StickerImageRules`）。Markdown 中的 `:代码:` 用 `NodeSeekStickerLibrary` 映射到同一地址。
- 尺寸：固定高 65pt（`DetailImageLayout.fixedStickerHeight`），宽度按原图比例，不超过正文宽度。尺寸未知时先用 65×65 占位；`StickerAspectRatioCache` 记录已加载的原图尺寸，下次直接用真实比例，避免回流。
- 位置：作为行内附件嵌在文字中，与正文同一行按基线排列。单独成行时独占一行。
- 播放：GIF / WebP 用 `DetailInlineImageView`（Kingfisher `AnimatedImageView`）自动播放，滑出屏幕暂停；视频表情用 `DetailInlineVideoStickerView`（AVPlayer）循环播放，未播放时显示首帧。
- 交互：点击行为与现状一致。

新链路做法：

- 尺寸计算直接复用 `DetailImageLayout.presentation(kind: .sticker)` 和 `StickerAspectRatioCache`，不另写规则。
- 排版时插入同尺寸的附件占位，分块位图里不画表情。表情由覆盖在附件矩形上的 `DetailInlineImageView` / `DetailInlineVideoStickerView` 显示，复用现有的加载、播放、可见性暂停逻辑。
- 原图尺寸加载后与缓存不同时，只更新该楼的布局，并按现有节流策略刷新。
- 对比测试中，表情的数量、地址、显示尺寸和相对文字的位置列为硬断言；截图对照时单独检查句中表情的基线对齐。
- 回退楼层的表情仍由 `DetailRichTextView` 现有逻辑显示，不受影响。

## 交互调整

- **正文长按 = 选字**（仅 Markdown 原生楼层；回退楼层长按无选字，复制走"⋯"菜单里的复制面板）。现有主帖和回复的 `UIContextMenuInteraction`（`PostBodyCellNode.swift:376`、`CommentCellNode.swift:374`）不再挂在正文上。
- 原长按菜单里的"复制 / 投放鸡腿 / 作者筛选 / 编辑"移到楼层头部的"⋯"按钮。头像长按预览作者资料保持不变。
- **复制面板显示 Markdown 原文**，复制按钮复制原文。以下情况改为显示网页可见文字，不暴露原文：
  - 原文缺失；
  - 网页显示的是权限不足、屏蔽或删除提示。
- "⋯"菜单的新文案走现有本地化资源，补齐支持的语言。

## 改造前基线与新旧列表对比

以已有 47 组样本为基础，补充配对的投票样本。对同一页、同一楼层，旧链路渲染网页 HTML，新链路渲染可见正文的 Markdown 或记录该楼回退原因。

### 1. 渲染速度

- 阶段 1 用现有 Texture 列表建立基线。阶段 2 只做专属解析、原地选字与 UI 验证。阶段 3 新列表完成并接通测评和投票后，用同一套页面驱动分别运行两个入口。
- 两条路径以相同的离线分页数据就绪、开始展示或跳转目标楼层为起点，分别记录目标楼层布局就绪、首帧正文实际可见的耗时。复杂块同时记录其首帧可见时间；两边采用相同的资源和就绪条件。解析、富文本生成、布局和绘制的分段数据用于定位开销。
- 固定设备、构建配置、正文宽度、字号、外观和滚动路径。分别重复冷缓存首次进入、热缓存回滚，记录 P50、P95 和峰值内存；标记每个楼层实际使用的解析路径，单列回退样本。
- 结果输出为 JSON 报告，保存到 `.build/` 下，不提交。汇总结论写入 `docs/performance/`。
- 模拟器数据只用于前后相对比较；切换前再用 Release 构建在真机上跑一次，至少包含一台接近 iOS 15 的设备。
- 分段计时（解析、富文本生成、布局、绘制）只在跑统计时临时加入，新旧两条链路使用相同的计时点。数据记录完成后删除，不提交到业务代码；提交前用 `git diff` 确认旧详情页没有残留改动。真机记录三个页面场景（见"验收"）。

### 2. UI 渲染结果

- 对每组样本，在固定宽度下把楼层渲染成截图，覆盖浅色和深色两种外观，以及默认和大号两档字号。
- 改造前先生成**旧链路基线截图**，存放在 `.build/` 下，不提交。
- 新链路产出同样的截图，生成左右对照页，并计算像素差异比例。像素差异只用于排序和人工复查：两套排版引擎不可能做到像素一致，不作为通过条件。
- **硬断言**（新旧都跑，差异即失败）：
  - 可见文字与段落边界一致，保留词间空格、换行和代码缩进；
  - 链接数量和目标一致（比较解析后的帖子、页码、楼层或用户）；
  - 图片和表情的数量与地址一致；
  - 楼层高度差异在约定容差内（阶段 1 根据基线确定）；
  - 回退楼层走旧链路，结果与基线一致。

### 3. 异步回调与线程隔离回归

邮箱修复 `0b516f0` 给存储的异步 `Transport` 函数类型显式加了 `@MainActor`。提交注释记录，旧版 Swift 转换该闭包时可能破坏传入的 `URLRequest`。详情页需要在实际调用边界验证参数完整性和执行隔离。

- **阶段 1，复用现成检查。** 用 `make xcode-test-class TEST="PostDetailViewControllerTests ListRequestIsolationTests"` 建立旧版对照。前者的 `detailTextureCellsCanBeConstructedOffMainThread` 从后台队列创建并测量主帖与回复节点；后者提供可控挂起、让旧请求最后返回的测试写法。另可参考 `SeekMailAPITests` 将实例方法作为 transport 注入并捕获实参的做法。
- **阶段 2，走正式渲染入口。** 在 App-hosted 测试中通过生产使用的闭包类型保存、传递并调用真实的方法引用。后台处理主帖、回复及 HTML 回退，跨挂起点核对楼层 ID、正文、宽度和布局版本；在 UI 回调内检查主线程并核对实际安装的快照。UI 回调的函数类型显式声明主 actor；后台排版任务独占 TextKit 对象，只交付不可变结果。App target 使用默认 MainActor 隔离，因此此项需要在 App 的编译设置下执行。
- **阶段 3，控制完成顺序。** 挂起楼层 A 的附件加载或排版，在 cell 已复用于楼层 B 后交付 A；另测同一楼层更换字号，以及页面退出后回调才到达。断言新楼层的内容和选区正确、过期结果未安装、已退出页面可释放。用测试同步点控制先后顺序。
- **阶段 4，复核发布构建。** 用 TestFlight 打包所用的 Xcode 和 Release 优化配置，在真机重复打开测评帖、快速滚动、跳楼和退出重进。记录 Xcode/Swift 版本、设备、系统和结果；若出现崩溃，保存符号化调用栈和触发步骤。把这项检查与速度报告分别记录。

### 测试执行

- 解析层测试走 SwiftPM（`make spm-test`）。
- 速度与截图测试走 `make xcode-test-class TEST="类名"`，不手写 `xcodebuild test`。

## 分阶段开发与测试 TODO

### 1. 建立旧版基线

- [x] 采集 13 个主题、16 个页面，保留 47 组 Markdown 原文与网页正文配对样本。
- [ ] 补齐真实投票原文、网页正文和可回放的投票状态，保存完整分页顺序、目标楼层和离线媒体素材。
- [ ] 补采方言样本：单个换行、裸网址后紧跟中文或全角标点、中文强调边界、原文中的 HTML，与网页正文配对存入 fixture。
- [ ] 验证选定版本的 swift-markdown 在项目 SwiftPM 目标和最低 iOS 15 的 App 目标中均可编译，按项目习惯用 `exact` 固定版本，确认其依赖的 swift-cmark 同样兼容。
- [ ] 在旧 Texture 详情页回放样本，保存浅色、深色和默认、大号字号的基线截图。分别记录占位态和加载完成态，动图固定帧，播放行为单独验证。
- [ ] 运行现有后台节点构建和请求乱序回归：`make xcode-test-class TEST="PostDetailViewControllerTests ListRequestIsolationTests"`。
- [ ] **阶段验收**　在同一真机和 Release 配置下重复跑直达第 2 页目标楼层、快速滚动再回滚、打开复杂测评帖三个场景。保存冷、热数据、截图、运行参数和验收容差。

### 2. 实现专属解析器与方案 B 原型

- [ ] 在 SharedCore 实现 Markdown 到 `DetailDocument` 的转换。按 `commentId` 为主帖和回复关联原文，支持正文、引用、链接、图片和行内表情。解析器、文档模型和排版快照类型显式标注 `nonisolated` 并满足 `Sendable`。
- [ ] 实现站点方言对齐，逐条为单个换行、裸网址边界、中文强调、原文 HTML 和标题层级写断言；原文 HTML 无法安全呈现时整楼回退。
- [ ] 实现 `:::: tabs` 测评解析器，断言最长样本走原生路径，四个标签页按序切换，两个 ANSI 代码块保留颜色、空格和换行。
- [ ] 实现投票专属解析器，核对投票 ID、嵌套位置、前后正文和状态展示。
- [ ] 验证逐楼回退及嵌套内容的 UIKit 展示。回退楼层文本用 `DetailRichTextView` 显示，长按不触发选字，复制面板可用。可见原文解析失败时显示整楼网页内容；受限、屏蔽、删除或可见性不明确时，展示与复制均取网页可见内容。
- [ ] 在独立调试页实现 TextKit 1 后台排版、分块绘制与只读原地选字。用长中文、组合 emoji 和 RTL 文本验证跨绘制分块拖选；选区止于楼层、块级图片或表格边界。
- [ ] 按现有规则展示行内表情，核对 65 pt 高度、比例、基线和 GIF 播放。复制包含表情的选区，检查剪贴板中的表情代码。
- [ ] App-hosted 测试断言 Markdown 解析和 TextKit 排版入口不在主线程执行，UI 快照安装在主线程执行。
- [ ] **阶段验收**　在 iOS 15 和当前系统验证选字、拷贝、链接、动态字号和 VoiceOver；通过真实渲染回调核对挂起前后的楼层 ID、正文、宽度和布局版本。

### 3. 完成 UIKit 列表并正式对比

- [ ] 用 `UICollectionView` 接入主帖、回复、跨页热评、分页和跳楼。按展示位置区分同一评论的热评和分页条目，图片回填后保持可见楼层锚点。
- [ ] 接入签名、图片预览、表格横滚、代码、测评标签页、投票状态刷新、作者筛选和回复。验证普通图片、行内表情和视频表情各自的点击行为。
- [ ] 正文长按直接选字；楼层菜单保留复制面板，分别验证主帖和回复可复制完整的可见 Markdown 原文。
- [ ] 验证并发与复用。让 A 楼的结果在 cell 已显示 B 楼后返回，核对 B 的正文和选区；另测同楼层字号变化和退出页面后回调才到达。
- [ ] 接通 UIKit / Texture 切换开关，通过两个入口分别验证普通打开和直达楼层。
- [ ] **阶段验收**　完整列表接通后，在同一真机重跑阶段 1 的三个场景。按相同起止点比较布局就绪和正文首帧可见的冷、热 P50/P95，以及卡顿和峰值内存。单列回退样本，复核含辅助功能字号的 UI 对照图及硬断言。

### 4. 发布、回切与清理

- [ ] 用 TestFlight 打包工具链和候选 Release 包真机复核打开测评帖、快速滚动、跳楼、退出重进及异步回调。记录工具链、设备、系统和结果，在 `docs/performance/` 保存性能结论。
- [ ] 验证发布版能切回 Texture 详情页；功能和性能验收通过后，默认启用新版并保留开关。
- [ ] 观察线上崩溃、滚动、选字、测评和投票反馈；出现回归时回切并复现。
- [ ] **阶段验收**　稳定运行后再评估清理，逐项核查发帖预览等共享调用方，只清理已迁移的 Texture 节点。

## 验收

| 场景 | 体验 | 指标 |
|---|---|---|
| 直达第 2 页指定楼层 | 目标楼层先可读，图片加载后位置稳定 | 进入页面到目标正文可见的 P50 / P95 |
| 快速滚动再回滚 | 短评及时出现，@用户和楼层链接可点，行内 GIF 可见时播放、离屏暂停 | 卡顿时长、回滚重复排版次数、峰值内存 |
| 长帖、表格、标签页 | 表格可横滑，标签可切换，正文可原地选字 | 主线程单次最长耗时、复杂块首次显示耗时 |

## 风险

- **方案 B 复杂度**：`UITextInput` 细节多，放在阶段 2 先验证，不把风险留到整页完成之后。
- **视觉一致性**：DTCoreText 靠 CSS 控制的行高、段距、引用样式，需要逐项用富文本属性还原，靠截图对照把关。
- **站点规则漂移**：站点新增表情或语法时，App 会和网页悄悄不一致。Debug 构建抽样比对两条链路的可见文字和链接数，差异写日志。
- **原文来源**：Markdown 来自页面内嵌配置，不是公开接口，字段缺失时自动回退 HTML。权限不足、屏蔽和删除以网页显示为准。
- **样本覆盖**：47 组样本缺少真实的受限页面，阶段 1 需补采或用构造用例覆盖。
