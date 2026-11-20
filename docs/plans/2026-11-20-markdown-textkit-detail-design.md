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
| 选区范围 | 不跨楼层，不越过图片或表格。每个文字块独立选择。 |
| 执行顺序 | 先建对比测试并跑出改造前基线，再开始改造。 |

## 非目标

- 不动列表页、`UserContent`、发帖页里的 Texture 使用，详情页稳定后另行评估。
- 不改网络请求和页面抓取方式，Markdown 仍取自页面内嵌配置。
- 不追求与网页 HTML 字符串一致，只验收可见内容、交互和视觉。

## 分层设计

```
SharedCore/Markdown（纯逻辑，SwiftPM 可测）
  Markdown 原文 → swift-markdown 语法树 → 站点规则处理 → DetailDocument
    站点规则：表情、@用户、楼层链接、站内外跳转、标题层级
    不支持的结构（标签页、ANSI、复杂表格等）→ 标记该楼回退

AppRuntime/Rendering（UIKit / TextKit，App-hosted 测试）
  DetailDocument + 宽度 + 字号 + 外观 → DetailLayout（后台线程）
    文本块：NSAttributedString + TextKit 1 布局结果 + 分块绘制结果
    图片、表格、代码、引用块：尺寸和子布局
  回退楼层：HTML → 现有 DTCoreText 链路 → 同样产出 DetailLayout

Features/PostDetail（新页面）
  UICollectionView + diffable data source，行高全部来自 DetailLayout
  DetailTextSurfaceView：自绘文字 + UITextInput（只读子集）+ UITextInteraction
```

要点：

- **缓存 `DetailDocument`，不缓存最终富文本**。字号或暗黑模式变化时只重新排版，不重新解析。颜色用动态色，字体走 AppTypography。
- **排版只做一次**：同一份 TextKit 1 布局同时用于测量高度、分块绘制、命中测试（链接点击）和选区矩形。
- 调度沿用 PerchBoard 对话列表的做法：目标楼层和相邻一屏优先，滑出预取范围的任务取消，位图缓存按字节数限额。

### 方案 B 文字视图的范围

`DetailTextSurfaceView` 只读，需要实现的 `UITextInput` 子集：

- 文档范围与位置：`beginningOfDocument`、`endOfDocument`、`position(from:offset:)`、`offset(from:to:)`、`compare`、`textRange(from:to:)`、`text(in:)`。
- 几何：`firstRect(for:)`、`caretRect(for:)`、`selectionRects(for:)`、`closestPosition(to:)`、`characterRange(at:)`。
- 选择：`selectedTextRange`，`tokenizer` 用 `UITextInputStringTokenizer`（按词、按段选择）。
- 编辑相关方法全部空实现（`insertText`、`deleteBackward`、`markedTextRange` 等），`UITextInteraction(for: .nonEditable)`。

配套处理：

- **拷贝**：复制所选范围的纯文本。表情按其代码（如 `:xhj003:`）还是按占位字符复制，在阶段 2 定。
- **链接点击**：单击手势在布局上命中测试。已有选区时单击先清除选区，不触发链接。
- **句中表情 / GIF**：排版时用固定尺寸的附件占位，动图用覆盖在附件位置的图片视图播放，不重绘文字分块。
- **分块绘制**：超过一定高度的文本按行边界切块，在后台绘制成位图。选区高亮由 `UITextInteraction` 绘制在分块之上。
- **无障碍**：整块文字作为 `accessibilityValue`，链接作为独立的无障碍元素。
- **最低版本**：iOS 15。iOS 16 起拷贝菜单由 `UITextInteraction` 自动使用 `UIEditMenuInteraction`，需要在两个系统上分别验证。

## 交互调整

- **正文长按 = 选字**。现有主帖和回复的 `UIContextMenuInteraction`（`PostBodyCellNode.swift:376`、`CommentCellNode.swift:374`）不再挂在正文上。
- 原长按菜单里的"复制 / 投放鸡腿 / 作者筛选 / 编辑"移到楼层头部的"⋯"按钮。头像长按预览作者资料保持不变。
- **复制面板显示 Markdown 原文**，复制按钮复制原文。以下情况改为显示网页可见文字，不暴露原文：
  - 原文缺失；
  - 网页显示的是权限不足、屏蔽或删除提示。
- "⋯"菜单的新文案走现有本地化资源，补齐支持的语言。

## 对比测试（先于改造）

同一套测试分别跑旧链路和新链路，输入都是 47 组样本中的同一楼层：旧链路渲染网页 HTML，新链路渲染 Markdown。

### 1. 渲染速度

- 新增 App-hosted 基准测试类（参照 `ImageIOWebPPerformanceTests` 的写法），每组样本分别计时：
  - 旧链路：HTML → DTCoreText → `RenderedContentBlock` → Texture 节点布局完成。
  - 新链路：Markdown → `DetailDocument` → `DetailLayout` → 文字分块绘制完成。
- 固定宽度、字号和外观，每组预热后重复多次，记录中位数和 P95，并汇总全部样本。
- 结果输出为 JSON 报告，保存到 `.build/` 下，不提交。汇总结论写入 `docs/performance/`。
- 模拟器数据只用于前后相对比较；切换前再用 Release 构建在真机上跑一次，至少包含一台接近 iOS 15 的设备。
- 在旧详情页加 `os_signpost`（解析、富文本生成、布局三段），真机记录三个页面场景（见"验收"）。

### 2. UI 渲染结果

- 对每组样本，在固定宽度下把楼层渲染成截图，覆盖浅色和深色两种外观，以及默认和大号两档字号。
- 改造前先生成**旧链路基线截图**，存放在 `.build/` 下，不提交。
- 新链路产出同样的截图，生成左右对照页，并计算像素差异比例。像素差异只用于排序和人工复查：两套排版引擎不可能做到像素一致，不作为通过条件。
- **硬断言**（新旧都跑，差异即失败）：
  - 可见文字（去除空白后）一致；
  - 链接数量和目标一致（比较解析后的帖子、页码、楼层或用户）；
  - 图片和表情的数量与地址一致；
  - 楼层高度差异在约定容差内（阶段 0 根据基线确定）；
  - 回退楼层走旧链路，结果与基线一致。

### 测试执行

- 解析层测试走 SwiftPM（`make spm-test`）。
- 速度与截图测试走 `make xcode-test-class TEST="类名"`，不手写 `xcodebuild test`。

## 阶段与门槛

每个阶段单独提交，通过门槛后再进入下一阶段。

### 阶段 0：基线
- 实现上节的速度和截图测试，先只接旧链路，跑出基线报告和基线截图。
- 旧详情页加 signpost，在真机记录三个页面场景的数据。
- 确认 swift-markdown 的最低系统版本兼容 iOS 15，并能在 SwiftPM 和 Xcode 工程中同时引入。
- **门槛**：基线报告、基线截图、真机数据齐全，依赖可用。

### 阶段 1：Markdown → DetailDocument
- 在 `SharedCore` 实现解析和站点规则，用 47 组样本写结构测试：内容块、可见文字、链接目标、表情地址、回退判定。
- **门槛**：可渲染楼层的可见文字和链接与网页一致；回退判定覆盖标签页、ANSI、原文缺失和受限提示。

### 阶段 2：TextKit 排版与方案 B 原型（风险优先）
- 实现 `DetailLayout` 和 `DetailTextSurfaceView`，先在独立的调试页面里，用样本中最长的正文验证：
  - 原地选字（按词、按段、拖动手柄）、拷贝、链接点击，以及选区与单击的冲突处理；
  - 句中表情和 GIF、分块绘制；
  - 动态字号、暗黑模式、VoiceOver。
- 把新链路接入对比测试，跑出第一份前后对比。
- **门槛**：方案 B 交互在 iOS 15 和最新系统上都可用；单块渲染速度不差于旧链路。未通过时先回到本阶段解决，不进入整页开发。

### 阶段 3：新详情页骨架
- 通过开关进入新页面，旧页面保留。
- 覆盖楼层头部和"⋯"菜单、正文文本、图片、表情、引用、分页和跳楼层。表格、代码、标签页暂时走回退。
- **门槛**：三个页面场景的真机数据不差于基线；选字、链接、跳楼层可用。

### 阶段 4：复杂块与交互对齐
- 表格横向滚动、代码块、ANSI 终端、标签页、投票、图片预览、作者筛选、回复入口。
- 复制面板改为显示和复制 Markdown 原文（受限情况除外）。
- 动态字号、暗黑模式、长译文逐屏核对。
- **门槛**：对比测试的硬断言全部通过，截图对照逐张复查通过，功能清单全部可用。

### 阶段 5：切换与清理
- 真机 Release 再跑一次完整对比，结论写入 `docs/performance/`。
- 新页面设为默认，观察一个版本后删除旧详情页的 Texture 节点。

## 验收

| 场景 | 体验 | 指标 |
|---|---|---|
| 直达第 2 页指定楼层 | 目标楼层先可读，图片加载后位置稳定 | 进入页面到目标正文可见的 P50 / P95 |
| 快速滚动再回滚 | 短评及时出现，@用户、楼层链接、句中表情可点 | 卡顿时长、回滚重复排版次数、峰值内存 |
| 长帖、表格、标签页 | 表格可横滑，标签可切换，正文可原地选字 | 主线程单次最长耗时、复杂块首次显示耗时 |

## 风险

- **方案 B 复杂度**：`UITextInput` 细节多，放在阶段 2 先验证，不把风险留到整页完成之后。
- **视觉一致性**：DTCoreText 靠 CSS 控制的行高、段距、引用样式，需要逐项用富文本属性还原，靠截图对照把关。
- **站点规则漂移**：站点新增表情或语法时，App 会和网页悄悄不一致。Debug 构建抽样比对两条链路的可见文字和链接数，差异写日志。
- **原文来源**：Markdown 来自页面内嵌配置，不是公开接口，字段缺失时自动回退 HTML。权限不足、屏蔽和删除以网页显示为准。
- **样本覆盖**：47 组样本缺少真实的受限页面，阶段 1 需补采或用构造用例覆盖。
