# NodeSeek Core Animation Splash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 iOS 启动后第一屏播放白底 `NS.` 字标 Core Animation 动画，最终视觉与当前 `AppIcon.png` 对齐。

**Architecture:** 系统 `UILaunchScreen` 继续保持静态白底，App 启动完成后由 `SceneDelegate` 先展示自定义 `NodeSeekSplashViewController`。Splash 内部用 `CAShapeLayer` 绘制从 `docs/assets/nodeseek-wordmark-traced.svg` 提取的 `NS` 和青绿色点路径，通过遮罩、光扫、缩放和淡出完成动画；动画结束后切换到 `AppRouter().makeRootViewController()` 生成的主界面。

**Tech Stack:** UIKit, Core Animation, `CALayer`, `CAShapeLayer`, `CAGradientLayer`, Swift Testing, Xcode iOS Simulator。

---

## 现有上下文

- 当前 App 生命周期是 UIKit Scene，入口文件是 `nodeseek/SceneDelegate.swift`。
- 当前主界面由 `nodeseek/App/AppRouter.swift` 的 `makeRootViewController()` 创建。
- 当前 `Info.plist` 使用 `UILaunchScreen` 字典，没有 storyboard 启动画面。
- 动画矢量底稿已经生成在 `docs/assets/nodeseek-wordmark-traced.svg`。
- 最终要和原图完全一致时，动画最后 100-150ms 应交叉淡入完整 `AppIcon.png`，不要只停在描摹矢量层。

## 文件结构

- Create: `nodeseek/App/Splash/NodeSeekSplashVector.swift`
  - 存放 `NS` 和青绿色点的 `CGPath` 构造逻辑、1024 基准画布尺寸、颜色常量、原始 logo 边界。
- Create: `nodeseek/App/Splash/NodeSeekSplashAnimator.swift`
  - 负责创建 Core Animation 层级、播放时间线、处理 Reduce Motion、触发完成回调。
- Create: `nodeseek/App/Splash/NodeSeekSplashViewController.swift`
  - 负责承载 splash view，调用 animator，并在完成后通知外部切换主界面。
- Modify: `nodeseek/SceneDelegate.swift`
  - 启动时先设置 splash controller，再由完成回调切换为主 root。
- Modify: `nodeseek/Assets.xcassets`
  - 如果动画最终交叉淡入完整 PNG，需要新增一个 image set，例如 `SplashFinalLogo.imageset`，复用 `AppIcon.png` 的 1024 源图。
- Create: `nodeseekTests/App/NodeSeekSplashAnimatorTests.swift`
  - 测试路径、图层创建、Reduce Motion 分支、完成回调。

## 动画规格

- 背景：全程白底，避免从现有白底图标跳到黑底。
- 总时长：默认 `1.25s`，最多不要超过 `1.5s`。
- `N`：在 `0.00s-0.45s` 通过斜向/竖向遮罩切出，避免简单淡入。
- `S`：在 `0.30s-0.82s` 通过横向遮罩从左到右扫出。
- 光扫：在 `0.28s-0.85s` 使用窄 `CAGradientLayer` 从左向右经过字标。
- 青绿色点：在 `0.82s-1.08s` 执行 `scale 0.72 -> 1.12 -> 1.0` 和轻微 opacity/glow。
- 最终对齐：在 `1.05s-1.20s` 淡入完整 logo PNG，同时淡出矢量分层，保证最后一帧和图标一致。
- Reduce Motion：不播放遮罩和缩放，只显示最终 logo，`0.18s` 后进入主界面。

---

### Task 1: 固化矢量路径与尺寸常量

**Files:**
- Create: `nodeseek/App/Splash/NodeSeekSplashVector.swift`
- Reference: `docs/assets/nodeseek-wordmark-traced.svg`

- [ ] **Step 1: 创建 Splash 目录**

Run:

```bash
mkdir -p nodeseek/App/Splash
```

Expected: `nodeseek/App/Splash` 存在。项目使用 file system synchronized group，新 Swift 文件放进 `nodeseek` 目录后会被 target 自动识别。

- [ ] **Step 2: 从 SVG 提取路径**

Run:

```bash
rg -n 'path id="(ns|dot)"' docs/assets/nodeseek-wordmark-traced.svg
```

Expected: 输出包含 `path id="ns"` 和 `path id="dot"`。当前 SVG 只包含 `M`、`L`、`Z`，不需要运行时 SVG 解析器。

- [ ] **Step 3: 从 SVG 自动生成矢量 Swift 文件**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
import re

svg = Path("docs/assets/nodeseek-wordmark-traced.svg").read_text()
out = Path("nodeseek/App/Splash/NodeSeekSplashVector.swift")

def extract_path(path_id):
    match = re.search(rf'<path id="{path_id}" d="([^"]+)"', svg)
    if not match:
        raise SystemExit(f"Missing path id={path_id}")
    return match.group(1)

def swift_commands(d):
    tokens = re.findall(r'[MLZ]|-?\d+(?:\.\d+)?', d)
    commands = []
    index = 0
    current = None
    while index < len(tokens):
        token = tokens[index]
        if token in ("M", "L"):
            current = token
            index += 1
            x = float(tokens[index])
            y = float(tokens[index + 1])
            method = "move" if current == "M" else "addLine"
            commands.append(f"        path.{method}(to: CGPoint(x: {x:g}, y: {y:g}))")
            index += 2
        elif token == "Z":
            commands.append("        path.closeSubpath()")
            index += 1
        elif current in ("M", "L"):
            x = float(token)
            y = float(tokens[index + 1])
            method = "move" if current == "M" else "addLine"
            commands.append(f"        path.{method}(to: CGPoint(x: {x:g}, y: {y:g}))")
            index += 2
        else:
            raise SystemExit(f"Unexpected SVG path token: {token}")
    return "\n".join(commands)

wordmark = swift_commands(extract_path("ns"))
accent = swift_commands(extract_path("dot"))

out.write_text(f'''//
//  NodeSeekSplashVector.swift
//  nodeseek
//

import UIKit

enum NodeSeekSplashVector {{
    static let canvasSize = CGSize(width: 1024, height: 1024)
    static let wordmarkColor = UIColor(red: 0x1A / 255.0, green: 0x1F / 255.0, blue: 0x24 / 255.0, alpha: 1)
    static let accentColor = UIColor(red: 0x18 / 255.0, green: 0xB3 / 255.0, blue: 0xB0 / 255.0, alpha: 1)
    static let logoBounds = CGRect(x: 176, y: 273, width: 729, height: 451)
    static let nRevealBounds = CGRect(x: 176, y: 273, width: 334, height: 451)
    static let sRevealBounds = CGRect(x: 505, y: 273, width: 346, height: 451)
    static let dotBounds = CGRect(x: 822, y: 664, width: 83, height: 60)

    static func wordmarkPath() -> CGPath {{
        let path = CGMutablePath()
{wordmark}
        return path
    }}

    static func accentPath() -> CGPath {{
        let path = CGMutablePath()
{accent}
        return path
    }}
}}
''')
PY
```

Expected: `nodeseek/App/Splash/NodeSeekSplashVector.swift` 被生成，运行时不需要读取 SVG，也不需要引入 SVG 解析依赖。

- [ ] **Step 4: Build to catch syntax errors**

Run:

```bash
xcodebuild -project nodeseek.xcodeproj -scheme nodeseek -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected: build succeeds. If `iPhone 16` is unavailable, run `xcrun simctl list devices available` and use an installed iPhone simulator.

---

### Task 2: 实现 Core Animation 图层工厂与时间线

**Files:**
- Create: `nodeseek/App/Splash/NodeSeekSplashAnimator.swift`
- Test: `nodeseekTests/App/NodeSeekSplashAnimatorTests.swift`

- [ ] **Step 1: 先写图层创建测试**

Create `nodeseekTests/App/NodeSeekSplashAnimatorTests.swift`:

```swift
//
//  NodeSeekSplashAnimatorTests.swift
//  nodeseekTests
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct NodeSeekSplashAnimatorTests {
    @Test func animatorInstallsExpectedLogoLayers() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let animator = NodeSeekSplashAnimator(reduceMotion: false)

        animator.install(in: container)

        let layerNames = container.layer.sublayers?.compactMap(\.name) ?? []
        #expect(layerNames.contains("splash.background"))
        #expect(layerNames.contains("splash.n"))
        #expect(layerNames.contains("splash.s"))
        #expect(layerNames.contains("splash.dot"))
        #expect(layerNames.contains("splash.finalLogo"))
    }

    @Test func reduceMotionCompletesWithoutLongAnimation() async {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let animator = NodeSeekSplashAnimator(reduceMotion: true)
        var completed = false

        animator.install(in: container)
        animator.play {
            completed = true
        }

        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(completed)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run:

```bash
xcodebuild -project nodeseek.xcodeproj -scheme nodeseek -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:nodeseekTests/NodeSeekSplashAnimatorTests
```

Expected: fails because `NodeSeekSplashAnimator` does not exist.

- [ ] **Step 3: 创建 animator 骨架**

Create `nodeseek/App/Splash/NodeSeekSplashAnimator.swift`:

```swift
//
//  NodeSeekSplashAnimator.swift
//  nodeseek
//

import UIKit

@MainActor
final class NodeSeekSplashAnimator: NSObject {
    private weak var containerView: UIView?
    private let reduceMotion: Bool
    private let animationDuration: CFTimeInterval

    private let backgroundLayer = CALayer()
    private let nLayer = CAShapeLayer()
    private let sLayer = CAShapeLayer()
    private let dotLayer = CAShapeLayer()
    private let finalLogoLayer = CALayer()
    private var completion: (() -> Void)?

    init(
        reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled,
        animationDuration: CFTimeInterval = 1.25
    ) {
        self.reduceMotion = reduceMotion
        self.animationDuration = animationDuration
        super.init()
    }

    func install(in view: UIView) {
        containerView = view
        configureLayerNames()
        layoutLayers(in: view.bounds)
        view.layer.addSublayer(backgroundLayer)
        view.layer.addSublayer(nLayer)
        view.layer.addSublayer(sLayer)
        view.layer.addSublayer(dotLayer)
        view.layer.addSublayer(finalLogoLayer)
    }

    func play(completion: @escaping () -> Void) {
        self.completion = completion

        guard !reduceMotion else {
            finalLogoLayer.opacity = 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                completion()
            }
            return
        }

        startAnimationTimeline()
    }

    func relayout() {
        guard let containerView else { return }
        layoutLayers(in: containerView.bounds)
    }
}
```

- [ ] **Step 4: 补齐图层配置**

Append to the same file:

```swift
private extension NodeSeekSplashAnimator {
    func configureLayerNames() {
        backgroundLayer.name = "splash.background"
        nLayer.name = "splash.n"
        sLayer.name = "splash.s"
        dotLayer.name = "splash.dot"
        finalLogoLayer.name = "splash.finalLogo"
    }

    func layoutLayers(in bounds: CGRect) {
        backgroundLayer.frame = bounds
        backgroundLayer.backgroundColor = UIColor.white.cgColor

        let logoFrame = aspectFitFrame(for: NodeSeekSplashVector.canvasSize, in: bounds)
        configureShapeLayer(nLayer, frame: logoFrame, path: NodeSeekSplashVector.wordmarkPath(), color: NodeSeekSplashVector.wordmarkColor)
        configureShapeLayer(sLayer, frame: logoFrame, path: NodeSeekSplashVector.wordmarkPath(), color: NodeSeekSplashVector.wordmarkColor)
        configureShapeLayer(dotLayer, frame: logoFrame, path: NodeSeekSplashVector.accentPath(), color: NodeSeekSplashVector.accentColor)

        nLayer.mask = revealMask(for: NodeSeekSplashVector.nRevealBounds, in: logoFrame)
        sLayer.mask = revealMask(for: NodeSeekSplashVector.sRevealBounds, in: logoFrame)

        finalLogoLayer.frame = logoFrame
        finalLogoLayer.contentsGravity = .resizeAspect
        finalLogoLayer.contentsScale = UIScreen.main.scale
        finalLogoLayer.opacity = 0
        finalLogoLayer.contents = UIImage(named: "SplashFinalLogo")?.cgImage
    }

    func configureShapeLayer(_ layer: CAShapeLayer, frame: CGRect, path: CGPath, color: UIColor) {
        layer.frame = frame
        layer.path = path
        layer.fillColor = color.cgColor
        layer.fillRule = .evenOdd
        layer.contentsScale = UIScreen.main.scale
        let scale = frame.width / NodeSeekSplashVector.canvasSize.width
        layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
    }

    func revealMask(for rect: CGRect, in logoFrame: CGRect) -> CALayer {
        let scale = logoFrame.width / NodeSeekSplashVector.canvasSize.width
        let mask = CALayer()
        mask.backgroundColor = UIColor.black.cgColor
        mask.frame = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        return mask
    }

    func aspectFitFrame(for sourceSize: CGSize, in bounds: CGRect) -> CGRect {
        let scale = min(bounds.width / sourceSize.width, bounds.height / sourceSize.height)
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
```

- [ ] **Step 5: 补齐动画时间线**

Append to `NodeSeekSplashAnimator.swift`:

```swift
private extension NodeSeekSplashAnimator {
    func startAnimationTimeline() {
        dotLayer.opacity = 0
        finalLogoLayer.opacity = 0

        animateMaskReveal(layer: nLayer, beginTime: 0.00, duration: 0.45, fromX: -0.35, toX: 0)
        animateMaskReveal(layer: sLayer, beginTime: 0.30, duration: 0.52, fromX: -0.55, toX: 0)
        animateDotPop(beginTime: 0.82)
        animateFinalCrossfade(beginTime: 1.05)

        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) { [weak self] in
            self?.completion?()
            self?.completion = nil
        }
    }

    func animateMaskReveal(layer: CALayer, beginTime: CFTimeInterval, duration: CFTimeInterval, fromX: CGFloat, toX: CGFloat) {
        guard let mask = layer.mask else { return }
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = mask.bounds.width * fromX
        animation.toValue = mask.bounds.width * toX
        animation.beginTime = CACurrentMediaTime() + beginTime
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.fillMode = .backwards
        animation.isRemovedOnCompletion = true
        mask.add(animation, forKey: "reveal")
    }

    func animateDotPop(beginTime: CFTimeInterval) {
        dotLayer.opacity = 1

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.72, 1.12, 1.0]
        scale.keyTimes = [0, 0.62, 1]
        scale.beginTime = CACurrentMediaTime() + beginTime
        scale.duration = 0.26
        scale.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        dotLayer.add(scale, forKey: "dotPop")
    }

    func animateFinalCrossfade(beginTime: CFTimeInterval) {
        finalLogoLayer.opacity = 1

        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.beginTime = CACurrentMediaTime() + beginTime
        fadeIn.duration = 0.15
        fadeIn.fillMode = .backwards
        fadeIn.isRemovedOnCompletion = true
        finalLogoLayer.add(fadeIn, forKey: "finalLogoFadeIn")

        [nLayer, sLayer, dotLayer].forEach { layer in
            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = 1
            fadeOut.toValue = 0
            fadeOut.beginTime = CACurrentMediaTime() + beginTime
            fadeOut.duration = 0.15
            fadeOut.fillMode = .forwards
            fadeOut.isRemovedOnCompletion = false
            layer.add(fadeOut, forKey: "vectorFadeOut")
        }
    }
}
```

- [ ] **Step 6: 跑测试**

Run:

```bash
xcodebuild -project nodeseek.xcodeproj -scheme nodeseek -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:nodeseekTests/NodeSeekSplashAnimatorTests
```

Expected: `NodeSeekSplashAnimatorTests` pass.

---

### Task 3: 新增 Splash View Controller

**Files:**
- Create: `nodeseek/App/Splash/NodeSeekSplashViewController.swift`
- Test: `nodeseekTests/App/NodeSeekSplashViewControllerTests.swift`

- [ ] **Step 1: 写完成回调测试**

Create `nodeseekTests/App/NodeSeekSplashViewControllerTests.swift`:

```swift
//
//  NodeSeekSplashViewControllerTests.swift
//  nodeseekTests
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct NodeSeekSplashViewControllerTests {
    @Test func splashCallsCompletionWhenReduceMotionIsEnabled() async {
        var didFinish = false
        let controller = NodeSeekSplashViewController(reduceMotion: true) {
            didFinish = true
        }

        controller.loadViewIfNeeded()
        controller.viewDidAppear(false)

        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(didFinish)
    }
}
```

- [ ] **Step 2: 实现 View Controller**

Create `nodeseek/App/Splash/NodeSeekSplashViewController.swift`:

```swift
//
//  NodeSeekSplashViewController.swift
//  nodeseek
//

import UIKit

@MainActor
final class NodeSeekSplashViewController: UIViewController {
    private let animator: NodeSeekSplashAnimator
    private let onFinish: () -> Void
    private var didStartAnimation = false

    init(
        reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled,
        onFinish: @escaping () -> Void
    ) {
        self.animator = NodeSeekSplashAnimator(reduceMotion: reduceMotion)
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NodeSeekSplashViewController does not support storyboard initialization")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        animator.install(in: view)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        animator.relayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !didStartAnimation else { return }
        didStartAnimation = true
        animator.play { [weak self] in
            self?.onFinish()
        }
    }
}
```

- [ ] **Step 3: 跑测试**

Run:

```bash
xcodebuild -project nodeseek.xcodeproj -scheme nodeseek -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:nodeseekTests/NodeSeekSplashViewControllerTests
```

Expected: test passes.

---

### Task 4: 接入 SceneDelegate

**Files:**
- Modify: `nodeseek/SceneDelegate.swift`
- Modify: `nodeseekTests/ArchitectureSkeletonTests.swift`

- [ ] **Step 1: 保留 AppRouter 测试**

Run:

```bash
xcodebuild -project nodeseek.xcodeproj -scheme nodeseek -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:nodeseekTests/ArchitectureSkeletonTests
```

Expected: existing architecture tests pass before changing startup flow.

- [ ] **Step 2: 修改 SceneDelegate 启动流程**

Replace `scene(_:willConnectTo:options:)` in `nodeseek/SceneDelegate.swift` with:

```swift
func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene else { return }

    let window = UIWindow(windowScene: windowScene)
    let appRouter = AppRouter()
    window.rootViewController = NodeSeekSplashViewController { [weak window] in
        UIView.transition(
            with: window ?? UIWindow(),
            duration: 0.18,
            options: [.transitionCrossDissolve, .allowAnimatedContent],
            animations: {
                window?.rootViewController = appRouter.makeRootViewController()
            }
        )
    }
    window.makeKeyAndVisible()
    self.window = window
}
```

Then simplify the fallback to avoid creating a temporary `UIWindow()`:

```swift
func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene else { return }

    let window = UIWindow(windowScene: windowScene)
    let appRouter = AppRouter()
    window.rootViewController = NodeSeekSplashViewController { [weak window] in
        guard let window else { return }
        UIView.transition(
            with: window,
            duration: 0.18,
            options: [.transitionCrossDissolve, .allowAnimatedContent],
            animations: {
                window.rootViewController = appRouter.makeRootViewController()
            }
        )
    }
    window.makeKeyAndVisible()
    self.window = window
}
```

- [ ] **Step 3: 跑架构测试**

Run:

```bash
xcodebuild -project nodeseek.xcodeproj -scheme nodeseek -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:nodeseekTests/ArchitectureSkeletonTests
```

Expected: tests still pass because `AppRouter` 行为没有变。

---

### Task 5: 准备最终帧 PNG 资源

**Files:**
- Create: `nodeseek/Assets.xcassets/SplashFinalLogo.imageset/Contents.json`
- Copy: `nodeseek/Assets.xcassets/AppIcon.appiconset/AppIcon.png` to `nodeseek/Assets.xcassets/SplashFinalLogo.imageset/SplashFinalLogo.png`

- [ ] **Step 1: 创建 image set**

Run:

```bash
mkdir -p nodeseek/Assets.xcassets/SplashFinalLogo.imageset
cp nodeseek/Assets.xcassets/AppIcon.appiconset/AppIcon.png nodeseek/Assets.xcassets/SplashFinalLogo.imageset/SplashFinalLogo.png
```

Expected: final logo PNG exists at `nodeseek/Assets.xcassets/SplashFinalLogo.imageset/SplashFinalLogo.png`。

- [ ] **Step 2: 写 Contents.json**

Create `nodeseek/Assets.xcassets/SplashFinalLogo.imageset/Contents.json`:

```json
{
  "images": [
    {
      "filename": "SplashFinalLogo.png",
      "idiom": "universal",
      "scale": "1x"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
```

- [ ] **Step 3: 验证资源可编译**

Run:

```bash
xcodebuild -project nodeseek.xcodeproj -scheme nodeseek -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected: build succeeds and no asset catalog errors.

---

### Task 6: 手动验证启动体验

**Files:**
- No source changes unless verification finds visual defects.

- [ ] **Step 1: 启动模拟器并安装运行**

Run:

```bash
xcodebuild -project nodeseek.xcodeproj -scheme nodeseek -destination 'platform=iOS Simulator,name=iPhone 16' build
xcrun simctl boot "iPhone 16" || true
xcrun simctl install booted "$(find ~/Library/Developer/Xcode/DerivedData -path '*Build/Products/Debug-iphonesimulator/nodeseek.app' | head -1)"
xcrun simctl launch booted com.mist.nodeseek
```

Expected: App 冷启动后先显示白底 `NS.` 动画，约 `1.25s` 后进入帖子列表主界面。

- [ ] **Step 2: 录屏检查最终帧**

Run:

```bash
xcrun simctl io booted recordVideo /tmp/nodeseek-splash.mp4
```

Stop recording after launch with `Control-C`。

Expected visual result:

- 白底不跳黑底。
- `N` 和 `S` 不是整体淡入，而是遮罩切出。
- 青绿色点最后出现，有轻微弹性。
- 动画最后一帧与 `AppIcon.png` 一致，因为已经淡入 `SplashFinalLogo`。
- 进入主界面时无明显白屏或二次闪烁。

- [ ] **Step 3: 验证 Reduce Motion**

In Simulator:

```text
Settings -> Accessibility -> Motion -> Reduce Motion -> On
```

Relaunch app.

Expected: 不播放遮罩和弹性动画，只短暂显示最终 logo 后进入主界面。

---

## 风险与处理

- **启动被拖慢：** Splash 只能覆盖主界面准备过程，不能阻塞主界面数据加载。若冷启动实际超过 `1.5s`，优先缩短动画到 `0.9s`。
- **矢量描摹不完全等于原图：** 动画末尾必须淡入 `SplashFinalLogo`，保证最终帧与 AppIcon 一致。
- **路径填充方向问题：** `CAShapeLayer.fillRule` 使用 `.evenOdd`。如果字形内部孔洞异常，先检查 SVG 子路径是否全部转入同一个 `CGMutablePath`。
- **不同屏幕比例：** 所有层按 1024 画布 `aspectFit` 到当前 view，不直接使用固定点位。
- **重复播放：** 只在 scene 首次连接时播放；后台恢复不在 `sceneWillEnterForeground` 里播放。

## 最终验收

- `xcodebuild ... build` 成功。
- Splash 相关单元测试通过。
- App 冷启动播放一次白底 Core Animation splash。
- Reduce Motion 分支可用。
- 最终停帧和当前 `AppIcon.png` 一致。
- 未引入 Lottie、Rive、视频或运行时 SVG 解析依赖。
