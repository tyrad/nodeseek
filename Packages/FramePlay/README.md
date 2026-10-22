# FramePlay

独立的 Swift 图片动画播放模块。零第三方依赖，使用 ImageIO 解码；NodeSeek 详情页通过宿主适配器接入动态 WebP。

- Swift 6，iOS 15+，macOS 13+。
- 支持动画 WebP、GIF、APNG 和 ImageIO 可解码的单帧位图。
- 主线程管理播放状态，后台解码；按像素规格共享帧，缓存有字节上限。
- 支持不同帧时长、有限/无限循环、暂停恢复、视图复用和失败后的静态回退。
- UIKit 提供 `AnimatedImageView`；macOS 可使用核心播放器的 `CGImage` 回调。

## 使用

将本目录作为本地 Swift Package 添加到需要使用的工程，选择 `FramePlay` product。本仓库的 App 工程已引用此本地包，根 Package.swift 仍为纯逻辑测试入口。接入范围及验证见[主项目集成记录](../../docs/2026-10-22-frameplay-integration.md)。

```swift
import FramePlay
import UIKit

@MainActor
func configure(_ imageView: AnimatedImageView, data: Data, placeholder: UIImage?) {
    let source = AnimatedImageSource(data: data)
    let pixels = Int(ceil(max(imageView.bounds.width, imageView.bounds.height)
                          * imageView.traitCollection.displayScale))
    let configuration = PlaybackConfiguration(maximumPixelSize: max(pixels, 1))
    imageView.onFallback = { reason in
        print("静态回退：", reason)
    }
    imageView.load(source, configuration: configuration, fallbackImage: placeholder)
}
```

在布局确定后计算目标像素尺寸，也可以显式传入。默认最大边为 512 像素；库不因视图后续尺寸变化自动重新加载。Data 由宿主下载或读取，库中没有网络请求和磁盘缓存。

多个视图显示同一资源时，复用同一个 `AnimatedImageSource` 值；重复调用 `AnimatedImageSource(data:)` 会生成不同的资源身份。共享范围还包含目标像素尺寸、缓存规格和解码限制，不会混用不同清晰度的帧。各播放器的时钟、暂停和循环状态独立。

## 核心播放器

```swift
@MainActor
final class Preview {
    let player = AnimatedImagePlayer()

    func load(data: Data, into imageView: UIImageView) {
        player.onFrame = { [weak imageView] frame in
            imageView?.image = frame.map { UIImage(cgImage: $0) }
        }
        player.load(AnimatedImageSource(data: data))
    }
}
```

宿主需持有播放器。所有公开播放器、视图与环境 API 都在 MainActor 上使用；`AnimatedImageSource` 是可跨任务传递的值。普通位图进入 `.staticImage`，不会启动动画，也不会被当作失败。

| 方法 | 语义 |
| --- | --- |
| `play()` | 开始/继续播放；结束或 stop 后从首帧重播；静态回退后不自动重试 |
| `pause()` | 保留画面和播放位置，暂停期间不追赶流逝时间 |
| `stop()` | 保留当前画面，下一次 play 从首帧开始 |
| `reset()` | 清除画面、解除资源订阅并取消旧任务 |
| `AnimatedImageView.prepareForReuse()` | 清除视图及播放器状态，用于列表复用 |
| `AnimatedImageView.setPlaybackVisible(_:)` | 宿主显式通知滚出/进入可见区域 |

UIKit 视图移出窗口或进入后台会暂停，重新可见或激活后根据原播放意图恢复。用户主动 pause/stop 后不会被前台通知自动恢复。仍在窗口中的滚出屏幕、祖先隐藏等情况，由宿主通过 `setPlaybackVisible` 通知；远离可见区且无需保留资源时使用 `prepareForReuse`。

## 帧时序与回退

默认 `.preserveFrames` 等待缺失帧，保留全部内容，允许播放变慢。可配置 `.preserveTiming` 跳过过期显示帧以追随时间轴；解码和完整画布合成仍由后端负责。每帧使用自己的时长，非法/零延时回落为 0.1 秒，最短调度间隔为 1/120 秒。GIF 正数循环值按首轮后的重复次数处理；APNG/WebP 按总轮数处理，0 均表示无限。

静态回退顺序：

1. 最近成功解码并显示的帧。
2. 初始化或首帧失败时，受相同数据/尺寸限制的首帧恢复结果。
3. 调用方提供的静态图。
4. nil；占位内容由宿主负责。

短暂缺帧保留当前画面；连续未恢复超过 `bufferTimeout`（默认 2 秒）后回退。不可恢复的解码错误立即回退。回退进入 `.staticFallback(reason)`，停止时钟、释放订阅和缓存引用，并调用一次 `onFallback`。默认不自动重试；显式再次 `load` 开启新请求。旧请求的晚到结果和用户回调中重入产生的旧事件会被丢弃。

取消是协作式的：正在执行的 ImageIO 同步调用需要返回后才能释放其工作区，但结果不会再更新旧播放器。

## 缓存与调度

```swift
let environment = PlaybackEnvironment(
    maximumConcurrentDecodes: 2,
    maximumBufferBytes: 32 * 1_024 * 1_024
)
let configuration = PlaybackConfiguration(
    maximumPixelSize: 320,
    bufferBytes: 8 * 1_024 * 1_024,
    maximumBufferedFrames: 6,
    bufferTimeout: 2,
    frameDropPolicy: .preserveFrames
)
let player = AnimatedImagePlayer(environment: environment)
```

每个解码源一次只执行一个帧任务；不同源受环境的总并发数约束。每次只提交一帧任务，优先交付待显示帧，再准备后续帧。已显示的帧由播放器持有，暂停、停止或结束后撤销解码需求。

`maximumBufferedFrames` 表示每个活动播放位置的预取窗口，默认 6 帧。共享池合并不同位置的窗口；同步播放仍复用同一个窗口，错峰播放可缓存更多帧，减少重复解码。例如四个相差 3 帧的位置，其六帧窗口合并后为 15 帧，而不是四份 6 帧。该语义在共享缓存修正时明确为按位置计算，单播放器行为不变。

缓存按实际 `bytesPerRow × height` 计费，始终遵守每资源字节数（默认 8 MiB）和环境总字节数（默认 32 MiB）。预算不足时缩短预取窗口，待显示请求依次交付；暂停视图不会占据待解码名额。单帧本身超过资源/环境预算时进入静态回退，暂时的资源竞争交由缓冲超时处理，不会把整个共享源标记为永久失败。环境可通过 `statistics` 查询缓存和任务数量，通过 `trimMemory()` 清除已缓存帧。

字节预算不足以容纳错峰窗口时，仍可能重复解码，默认保帧策略也可能变慢。小动画可由宿主明确配置完整缓存，例如本地 25 帧、320px 样本使用 `maximumBufferedFrames: 25` 和 `bufferBytes: 12 * 1_024 * 1_024` 后只需解码 25 帧；此配置不能直接推广到任意尺寸或帧数。相关取舍见 [验证记录](VALIDATION.md)。

本地样本的 512px 四图错峰在默认 8 MiB 下仍有变慢；宿主显式设置 `bufferBytes: 16 * 1_024 * 1_024` 后，实际缓存约 15 MiB，恢复约 3 秒一轮。库不会自动提高字节预算。

缓存字节数不包含调用方/播放器仍持有的显示帧、压缩 Data、ImageIO 工作区和系统绘制开销；它不是进程内存硬上限。ImageIO 输出先在后台解码为独立 RGBA 位图，以避免惰性源引用把工作带到显示线程；当前输出为 SDR RGB，不保留 HDR 显示能力。

## 测试

在仓库根目录运行核心测试：

```sh
swift test --package-path Packages/FramePlay
```

独立 iOS 测试不依赖 NodeSeek App：

```sh
cd Packages/FramePlay
xcodebuild test -scheme FramePlay \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/iOS CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO
```

实际界面和性能验证使用 `Examples/iOSHarness` 的独立 App 宿主。纯 Swift Package 测试运行器可能没有 UIWindowScene，这种情况下性能用例会明确跳过，不能把帧回调当作渲染通过。宿主通过本机 XcodeGen 生成，开发工具不会成为库的运行时依赖：

```sh
cd Packages/FramePlay/Examples/iOSHarness
xcodegen generate
TEST_RUNNER_FRAMEPLAY_PERFORMANCE=1 xcodebuild test \
  -project FramePlayHarness.xcodeproj -scheme FramePlayHarness \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath ../../.build/Harness CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -only-testing:FramePlayHarnessTests/PerformanceTests/testRealWebPPlaybackMeasurements
```

去掉环境变量和 `-only-testing` 可在宿主中运行全部功能测试；性能用例默认跳过。模拟器型号和系统版本可替换。性能测试输出 JSON 和截图附件，并检查窗口可绘制以及截图存在图像内容。普通功能测试使用可控时钟、故障注入和本地样本，验证回退、取消、重入、缓冲及生命周期，不依赖网络。结果见 [VALIDATION.md](VALIDATION.md)。

## 实现参考

源码为独立实现。职责划分参考 [SDAnimatedImagePlayer](https://github.com/SDWebImage/SDWebImage/blob/master/SDWebImage/Core/SDAnimatedImagePlayer.m)、[SDImageFramePool](https://github.com/SDWebImage/SDWebImage/blob/master/SDWebImage/Private/SDImageFramePool.m)、[Gifu](https://github.com/kaishin/Gifu) 与 [Kingfisher AnimatedImageView](https://github.com/onevcat/Kingfisher/blob/master/Sources/Views/AnimatedImageView.swift)。解码器协议暂为内部实现细节，后续可在不改变播放器使用方式的前提下增加可选后端。
