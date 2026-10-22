# FramePlay 独立审核与性能复测

状态更新：以下为修正前的审核记录。共享缓存的连带回退和错峰窗口问题已在后续实现中核实并局部修正，预期失败标记已移除；当前测试、配置语义及性能取舍见 [VALIDATION.md](VALIDATION.md)。保留下文作为修正前的证据，不代表当前实现状态。

日期：2026-10-22。比较基线：`a4c24b58d85ce7bb152800f649ebb41ac7879cf5`。

本轮审查全部 7 个生产源码文件，共 1,058 行。仅新增审核测试与本文，未修改库实现、App 工程或业务图片流程。

## 审核结论

ImageIO 解码、后台准备帧、主线程播放及静态回退的边界合理；零依赖、输入完整 Data 的设计适合轻量模块。目前最需要处理的是共享帧池，暂不建议按“任意独立播放位置均流畅”的能力集成。

### P2：共享帧数不足会让所有订阅者一起回退

位置：`Sources/FramePlay/PlaybackEnvironment.swift:234`，相关需求计算见第 134 行。

`pump()` 将不同观察者的当前索引数与共享池容量比较，超过容量后直接设置整个 `FrameStore.failure`。暂停者仍保留索引需求，即使播放器本身已经持有显示帧，也会占用这个名额。

稳定复现：同一资源的 7 个播放器分别暂停在第 0–6 帧，使用默认 6 帧缓存和充足的 32 MiB 环境预算。第 7 个位置出现后，7 个播放器全部进入 `.staticFallback(.resourceLimitExceeded)`。对照测试使用独立资源身份，7 个播放器均正常暂停。

建议先做局部修正：暂停、结束的播放器不再占用待解码帧需求；缓存暂时不足时优先减少预取，避免将共享池调度不足广播为资源永久失败。真实数据损坏仍可作为共享解码源的失败。无需为此增加新的调度框架。

`ReviewReproductionTests` 已保留该复现，并用 `XCTExpectFailure` 标记期望的正常行为。修复后应移除此标记；该测试当前记录了已知缺陷，不能算功能验收通过。

### P2：默认共享池在错峰播放时明显变慢

位置：`Sources/FramePlay/PlaybackEnvironment.swift:215`，容量计算见第 228 行。

四个播放器的当前帧及后续帧需求被截断到整个资源共 6 帧；来源内解码又是串行的。同步播放能够有效复用，错峰播放则容易反复解码和等待。

两轮 Release 复测中，四图同步共享均约 3 秒一轮；每隔 350ms 启动一个播放器后，部分循环延长到 3.6–4.12 秒，最长持帧达 232–278ms。索引连续且没有 fallback，但不代表按原速度播放。默认 `.preserveFrames` 会等待，因此这种退化也不会显示为“跳帧”。

建议在完善共享需求管理前明确这一限制。小动画可先使用已有 API 配置完整帧缓存；大动画继续使用有界窗口，待不同播放位置的共享预取通过实测后再宣称其收益。不需要先增加预测、优先级树或第二套解码后端。

## Release 性能结果

环境：Xcode 27.0、iPhone 17 Pro / iOS 26.5 arm64 专用模拟器。真实 UIWindowScene 和 UIScrollView，160pt 图片，60Hz 滚动采样；每组测量 9 秒，随后 reset 并观测 1 秒。样本为包内 640×640、25 帧、120ms/帧的 WebP，预期完整循环为 3 秒。

CPU 为测试宿主整个进程的 CPU 时间除以墙钟时间，100% 表示占用一个核心；包含采样和 UI 开销。它不是整机占用比例或真机耗电。下表主要采用最后一轮，默认配置指解码并发 2、资源缓存 6 帧/8 MiB、环境 32 MiB。512px 为库的默认最大边。

| 场景 | CPU / 单核心 | 缓存峰值 MiB | 解码次数 | 每播放器输出帧数 | 循环时间 ms |
| --- | ---: | ---: | ---: | --- | --- |
| 四张静态首帧基线 | 6.3% | 0 | 0 | — | — |
| 单图 320px | 36.9% | 2.34 | 80 | 75 | 3000.1–3000.3 |
| 四图独立 320px | 131.0% | 9.38 | 320 | 74–75 | 约 3000 |
| 四图同步共享 320px | 40.7% | 2.34 | 80 | 75 | 2999.9–3000.4 |
| 四图错峰共享 320px | 91.8% | 2.34 | 264 | 57–73 | 3016.5–3732.4 |
| 四图独立，默认 512px | 133.5% | 24.00 | 320 | 75 | 约 3000 |
| 四图独立 640px | 132.7% | 31.25 | 316 | 75 | 约 3000 |
| 单图 320px，完整缓存 | 17.6% | 9.77 | 25 | 75 | 3000.0–3000.7 |
| 四图错峰共享 320px，完整缓存，单独补测 | 9.1% | 9.77 | 25 | 75 | 2998.8–3015.9 |

完整缓存使用现有配置：`maximumBufferedFrames: 25`、`bufferBytes: 12 * 1_024 * 1_024`，不修改解码器或播放器。最后一组准备阶段已执行 4×350ms 的错峰等待，更多首次解码发生在正式采样前；其 9.1% 不能直接当作相对单图 17.6% 的加速比。解码次数统计包含准备阶段，均为整个场景总量。

前一轮 Release 的静态基线为 1.9%、单图为 34.2%、独立四图为 131.2%、同步共享为 34.7%、错峰共享为 97.1%。错峰共享的输出为 54–70 帧/播放器，循环最高 4119.7ms。CPU 绝对值有环境波动，但共享播放位置错开后的退化在两轮均复现。

各组主线程显示回调 P95 为 16.7–17.8ms，最大约 18.1ms，未出现超过 33.34ms 的间隔；所有动画相邻帧索引连续。已通过图片读取工具检查错峰播放及完整缓存补测截图，四个图像正常绘制、位置不同。截图和回调记录并不能替代 GPU 实际呈现或真机评估。

测试宿主 RSS 峰值约 181–220 MiB，包含 UIKit、测试框架、图片工作区与分配器等，不能归因于库本身，也不能用 32 MiB 缓存上限代表进程内存。所有场景 reset 后资源与缓存计数为 0，等待解码任务退出后，随后 1 秒 CPU 时间约 0.004–0.009 秒，未观察到持续解码空转。未据此宣称无内存泄漏。

这次封装后 Release 测量中的四图 640px 能维持原速度；之前独立原型测试的 640px 停顿不能直接套用于当前模块。对这个样本，降低输出尺寸明显减少帧缓存，但没有明显降低四个独立资源的 CPU。因此不要只依据输出像素尺寸推断解码成本。

## 保持实现简单的建议

1. 保留现有 ImageIO、帧缓存、播放器、UIKit 薄视图的边界，不增加下载、磁盘缓存、SwiftUI、多后端和自动重试系统。
2. 先修共享池的失败传播及暂停需求，复用现有可控时钟测试。不要为了处理 7 个暂停位置重写整个调度层。
3. 帧数与字节预算继续显式配置。完整缓存能减少重复解码，但这里的 9.77 MiB 只适用于这个样本，不能无条件推广至任意动画；首版无需实现自动预测缓存策略。
4. 真机验证前，仅将上述结果标为模拟器样本测试；iOS 15 运行兼容性、透明增量帧/复杂 disposal、大尺寸高帧率动画和长期耗电仍未覆盖。本轮不扩展这些功能。

## 功能验证与复现

macOS 核心套件 28 项执行，独立 iOS Release 宿主功能套件 31 项执行，均无意外失败，各包含 1 项共享池已知缺陷的预期失败。性能测量独立启用，报告正常生成不表示所有采样场景都流畅。

```sh
swift test --package-path Packages/FramePlay

# 将 SIMULATOR_ID 设为当前空闲模拟器；请勿与其他工程共用正在测试的设备。
TEST_RUNNER_FRAMEPLAY_REVIEW_PERFORMANCE=1 xcodebuild test \
  -project Packages/FramePlay/Examples/iOSHarness/FramePlayHarness.xcodeproj \
  -scheme FramePlayHarness -configuration Release \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath Packages/FramePlay/.build/ReviewHarness \
  CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES \
  -parallel-testing-enabled NO \
  -only-testing:FramePlayHarnessTests/ReviewPerformanceTests/testPlaybackResourceMeasurements
```

初次运行前按 README 使用 XcodeGen 生成独立宿主。`ENABLE_TESTABILITY=YES` 供 `@testable` 测试读取内部解码器，不关闭 Release 的 `-O` 优化。可额外设置 `TEST_RUNNER_FRAMEPLAY_REVIEW_SCENARIO=shared-staggered-320-full-buffer` 单独复现补测。

本轮本地原始证据保存在 `.build/review/`，该目录被 Git 忽略：

- `core-final.log`：28 项核心测试，含明确的预期失败说明。
- `release-functional-final.xcresult` / 同名 `.log`：独立 iOS 功能验证。
- `release-performance-2.xcresult`：首轮完整 Release 测量，6 个场景。
- `release-performance-final.xcresult`：复测，8 个场景；逐帧、CPU、RSS、耗时及截图见 `release-attachments-final/`。
- `release-shared-full-buffer.xcresult`：完整缓存的错峰共享补测；原始数据及截图见 `release-shared-full-buffer-attachments/`。
- `summary-2.json`、`summary-final.json`、`summary-shared-full-buffer.json`：对原始事件的统计汇总。

P95 取排序后第 `ceil(0.95 × 数量)` 项；循环时间取同一播放器相邻索引 0 的时间差；跳帧按 25 帧循环的相邻索引检查。74/75 帧的小差异可能来自采样边界，错峰场景的 54–73 帧及循环延长则超出边界差异。

最初 Debug 采样被同一模拟器上的另一工程测试打断，另一次 Release 构建因未启用 testability 失败；两者均未计入性能结论。后续使用专用模拟器完成测量。本轮没有进行 App 集成或生产代码修复。
