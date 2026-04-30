# NodeSeek Directory Boundary Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize the NodeSeek iOS source and test tree around runtime boundaries so SwiftPM only sees pure shared logic while Xcode continues to own App-hosted code and tests.

**Architecture:** Keep `nodeseek.xcodeproj` as the App owner and keep SwiftPM as a fast pure-logic test entry only. Move pure Foundation/CoreGraphics/Kanna code to `nodeseek/SharedCore`, iOS runtime infrastructure to `nodeseek/AppRuntime`, lifecycle/resources to `nodeseek/App` and `nodeseek/Resources`, then mirror tests under `nodeseekTests/SharedCore`, `nodeseekTests/AppRuntime`, `nodeseekTests/App`, and `nodeseekTests/Features`.

**Tech Stack:** Swift 5.9, SwiftPM, Xcode project filesystem-synchronized groups, Swift Testing, UIKit, WebKit, Texture, DTCoreText, Kingfisher, SwiftDraw, Kanna.

---

## File Structure

Production source target structure after migration:

```text
nodeseek/
  App/
    AppDelegate.swift
    SceneDelegate.swift
    AppRouter.swift
    Splash/
    ViewController.swift
  SharedCore/
    Composer/CommentComposerContentBuilder.swift
    Domain/ChallengeSession.swift
    Domain/NodeSeekModels.swift
    Domain/NodeSeekResult.swift
    HTTP/ChallengeDetector.swift
    HTTP/FormURLEncoder.swift
    HTTP/HTMLClient.swift
    HTTP/WebRequestFingerprint.swift
    Layout/DetailImageLayout.swift
    Parsing/KannaNodeSeekParser.swift
    Parsing/NodeSeekParser.swift
    Parsing/XPathRules.swift
  AppRuntime/
    Images/AvatarImageLoader.swift
    Images/DetailImageLoader.swift
    Rendering/DTCoreTextHTMLContentRenderer.swift
    Rendering/HTMLContentRenderer.swift
    Rendering/RenderedContentBlock.swift
    Services/NodeSeekService.swift
    UI/NodeSeekDebugConfig.swift
    UI/PageScrubberView.swift
    Web/CookieBridge.swift
    Web/HiddenWebViewCommentSubmissionClient.swift
    Web/HiddenWebViewHTMLClient.swift
    Web/HTTPHTMLClient.swift
    Web/LoginWebViewController.swift
    Web/NodeSeekCommentSubmitter.swift
  Features/
  Resources/
    Assets.xcassets
    Info.plist
```

`ViewController.swift` is an unused app-template `UIViewController`; move it to `App/` with lifecycle code rather than inventing a new top-level bucket.

Test target structure after migration:

```text
nodeseekTests/
  App/
    ArchitectureSkeletonTests.swift
    NodeSeekSplashAnimatorTests.swift
    NodeSeekSplashViewControllerTests.swift
    nodeseekTests.swift
  AppRuntime/
    CookieBridgeTests.swift
    DTCoreTextHTMLContentRendererTests.swift
    HTMLContentRendererTests.swift
    LoginWebViewControllerTests.swift
    NodeSeekCommentSubmitterTests.swift
    NodeSeekServiceTests.swift
    SwiftDrawPerformanceTests.swift
  Features/
  Fixtures/
  SharedCore/
    ChallengeDetectorTests.swift
    ChallengeSessionStoreTests.swift
    CommentComposerContentBuilderTests.swift
    DetailImageLayoutTests.swift
    KannaNodeSeekParserTests.swift
```

`ChallengeSessionStoreTests.swift` moves to `SharedCore` because it only exercises `ChallengeSession.swift`, which is pure shared state and should compile under SwiftPM.

## Task 1: Move SharedCore Source And SwiftPM Tests

**Files:**
- Move: `nodeseek/Core/Domain/*` -> `nodeseek/SharedCore/Domain/`
- Move: `nodeseek/Core/Parsing/*` -> `nodeseek/SharedCore/Parsing/`
- Move: `nodeseek/Core/Networking/HTMLClient.swift` -> `nodeseek/SharedCore/HTTP/HTMLClient.swift`
- Move: `nodeseek/Core/Networking/FormURLEncoder.swift` -> `nodeseek/SharedCore/HTTP/FormURLEncoder.swift`
- Move: `nodeseek/Core/Networking/ChallengeDetector.swift` -> `nodeseek/SharedCore/HTTP/ChallengeDetector.swift`
- Move: `nodeseek/Core/Networking/WebRequestFingerprint.swift` -> `nodeseek/SharedCore/HTTP/WebRequestFingerprint.swift`
- Move: `nodeseek/Core/CommentComposerContentBuilder.swift` -> `nodeseek/SharedCore/Composer/CommentComposerContentBuilder.swift`
- Move: `nodeseek/Core/Rendering/DetailImageLayout.swift` -> `nodeseek/SharedCore/Layout/DetailImageLayout.swift`
- Move: selected tests from `nodeseekTests/Core/` -> `nodeseekTests/SharedCore/`
- Modify: `Package.swift`

- [ ] **Step 1: Create destination directories**

Run:

```bash
mkdir -p nodeseek/SharedCore/{Domain,Parsing,HTTP,Composer,Layout}
mkdir -p nodeseekTests/SharedCore
```

Expected: commands exit 0.

- [ ] **Step 2: Move SharedCore production files with git history**

Run:

```bash
git mv nodeseek/Core/Domain nodeseek/SharedCore/Domain
git mv nodeseek/Core/Parsing nodeseek/SharedCore/Parsing
git mv nodeseek/Core/Networking/HTMLClient.swift nodeseek/SharedCore/HTTP/HTMLClient.swift
git mv nodeseek/Core/Networking/FormURLEncoder.swift nodeseek/SharedCore/HTTP/FormURLEncoder.swift
git mv nodeseek/Core/Networking/ChallengeDetector.swift nodeseek/SharedCore/HTTP/ChallengeDetector.swift
git mv nodeseek/Core/Networking/WebRequestFingerprint.swift nodeseek/SharedCore/HTTP/WebRequestFingerprint.swift
git mv nodeseek/Core/CommentComposerContentBuilder.swift nodeseek/SharedCore/Composer/CommentComposerContentBuilder.swift
git mv nodeseek/Core/Rendering/DetailImageLayout.swift nodeseek/SharedCore/Layout/DetailImageLayout.swift
```

Expected: files no longer exist under the old `Core` paths and appear under `SharedCore`.

- [ ] **Step 3: Move SwiftPM-compatible tests**

Run:

```bash
git mv nodeseekTests/Core/KannaNodeSeekParserTests.swift nodeseekTests/SharedCore/KannaNodeSeekParserTests.swift
git mv nodeseekTests/Core/ChallengeDetectorTests.swift nodeseekTests/SharedCore/ChallengeDetectorTests.swift
git mv nodeseekTests/Core/DetailImageLayoutTests.swift nodeseekTests/SharedCore/DetailImageLayoutTests.swift
git mv nodeseekTests/Core/CommentComposerContentBuilderTests.swift nodeseekTests/SharedCore/CommentComposerContentBuilderTests.swift
git mv nodeseekTests/Core/ChallengeSessionStoreTests.swift nodeseekTests/SharedCore/ChallengeSessionStoreTests.swift
```

Expected: these tests live under `nodeseekTests/SharedCore`.

- [ ] **Step 4: Make `ChallengeSessionStoreTests` SwiftPM-compatible**

Edit `nodeseekTests/SharedCore/ChallengeSessionStoreTests.swift` imports to:

```swift
import Foundation
import Testing

#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif
```

Expected: the test can compile in both `swift test` and Xcode.

- [ ] **Step 5: Replace `Package.swift` target paths**

Replace the `targets` section in `Package.swift` with:

```swift
    targets: [
        .target(
            name: "NodeSeekCore",
            dependencies: [
                "Kanna"
            ],
            path: "nodeseek/SharedCore"
        ),
        .testTarget(
            name: "NodeSeekCoreTests",
            dependencies: [
                "NodeSeekCore"
            ],
            path: "nodeseekTests",
            sources: [
                "SharedCore"
            ],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
```

Expected: `Package.swift` no longer contains `exclude`, no longer references `nodeseek/Core`, and SwiftPM cannot see `AppRuntime`, `Features`, `App`, or `Resources`.

- [ ] **Step 6: Run SwiftPM verification**

Run:

```bash
make spm-test
```

Expected: PASS.

- [ ] **Step 7: Commit Task 1**

Run:

```bash
git add Package.swift nodeseek/SharedCore nodeseekTests/SharedCore
git add -u nodeseek/Core nodeseekTests/Core
git commit -m "refactor: move swiftpm code to shared core"
```

Expected: one commit containing only SharedCore source/test moves and the `Package.swift` simplification.

## Task 2: Move AppRuntime Source And Xcode Runtime Tests

**Files:**
- Move remaining runtime files from `nodeseek/Core/` -> `nodeseek/AppRuntime/`
- Move remaining runtime tests from `nodeseekTests/Core/` -> `nodeseekTests/AppRuntime/`

- [ ] **Step 1: Create destination directories**

Run:

```bash
mkdir -p nodeseek/AppRuntime/{Images,Rendering,Services,UI,Web}
mkdir -p nodeseekTests/AppRuntime
```

Expected: commands exit 0.

- [ ] **Step 2: Move AppRuntime production files**

Run:

```bash
git mv nodeseek/Core/NodeSeekService.swift nodeseek/AppRuntime/Services/NodeSeekService.swift
git mv nodeseek/Core/Networking/HTTPHTMLClient.swift nodeseek/AppRuntime/Web/HTTPHTMLClient.swift
git mv nodeseek/Core/Networking/HiddenWebViewHTMLClient.swift nodeseek/AppRuntime/Web/HiddenWebViewHTMLClient.swift
git mv nodeseek/Core/Networking/HiddenWebViewCommentSubmissionClient.swift nodeseek/AppRuntime/Web/HiddenWebViewCommentSubmissionClient.swift
git mv nodeseek/Core/Networking/LoginWebViewController.swift nodeseek/AppRuntime/Web/LoginWebViewController.swift
git mv nodeseek/Core/Networking/CookieBridge.swift nodeseek/AppRuntime/Web/CookieBridge.swift
git mv nodeseek/Core/Networking/NodeSeekCommentSubmitter.swift nodeseek/AppRuntime/Web/NodeSeekCommentSubmitter.swift
git mv nodeseek/Core/Rendering/RenderedContentBlock.swift nodeseek/AppRuntime/Rendering/RenderedContentBlock.swift
git mv nodeseek/Core/Rendering/HTMLContentRenderer.swift nodeseek/AppRuntime/Rendering/HTMLContentRenderer.swift
git mv nodeseek/Core/Rendering/DTCoreTextHTMLContentRenderer.swift nodeseek/AppRuntime/Rendering/DTCoreTextHTMLContentRenderer.swift
git mv nodeseek/Core/Imaging/DetailImageLoader.swift nodeseek/AppRuntime/Images/DetailImageLoader.swift
git mv nodeseek/Core/Imaging/AvatarImageLoader.swift nodeseek/AppRuntime/Images/AvatarImageLoader.swift
git mv nodeseek/Core/UI/PageScrubberView.swift nodeseek/AppRuntime/UI/PageScrubberView.swift
git mv nodeseek/Core/Networking/NodeSeekDebugConfig.swift nodeseek/AppRuntime/UI/NodeSeekDebugConfig.swift
```

Expected: no runtime production files remain under `nodeseek/Core`.

- [ ] **Step 3: Remove empty old Core directories**

Run:

```bash
rmdir nodeseek/Core/Networking nodeseek/Core/Rendering nodeseek/Core/Imaging nodeseek/Core/UI nodeseek/Core
```

Expected: command exits 0. If a directory is not empty, inspect it with `find nodeseek/Core -maxdepth 3 -type f` before deciding what remains.

- [ ] **Step 4: Move AppRuntime tests**

Run:

```bash
git mv nodeseekTests/Core/NodeSeekServiceTests.swift nodeseekTests/AppRuntime/NodeSeekServiceTests.swift
git mv nodeseekTests/Core/NodeSeekCommentSubmitterTests.swift nodeseekTests/AppRuntime/NodeSeekCommentSubmitterTests.swift
git mv nodeseekTests/Core/CookieBridgeTests.swift nodeseekTests/AppRuntime/CookieBridgeTests.swift
git mv nodeseekTests/Core/DTCoreTextHTMLContentRendererTests.swift nodeseekTests/AppRuntime/DTCoreTextHTMLContentRendererTests.swift
git mv nodeseekTests/Core/HTMLContentRendererTests.swift nodeseekTests/AppRuntime/HTMLContentRendererTests.swift
git mv nodeseekTests/Core/LoginWebViewControllerTests.swift nodeseekTests/AppRuntime/LoginWebViewControllerTests.swift
git mv nodeseekTests/Core/SwiftDrawPerformanceTests.swift nodeseekTests/AppRuntime/SwiftDrawPerformanceTests.swift
```

Expected: no runtime tests remain under `nodeseekTests/Core`.

- [ ] **Step 5: Remove empty old test Core directory**

Run:

```bash
rmdir nodeseekTests/Core
```

Expected: command exits 0. If it does not, inspect remaining files and classify by runtime boundary.

- [ ] **Step 6: Run narrow Xcode build verification**

Run:

```bash
make xcode-build-tests
```

Expected: PASS. If simulator destination is unavailable, run `xcodebuild -showdestinations -project nodeseek.xcodeproj -scheme nodeseek` and rerun with `SIMULATOR_ID=<available-id>`.

- [ ] **Step 7: Commit Task 2**

Run:

```bash
git add nodeseek/AppRuntime nodeseekTests/AppRuntime
git add -u nodeseek/Core nodeseekTests/Core
git commit -m "refactor: move app runtime code out of core"
```

Expected: one commit containing AppRuntime source/test moves only.

## Task 3: Move App Lifecycle, Resources, And App Tests

**Files:**
- Move: `nodeseek/AppDelegate.swift` -> `nodeseek/App/AppDelegate.swift`
- Move: `nodeseek/SceneDelegate.swift` -> `nodeseek/App/SceneDelegate.swift`
- Move: `nodeseek/ViewController.swift` -> `nodeseek/App/ViewController.swift`
- Move: `nodeseek/Assets.xcassets` -> `nodeseek/Resources/Assets.xcassets`
- Move: `nodeseek/Info.plist` -> `nodeseek/Resources/Info.plist`
- Move: `nodeseekTests/ArchitectureSkeletonTests.swift` -> `nodeseekTests/App/ArchitectureSkeletonTests.swift`
- Move: `nodeseekTests/nodeseekTests.swift` -> `nodeseekTests/App/nodeseekTests.swift`
- Modify: `nodeseek.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create resources directory**

Run:

```bash
mkdir -p nodeseek/Resources nodeseekTests/App
```

Expected: commands exit 0.

- [ ] **Step 2: Move App lifecycle files and resources**

Run:

```bash
git mv nodeseek/AppDelegate.swift nodeseek/App/AppDelegate.swift
git mv nodeseek/SceneDelegate.swift nodeseek/App/SceneDelegate.swift
git mv nodeseek/ViewController.swift nodeseek/App/ViewController.swift
git mv nodeseek/Assets.xcassets nodeseek/Resources/Assets.xcassets
git mv nodeseek/Info.plist nodeseek/Resources/Info.plist
git mv nodeseekTests/ArchitectureSkeletonTests.swift nodeseekTests/App/ArchitectureSkeletonTests.swift
git mv nodeseekTests/nodeseekTests.swift nodeseekTests/App/nodeseekTests.swift
```

Expected: root `nodeseek/` contains only boundary directories and root `nodeseekTests/` contains only test boundary directories plus `Fixtures`.

- [ ] **Step 3: Update Xcode Info.plist path**

In `nodeseek.xcodeproj/project.pbxproj`, replace both build-setting values:

```text
INFOPLIST_FILE = nodeseek/Info.plist;
```

with:

```text
INFOPLIST_FILE = nodeseek/Resources/Info.plist;
```

Expected: `rg -n "INFOPLIST_FILE" nodeseek.xcodeproj/project.pbxproj` only shows `nodeseek/Resources/Info.plist`.

- [ ] **Step 4: Update filesystem-synchronized Info.plist exception**

In `nodeseek.xcodeproj/project.pbxproj`, replace the exception:

```text
membershipExceptions = (
    Info.plist,
);
```

with:

```text
membershipExceptions = (
    Resources/Info.plist,
);
```

Expected: Xcode does not try to compile/copy `Resources/Info.plist` as a normal resource while still using it as the app Info.plist.

- [ ] **Step 5: Verify Xcode can list and build after resource move**

Run:

```bash
xcodebuild -list -project nodeseek.xcodeproj
make xcode-build-tests
```

Expected: both commands pass and Xcode can find `nodeseek/Resources/Info.plist` and `nodeseek/Resources/Assets.xcassets`.

- [ ] **Step 6: Commit Task 3**

Run:

```bash
git add nodeseek/App nodeseek/Resources nodeseekTests/App nodeseek.xcodeproj/project.pbxproj
git add -u nodeseek nodeseekTests
git commit -m "refactor: move app lifecycle and resources"
```

Expected: one commit containing App/Resources/test moves plus required project-path updates.

## Task 4: Update Documentation And Test Command Naming

**Files:**
- Modify: `AGENT.md`
- Modify: `Makefile`

- [ ] **Step 1: Update `AGENT.md` directory boundary rules**

Replace section `## 1.1 目录与模块边界` with:

```markdown
## 1.1 目录与模块边界

主 App 由 `nodeseek.xcodeproj` 管理，SwiftPM 只作为纯逻辑快速测试入口，不替代 iOS App 工程。

文件放置规则：

- `nodeseek/SharedCore/`：App 与 SwiftPM tests 共享的纯逻辑。允许 `Foundation`、`CoreGraphics`、`Kanna` 等可在 macOS SwiftPM 测试进程运行的依赖。不得依赖 UIKit、WebKit、Texture、DTCoreText、Kingfisher、SwiftDraw、App 生命周期或模拟器。
- `nodeseek/SharedCore/Domain/`：数据模型、结果类型、跨 feature 共享的纯业务状态。
- `nodeseek/SharedCore/Parsing/`：HTML 解析协议与 Kanna 实现。解析规则优先放在 `XPathRules.swift` 或 parser 内，不要散落到 ViewController。
- `nodeseek/SharedCore/HTTP/`：网络协议、表单编码、challenge 检测、请求指纹等不依赖 App host 的 HTTP 辅助逻辑。
- `nodeseek/SharedCore/Composer/`：评论内容组装等纯字符串/模型转换逻辑。
- `nodeseek/SharedCore/Layout/`：不依赖 UIKit view 生命周期的布局计算。
- `nodeseek/AppRuntime/`：需要 iOS App runtime 或第三方 UI/runtime 框架的基础设施，只走 Xcode 构建和 App-hosted 测试。
- `nodeseek/AppRuntime/Web/`：URLSession/WebKit/Cookie/登录 WebView/发帖提交等 runtime 网络实现。
- `nodeseek/AppRuntime/Rendering/`：UIKit/DTCoreText 富文本渲染实现和渲染 block 模型。
- `nodeseek/AppRuntime/Images/`：图片下载、SVG/GIF、Kingfisher、SwiftDraw 相关逻辑。
- `nodeseek/AppRuntime/UI/`：UIKit 共享控件和 App runtime 调试入口。
- `nodeseek/AppRuntime/Services/`：组合 SharedCore 与 runtime 客户端的服务实现，例如 `NodeSeekService.swift`。
- `nodeseek/Features/`：VIPER feature 层。Presenter/Interactor 可以用 Xcode 单测；ViewController、Router、Texture node 走 App-hosted tests。
- `nodeseek/App/`：App 生命周期、启动动画、根路由和模板 App 控制器。
- `nodeseek/Resources/`：`Info.plist`、`Assets.xcassets` 等 App 资源。
- `nodeseekTests/SharedCore/`：SwiftPM 优先覆盖的纯逻辑测试。测试需要同时支持 SwiftPM 和 Xcode 时使用 `#if SWIFT_PACKAGE` 条件导入。
- `nodeseekTests/AppRuntime/`：依赖 UIKit、WebKit、DTCoreText、Texture、Kingfisher、SwiftDraw 或 App host 的基础设施测试。
- `nodeseekTests/Features/`：feature 层测试，默认走 Xcode。
- `nodeseekTests/App/`：App 生命周期、路由、启动动画等测试。
- `nodeseekTests/Fixtures/`：HTML fixture 和共享测试资源。

新增文件时先按“能否脱离 App host 在 SwiftPM/macOS 测试进程运行”判断目录，不要因为名称像 Core 就放进共享路径。
```

Expected: `AGENT.md` no longer instructs future workers to add files under `nodeseek/Core` or `nodeseekTests/Core`.

- [ ] **Step 2: Update `AGENT.md` command selection rules**

In `AGENT.md`, replace references to old `Core` paths in test selection with the new boundary names:

```markdown
- 改 `SharedCore` 下纯逻辑：先跑 `make spm-test`。
- 改 `AppRuntime`、UIKit、WebKit、Texture、DTCoreText、图片预览、App 生命周期：跑对应 Xcode 窄范围测试。
- 改 `Features` presenter/interactor 或仍依赖 App target 的单测：跑 `make xcode-test-class TEST=测试类名`。
```

Also replace the network/parse core file list with:

```markdown
核心网络与解析文件：

- `nodeseek/AppRuntime/Services/NodeSeekService.swift`
- `nodeseek/AppRuntime/Web/`
- `nodeseek/SharedCore/HTTP/`
- `nodeseek/SharedCore/Parsing/KannaNodeSeekParser.swift`
- `nodeseek/AppRuntime/Rendering/`
```

Expected: `rg -n "nodeseek/Core|nodeseekTests/Core|Core/" AGENT.md` returns no stale placement guidance.

- [ ] **Step 3: Rename curated Xcode runtime test command for clarity**

In `Makefile`, replace:

```make
CORE_TEST_CLASSES := \
```

with:

```make
RUNTIME_TEST_CLASSES := \
```

Replace the `.PHONY` line so it includes both names:

```make
.PHONY: help spm-test xcode-build-tests xcode-test-runtime-core xcode-test-core xcode-test-class xcode-test-full
```

Replace help lines:

```make
		'  make xcode-test-core' \
```

with:

```make
		'  make xcode-test-runtime-core' \
		'  make xcode-test-core  # alias' \
```

Replace target:

```make
xcode-test-core: xcode-build-tests
	xcodebuild -quiet test-without-building $(XCODE_COMMON) $(addprefix -only-testing:nodeseekTests/,$(CORE_TEST_CLASSES))
```

with:

```make
xcode-test-runtime-core: xcode-build-tests
	xcodebuild -quiet test-without-building $(XCODE_COMMON) $(addprefix -only-testing:nodeseekTests/,$(RUNTIME_TEST_CLASSES))

xcode-test-core: xcode-test-runtime-core
```

Expected: old command still works as an alias, while the preferred command name reflects AppRuntime/Xcode semantics.

- [ ] **Step 4: Run documentation/path scan**

Run:

```bash
rg -n "nodeseek/Core|nodeseekTests/Core|path: \"nodeseek/Core\"|Core/" AGENT.md Package.swift Makefile nodeseek nodeseekTests
```

Expected: no stale path references except comments generated by Xcode file headers or intentional historical text outside active guidance.

- [ ] **Step 5: Commit Task 4**

Run:

```bash
git add AGENT.md Makefile
git commit -m "docs: document runtime boundary layout"
```

Expected: one commit containing only docs and Makefile command naming updates.

## Task 5: Final Verification And Boundary Audit

**Files:**
- Inspect: `Package.swift`
- Inspect: `nodeseek/`
- Inspect: `nodeseekTests/`
- Inspect: `nodeseek.xcodeproj/project.pbxproj`

- [ ] **Step 1: Verify source tree shape**

Run:

```bash
find nodeseek -maxdepth 3 -type f | sort
find nodeseekTests -maxdepth 3 -type f | sort
```

Expected:
- `nodeseek/Core` does not exist.
- `nodeseekTests/Core` does not exist.
- `nodeseek/SharedCore` contains only pure SwiftPM-compatible files.
- `nodeseek/AppRuntime` contains UIKit/WebKit/DTCoreText/Kingfisher/SwiftDraw/runtime infrastructure.
- `nodeseek/Resources/Info.plist` and `nodeseek/Resources/Assets.xcassets` exist.

- [ ] **Step 2: Verify SwiftPM target boundary**

Run:

```bash
swift package describe
rg -n "exclude|AppRuntime|Features|Resources|nodeseek/Core|nodeseekTests/Core" Package.swift
```

Expected:
- `swift package describe` succeeds.
- `Package.swift` contains no `exclude`.
- `Package.swift` contains no `AppRuntime`, `Features`, `Resources`, `nodeseek/Core`, or `nodeseekTests/Core`.

- [ ] **Step 3: Run required acceptance tests**

Run:

```bash
make spm-test
make xcode-build-tests
make xcode-test-class TEST=KannaNodeSeekParserTests
```

Expected: all PASS. If simulator destination is unavailable, record the failing destination error, choose an available simulator from `xcodebuild -showdestinations -project nodeseek.xcodeproj -scheme nodeseek`, and rerun with `SIMULATOR_ID=<available-id>`.

- [ ] **Step 4: Run alias sanity check**

Run:

```bash
make -n xcode-test-core
make -n xcode-test-runtime-core
```

Expected: both commands expand successfully and target the same curated runtime test classes.

- [ ] **Step 5: Commit final verification notes only if files changed**

Run:

```bash
git status --short
```

Expected: clean worktree. If verification required a tiny fix, commit it with:

```bash
git add <changed-files>
git commit -m "chore: finish directory boundary migration"
```

## Self-Review

Spec coverage:
- Main merge is handled before this migration plan begins.
- `SharedCore`, `AppRuntime`, `Features`, `App`, and `Resources` target layout is covered.
- SwiftPM is simplified to `path: "nodeseek/SharedCore"` and `sources: ["SharedCore"]`.
- Tests are split by runtime boundary, with SwiftPM tests under `nodeseekTests/SharedCore`.
- Xcode `INFOPLIST_FILE` and filesystem-synchronized `Info.plist` exception updates are explicit.
- `AGENT.md` is updated so future files and test runs follow the new layout.
- Required verification commands are listed in Task 5.

Placeholder scan:
- No step contains TBD/TODO/fill-in placeholders.
- Every move, edit, command, and expected result is explicit.

Risk controls:
- Use `git mv` to preserve history.
- Move resources in a separate task and immediately run Xcode build verification.
- Keep feature files and business behavior untouched.
- Do not delete `nodeseekUITests` in this plan because the current spec is about app/unit-test source boundaries.
