# NodeSeek iOS Agent Instructions

## 1. 项目定位

这是一个 iOS Swift 项目，主工程为 `nodeseek.xcodeproj`，业务代码在 `nodeseek/`，单元测试在 `nodeseekTests/`，UI 测试在 `nodeseekUITests/`。

当前主要技术栈包括：

- UIKit
- AsyncDisplayKit / Texture
- DTCoreText
- Kingfisher
- Kanna
- WebKit
- JXPhotoBrowser

处理任务时应优先理解现有 VIPER/分层结构，不要为了局部改动引入新的架构风格。

## 1.1 目录与模块边界

主 App 仍然由 `nodeseek.xcodeproj` 管理，SwiftPM 只作为纯逻辑快速测试入口，不替代 iOS App 工程。

文件放置规则：

- `nodeseek/Core/Domain/`：纯数据模型、结果类型、跨 feature 共享的业务实体。不得依赖 UIKit、WebKit、Texture、DTCoreText、Kingfisher。
- `nodeseek/Core/Parsing/`：HTML 解析协议与 Kanna 实现。解析规则优先放在 `XPathRules.swift` 或 parser 内，不要散落到 ViewController。
- `nodeseek/Core/Networking/`：网络协议、URLSession 客户端、表单编码、challenge 检测、提交逻辑。WebKit 宿主类仍可放这里，但不能加入 SwiftPM target。
- `nodeseek/Core/Rendering/`：渲染输入/输出模型和布局纯函数。依赖 UIKit/DTCoreText 的渲染实现仍留在 Xcode App 测试路径，不加入 SwiftPM 快速测试路径。
- `nodeseek/Core/Imaging/`：图片下载、SVG/GIF/Kingfisher/SwiftDraw 相关逻辑。默认不加入 SwiftPM target。
- `nodeseek/Core/UI/`：UIKit 共享控件。只走 Xcode 构建和测试。
- `nodeseek/Features/`：VIPER feature 层。Presenter/Interactor 可以用 Xcode 单测；ViewController、Router、Texture node 走 App-hosted tests。
- `nodeseekTests/Core/`：Core 单测。纯 Foundation/CoreGraphics/Kanna 的测试优先纳入 SwiftPM；UIKit/WebKit/DTCoreText/Texture 测试继续只走 Xcode。
- `nodeseekTests/Features/`：feature 层测试。默认走 Xcode，除非明确拆出纯逻辑模块。

新增 SwiftPM 覆盖文件时，先确认该文件能在 macOS 测试进程中运行：

```text
不能依赖 App 启动
不能依赖模拟器
不能依赖 UIKit 生命周期
不能依赖 WebKit 页面加载
不能依赖 Texture node/view 生命周期
```

## 2. 项目改动边界

- 证据优先：先看崩溃点、日志、调用栈、diff、相关代码，再决定修改。
- 最小修改：优先修根因，不顺手重构无关模块。
- 一次只处理一个主要问题，避免把 UI、网络、解析、缓存同时改动。
- 遇到复杂问题时先拆解计划，明确影响范围和验证方式。

## 3. 常用验证命令

不要频繁启动或重启模拟器；这会拖慢本机开发效率。能用 SwiftPM 或窄范围单元测试验证时，不要默认跑完整模拟器流程。

测试选择规则：

- 改 `Core/Domain`、`Core/Parsing`、`Core/Networking` 中可独立运行的纯逻辑：先跑 `make spm-test`。
- 改 presenter/interactor 或仍依赖 App target 的单测：跑 `make xcode-test-class TEST=测试类名`。
- 改 UIKit、WebKit、Texture、DTCoreText、图片预览、App 生命周期：跑对应 Xcode 窄范围测试。
- 提交前如果改动跨 Core 和 UI，至少跑一次 `make xcode-build-tests`，必要时再跑 `make xcode-test-full`。

纯 Core 逻辑优先使用 SwiftPM：

```bash
make spm-test
```

App-hosted 单测先复用构建产物：

```bash
make xcode-test-class TEST=KannaNodeSeekParserTests
```

需要刷新 Xcode 测试构建产物：

```bash
make xcode-build-tests
```

完整 App 单测：

```bash
make xcode-test-full
```

如果 simulator id 失效，先运行：

```bash
xcodebuild -showdestinations -project nodeseek.xcodeproj -scheme nodeseek
```

涉及 Swift 编译、测试、接口或 UI 节点生命周期时，应尽量跑对应的验证命令并记录结果。

## 3.1 SwiftPM 快速测试维护规则

`Package.swift` 是测试加速入口，不是 App 工程迁移入口。维护时遵守以下规则：

- 新增到 `NodeSeekCore` target 的源码必须能脱离 App host 编译。
- 如果某个文件 import 了 UIKit、WebKit、Texture、DTCoreText、Kingfisher、SwiftDraw，默认不要加入 `NodeSeekCore`。
- 如果测试因为缺少 UIKit/WebKit 类型失败，优先把该测试留在 Xcode 路径，不要为了让 `swift test` 通过而扩大 SwiftPM target。
- fixture 放在 `nodeseekTests/Fixtures/`，测试读取要同时兼容 `Bundle.module` 和 Xcode test bundle。
- Core 测试文件如需同时支持 SwiftPM 和 Xcode，使用：

```swift
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif
```

- SwiftPM 快速测试不替代最终 App 验证。涉及 UI、WebView、Texture node、DTCoreText 布局、图片加载和 App 导航时，仍需跑 Xcode 测试。

## 4. 详情页相关约定

详情页核心文件：

- `nodeseek/Features/PostDetail/PostDetailViewController.swift`
- `nodeseek/Features/PostDetail/Nodes/PostBodyCellNode.swift`
- `nodeseek/Features/PostDetail/Nodes/CommentCellNode.swift`

详情页包含富文本、图片附件、头像加载、评论列表和图片预览。修改时注意：

- DTCoreText 的布局和图片附件尺寸变更会影响 cell 高度。
- 图片加载完成后刷新布局要节流，避免频繁 `reloadData()` 造成抖动。
- 富文本 view 与 Texture node 生命周期要分清：node 可后台构造，UIKit view 只能在 Texture 加载 view 时创建和配置。
- 修详情页崩溃时，优先补覆盖 node 构造、布局、富文本配置的测试。

## 5. 网络与解析

核心网络与解析文件：

- `nodeseek/Core/NodeSeekService.swift`
- `nodeseek/Core/Networking/`
- `nodeseek/Core/Parsing/KannaNodeSeekParser.swift`
- `nodeseek/Core/Rendering/`

约定：

- 解析规则优先集中在 parser 或 `XPathRules`，不要把 HTML 细节散落到 ViewController。
- 网络请求头、Cookie、Cloudflare/challenge 相关逻辑优先复用已有 helper。
- 修改解析时优先增加 fixture 测试，不要只靠真实网络页面验证。

## 6. 测试习惯

- 新增 bugfix 时优先先写失败用例，再改生产代码。
- UI/节点生命周期问题可以用窄范围测试覆盖构造、布局、渲染入口。
- 解析问题优先使用 `nodeseekTests/Fixtures/` 中的 HTML fixture。
- 测试失败时先读完整错误，不要直接猜测修改。

## 7. 列表页视觉风格

首页帖子列表优先采用“极简高密度 iOS 社区阅读流”的方向：

- 保持 iOS 原生感：白底、黑字、浅灰辅助信息、细分割线，避免大面积色块、渐变和装饰性背景。
- 保持论坛/社区信息流效率：重点服务快速扫标题、作者、浏览数、回复数和时间，不把列表项做成卡片。
- 保留 NodeSeek 原站气质：信息密度可以高，但头像、标题、元信息和分割线需要对齐稳定、层级清楚。
- 标题使用较强黑色字重，元信息使用浅灰弱化；颜色主要控制在黑、白、灰，锁等状态图标可少量点缀。
- 顶部分类导航保持轻量横向 tab，选中态用黑色字重和短下划线表达，避免胶囊化或过度品牌化。
- 右侧排序入口可以使用贴边工具柄风格：实色高对比、右侧贴屏、只保留左上/左下圆角，像快捷操作抽屉而不是页面内容。
- 浮动工具入口应克制，不遮挡关键标题和元信息；文案要具体，例如“按发帖时间排序”“按回复时间排序”。
