# NodeSeek Directory Boundary Redesign

## 背景

当前项目已经建立了 SwiftPM 快速测试入口：

- `Package.swift` 暴露 `NodeSeekCore`
- `make spm-test` 可运行 SwiftPM 下的纯 Core 测试
- `make xcode-test-class` / `make xcode-build-tests` 继续服务 App-hosted Xcode 测试

但当前源码目录仍以 `Core/` 为中心，里面混合了两类代码：

- 可脱离 App 运行、适合 SwiftPM 测试的纯逻辑
- 依赖 UIKit、WebKit、Texture、DTCoreText、Kingfisher、SwiftDraw 或 App runtime 的实现

这会让后续维护者很难仅凭目录判断一个文件是否可以加入 `NodeSeekCore` target。目录边界需要变得更直接。

## 目标

重排目录，让运行边界成为第一层结构：

```text
SharedCore = App 和 SwiftPM tests 共享的纯核心逻辑
AppRuntime = 依赖 iOS App runtime 或第三方 UI/runtime 框架的基础设施
Features = VIPER feature 页面与业务交互
App = App 生命周期、启动、路由
Resources = Info.plist、Assets 等资源
```

改造完成后，维护者应能通过目录快速判断：

- 文件能否进入 SwiftPM 快速测试路径
- 文件是否依赖 App host 或模拟器
- 应该优先跑 `make spm-test` 还是 Xcode 测试

## 非目标

本次目录重构不做以下事情：

- 不把整个 iOS App 迁移到 SwiftPM
- 不拆分多个 Swift package
- 不引入 Tuist、Bazel 或其他工程生成器
- 不重构 VIPER 架构
- 不拆大文件内部逻辑，例如 `PostDetailViewController.swift` 或 `DTCoreTextHTMLContentRenderer.swift`
- 不修改业务行为、UI 表现、网络策略或解析规则

大文件拆分可以作为第二阶段单独设计。

## 目标结构

生产代码目录：

```text
nodeseek/
  App/
    AppDelegate.swift
    SceneDelegate.swift
    AppRouter.swift
    Splash/

  SharedCore/
    Domain/
    Parsing/
    HTTP/
    Composer/
    Layout/

  AppRuntime/
    Services/
    Web/
    Rendering/
    Images/
    UI/

  Features/
    Account/
    CheckIn/
    PostList/
    PostDetail/
    ReplyComposer/

  Resources/
    Assets.xcassets
    Info.plist
```

测试目录：

```text
nodeseekTests/
  SharedCore/
  AppRuntime/
  Features/
  App/
  Fixtures/
```

## 目录职责

### SharedCore

`SharedCore` 是 SwiftPM 快速测试的主要来源。这里的文件必须能在 macOS SwiftPM 测试进程中运行。

允许依赖：

- `Foundation`
- `CoreGraphics`
- `Kanna`
- 其他明确可在 SwiftPM/macOS 测试中运行的纯 Swift 依赖

默认不允许依赖：

- `UIKit`
- `WebKit`
- `AsyncDisplayKit` / Texture
- `DTCoreText`
- `Kingfisher`
- `SwiftDraw`
- App 启动、模拟器、真实系统权限或 View 生命周期

建议内容：

```text
SharedCore/Domain/
  NodeSeekModels.swift
  NodeSeekResult.swift
  ChallengeSession.swift

SharedCore/Parsing/
  NodeSeekParser.swift
  KannaNodeSeekParser.swift
  XPathRules.swift

SharedCore/HTTP/
  HTMLClient.swift
  FormURLEncoder.swift
  ChallengeDetector.swift
  WebRequestFingerprint.swift

SharedCore/Composer/
  CommentComposerContentBuilder.swift

SharedCore/Layout/
  DetailImageLayout.swift
```

### AppRuntime

`AppRuntime` 放需要 iOS App runtime 才成立的基础设施。这里的代码通常走 Xcode App-hosted 测试。

建议内容：

```text
AppRuntime/Services/
  NodeSeekService.swift

AppRuntime/Web/
  HTTPHTMLClient.swift
  HiddenWebViewHTMLClient.swift
  HiddenWebViewCommentSubmissionClient.swift
  LoginWebViewController.swift
  CookieBridge.swift
  NodeSeekCommentSubmitter.swift

AppRuntime/Rendering/
  RenderedContentBlock.swift
  HTMLContentRenderer.swift
  DTCoreTextHTMLContentRenderer.swift

AppRuntime/Images/
  DetailImageLoader.swift
  AvatarImageLoader.swift

AppRuntime/UI/
  PageScrubberView.swift
  NodeSeekDebugConfig.swift
```

`NodeSeekService.swift` 暂时放在 `AppRuntime/Services/`，因为它默认依赖 `HiddenWebViewHTMLClient()`。如果未来要让 `NodeSeekServiceTests` 进入 SwiftPM，应先单独做依赖倒置设计。

### Features

`Features` 继续保留现有 VIPER feature 结构。

```text
Features/PostList/
Features/PostDetail/
Features/Account/
Features/CheckIn/
Features/ReplyComposer/
```

本次不拆 `PostDetailViewController.swift`、Texture nodes 或 feature tests。目录迁移完成并验证稳定后，再单独处理大文件拆分。

### App

`App` 放 App 生命周期、启动动画、根路由。

```text
App/
  AppDelegate.swift
  SceneDelegate.swift
  AppRouter.swift
  Splash/
```

### Resources

`Resources` 放 App 资源和配置。

```text
Resources/
  Assets.xcassets
  Info.plist
```

迁移时需要同步 Xcode build settings 中的 `INFOPLIST_FILE` 和资源路径。

## SwiftPM 更新

目录迁移后，`Package.swift` 应简化为指向 `SharedCore`：

```swift
.target(
    name: "NodeSeekCore",
    dependencies: ["Kanna"],
    path: "nodeseek/SharedCore"
)
```

测试 target 指向 `nodeseekTests/SharedCore`：

```swift
.testTarget(
    name: "NodeSeekCoreTests",
    dependencies: ["NodeSeekCore"],
    path: "nodeseekTests",
    sources: ["SharedCore"],
    resources: [.copy("Fixtures")]
)
```

SwiftPM 不应引用 `AppRuntime`、`Features`、`App` 或 `Resources`。

## 测试更新

测试文件按运行环境迁移：

```text
nodeseekTests/SharedCore/
  KannaNodeSeekParserTests.swift
  ChallengeDetectorTests.swift
  DetailImageLayoutTests.swift
  CommentComposerContentBuilderTests.swift

nodeseekTests/AppRuntime/
  NodeSeekServiceTests.swift
  NodeSeekCommentSubmitterTests.swift
  CookieBridgeTests.swift
  DTCoreTextHTMLContentRendererTests.swift
  HTMLContentRendererTests.swift
  LoginWebViewControllerTests.swift
  SwiftDrawPerformanceTests.swift

nodeseekTests/Features/
  existing feature tests

nodeseekTests/App/
  existing app tests
```

`make spm-test` 只覆盖 `nodeseekTests/SharedCore`。

`make xcode-test-full` 继续覆盖完整 App-hosted 测试。

## Makefile 更新

目录迁移后需要同步：

- `make spm-test` 不变
- `make xcode-test-core` 的 curated test list 改为新的 class 路径仍可运行
- `make xcode-test-class TEST=...` 不变
- `make xcode-build-tests` 不变
- `make xcode-test-full` 不变

如果 `xcode-test-core` 名称造成误解，可以在实施计划中考虑改名为：

```text
xcode-test-runtime-core
```

但本次需求文档不强制改名。

## AGENT.md 更新

迁移完成后，`AGENT.md` 需要同步目录规则：

- `SharedCore` 是 SwiftPM 优先路径
- `AppRuntime` 是 Xcode/App-hosted 路径
- `Features` 保留 VIPER
- `App` 放生命周期和启动
- `Resources` 放资源
- 新增文件时优先根据运行边界选择目录，而不是根据“看起来像 Core”选择目录

## 验收标准

目录迁移完成后必须满足：

```bash
make spm-test
make xcode-build-tests
make xcode-test-class TEST=KannaNodeSeekParserTests
```

均通过。

还需要确认：

- `Package.swift` 不再依赖 `exclude` 维护大量 App runtime 文件
- `NodeSeekCore` 只指向 `nodeseek/SharedCore`
- `nodeseekTests/SharedCore` 下测试可通过 SwiftPM
- `nodeseekTests/AppRuntime` 下测试继续通过 Xcode
- Xcode 工程能找到新的 `Info.plist` 和 `Assets.xcassets`
- `AGENT.md` 与实际目录一致

## 风险与处理

### Xcode 路径引用风险

移动 `Info.plist` 和 `Assets.xcassets` 需要同步 Xcode project build settings 和资源引用。实施计划应把资源迁移放在单独任务，迁移后立即跑 `make xcode-build-tests`。

### SwiftPM target 路径风险

`Package.swift` 迁移到 `nodeseek/SharedCore` 后，如果某个 SharedCore 文件仍依赖 App runtime，会直接暴露为 `make spm-test` 编译失败。处理原则是移动该文件到 `AppRuntime`，不要扩大 SwiftPM target。

### 测试目录命名风险

`nodeseekTests/SharedCore` 和 `nodeseekTests/AppRuntime` 应以运行环境为准，不以原来的 `Core` 目录为准。

### 大文件拆分诱惑

本次只重排目录。`PostDetailViewController.swift`、`DTCoreTextHTMLContentRenderer.swift`、`PostDetailViewControllerTests.swift` 的拆分应另开需求，避免同时引入移动文件和行为重构。

## 推荐实施顺序

1. 迁移 `SharedCore` 源码与 SwiftPM 测试。
2. 更新 `Package.swift`，跑 `make spm-test`。
3. 迁移 `AppRuntime` 源码与 Xcode 测试。
4. 更新 Xcode 资源路径和 `App` / `Resources`。
5. 更新 `AGENT.md` 与 `Makefile`。
6. 跑完整验证。

每一步都应独立提交，便于定位路径迁移引入的问题。
