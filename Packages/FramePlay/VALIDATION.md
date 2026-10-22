# FramePlay 修正与验证记录

本文为独立库阶段的测试记录；后续主项目接入范围与结果见[集成记录](../../docs/2026-10-22-frameplay-integration.md)。

日期：2026-10-22。本轮核实 [审核记录](REVIEW.md) 中的问题并局部优化，未集成 NodeSeek App。原审核保留为修正前的证据；本文描述当前实现。

## 核实与修正

1. **七个暂停位置连带回退：已复现并修复。** 补强逐帧断言后，原实现稳定让七个播放器全部进入资源限制回退。暂停、停止和结束后现在撤销解码需求，当前显示帧仍由播放器持有。容量竞争时优先交付待显示帧，不再将暂时的共享池拥挤标记为整个源的永久失败。
2. **错峰共享变慢：已复现并优化。** 仅改变请求优先级仍有约 4.1 秒的循环，因此改为合并各活动播放位置的预取窗口。同步位置复用窗口；不同位置可以多保留帧，仍严格遵守资源和环境字节预算。320px 四图错峰恢复约 3 秒一轮。
3. **窗口移动时重复解码：补测发现并修复。** 解码完成前，多个位置可能从不同锚点重新对齐；旧缓存尚未清理时插入新帧，LRU 会误淘汰下一张显示帧。现在先移除过期项再插入，确定性复现中下一帧的解码次数由 2 次恢复为 1 次，同步共享的额外解码也已消除。

`maximumBufferedFrames` 明确为每个活动播放位置的预取窗口（默认 6），共享池合并窗口。四个相差 3 帧的位置会形成 15 帧窗口。**这调整了共享时的帧数配置语义；单播放器行为不变，字节预算没有提高。** 默认每资源 8 MiB、环境 32 MiB。预算装不下合并窗口时缩短预取，仍可能因重复解码变慢；不会自动扩张字节预算。

生产源码从审核时约 1,058 行增至 1,071 行，仍为七个文件。改动集中于播放器的需求交接、共享池窗口及缓存插入限制，没有增加依赖或解码后端。

## 功能与构建

| 验证 | 结果 |
| --- | --- |
| macOS `swift test --package-path Packages/FramePlay` | 32 项通过，无预期失败 |
| macOS `swift build -c release --package-path Packages/FramePlay` | 通过 |
| 独立 iOS Release 宿主功能测试 | 35 项通过，两个独立性能用例默认跳过，无预期失败 |
| 独立 iOS Release 性能采样 | 10 个场景通过，另补测 512px / 16 MiB 场景通过 |

共享回归用例覆盖七个不同暂停位置、暂停后无预取及继续播放、七个待显示请求竞争一帧缓存、全局预算释放后继续准备、错峰窗口复用以及解码期间窗口前移。错峰确定性测试中，四个播放器各推进 8 帧，只需新增解码 8 帧，而非重复解码 32 帧。原有格式、循环、透明度、回退、超时、取消、重入和 UIKit 生命周期测试继续通过。

## Release 性能结果

环境：macOS 27.0 / Xcode 27.0，专用 iPhone 17 Pro / iOS 26.5 arm64 模拟器。真实 UIWindowScene 内自动滚动 UIScrollView，每张图片 160pt。样本为用户提供的 640×640 WebP，746,146 bytes、25 帧、每帧 120ms、完整循环 3 秒。各场景采样 9 秒，之后 reset 并观测 1 秒；错峰场景每隔 350ms 启动一个播放器。

CPU 是测试宿主整个进程的 CPU 时间除以墙钟时间，100% 表示占用一个核心，包含 UI 和采样开销。解码次数包含准备阶段；CPU 仅统计采样阶段。以下为清理过期缓存修正后的最终完整一轮，512px / 16 MiB 是随后单独补测。

| 场景 | CPU / 单核心 | 缓存峰值 MiB | 解码次数 | 每播放器输出帧数 | 循环时间 ms |
| --- | ---: | ---: | ---: | --- | --- |
| 四张静态图基线 | 6.2% | 0 | 0 | — | — |
| 单图 320px | 40.1% | 2.34 | 81 | 75 | 2999.9–3000.1 |
| 四图独立 320px | 133.7% | 9.38 | 324 | 75 | 3000.0–3000.1 |
| 四图同步共享 320px | 40.5% | 2.34 | 81 | 75 | 2999.9–3000.0 |
| 四图错峰共享 320px | 40.2% | 5.86 | 102 | 75 | 3000.0–3000.1 |
| 四图错峰共享 512px，默认 8 MiB | 101.8% | 8.00 | 279 | 56–71 | **3070.0–4381.7** |
| 四图错峰共享 512px，显式 16 MiB | 41.2% | 15.00 | 102 | 75 | 2999.9–3000.0 |
| 四图独立 512px | 135.6% | 24.00 | 324 | 75 | 3000.0 |
| 四图独立 640px | 132.8% | 31.25 | 320 | 75 | 3000.0 |
| 单图 320px，完整缓存 | 15.7% | 9.77 | 25 | 75 | 3000.0 |
| 四图错峰共享 320px，完整缓存 | 7.8% | 9.77 | 25 | 75 | 2999.1–3000.3 |

修正前审核的 320px 错峰共享约占 92–97% 单核心 CPU，部分循环 3.6–4.12 秒。当前恢复原速，代价是缓存从 2.34 MiB 增至 5.86 MiB；共享预算仍为 8 MiB。只调整请求优先级的中间版本没有解决错峰退化，已被后续窗口合并修正替代。

**默认 512px / 8 MiB 的错峰播放仍会变慢，不能宣称所有默认配置都流畅。** 该预算只容纳 8 张 512px RGBA 帧，无法容纳此场景约 15 帧的合并窗口。宿主显式配置 `bufferBytes: 16 * 1_024 * 1_024` 后，本样本恢复原速；这是一项内存与解码成本的取舍。库保留 8 MiB 默认值，不为这个样本提高所有图片的默认预算。

完整缓存使用 `maximumBufferedFrames: 25`、`bufferBytes: 12 * 1_024 * 1_024`。错峰完整缓存的准备阶段已执行更多初始解码，其 7.8% 不能直接和单图 15.7% 作加速比。此配置仅适用于该尺寸与帧数，不能推广至任意动画。

最终各场景滚动回调 P95 约 16.7–17.3ms，没有超过 33.34ms 的回调间隔。所有动画帧索引连续，没有 fallback。512px 小预算场景最长持帧约 281ms，说明主线程回调稳定与动画按时播放是两件事。其余流畅场景最长持帧约 134ms，120ms 帧延时在 60Hz 调度下会量化到不同间隔。已查看最终 320px、512px 错峰及预算补测的截图，图像正常绘制。

测试宿主 RSS 峰值约 181–217 MiB，包含测试框架、UIKit、ImageIO 工作区及分配器等，不能归因于库本身；帧缓存字节数不是进程总内存。reset 后资源与缓存计数均为 0，解码任务结束后继续观测 1 秒，没有持续解码空转的迹象。这不能代替泄漏检测。

## 复现与证据

功能及独立宿主的生成方法见 [README](README.md#测试)。审核采样使用 Release，需设置 `ENABLE_TESTABILITY=YES` 读取内部解码器；不会关闭优化。

```sh
# 先将 SIMULATOR_ID 设为空闲的专用模拟器 ID。
TEST_RUNNER_FRAMEPLAY_REVIEW_PERFORMANCE=1 xcodebuild test \
  -project Packages/FramePlay/Examples/iOSHarness/FramePlayHarness.xcodeproj \
  -scheme FramePlayHarness -configuration Release \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath Packages/FramePlay/.build/ReviewHarness \
  CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES \
  -parallel-testing-enabled NO \
  -only-testing:FramePlayHarnessTests/ReviewPerformanceTests/testPlaybackResourceMeasurements
```

可额外设置 `TEST_RUNNER_FRAMEPLAY_REVIEW_SCENARIO=shared-staggered-default-512` 只测默认尺寸错峰；再加 `TEST_RUNNER_FRAMEPLAY_REVIEW_BUFFER_MIB=16` 复现显式预算补测。性能用例是采样工具，运行通过不等于每个场景都达到原速，需要分析帧事件和循环时间。

本地证据位于被 Git 忽略的 `.build/review/`：

- `fix-core-verified.log`、`fix-release.log`：核心测试与 Release 构建。
- `fix-functional-verified.xcresult`：当前 35 项 iOS 功能测试。
- `fix-performance-verified.xcresult`、`fix-attachments-verified/`、`fix-summary-verified.json`：最终完整一轮原始事件、CPU、RSS、截图及汇总。
- `fix-512-budget-16.xcresult`、同名 `-attachments/` 和 `-summary.json`：默认尺寸增加预算的独立补测。

通过 `xcrun xcresulttool export attachments --path <结果包> --output-path <目录>` 导出附件。P95 取排序后第 `ceil(0.95 × 样本数)` 项；循环间隔取同一播放器相邻索引 0 的时间差；跳帧按 25 帧循环的相邻索引检查。

## 验证边界

以上是本地样本和模拟器结果。回调加截图不能精确等同于 GPU 实际呈现帧率。尚未验证真机 CPU、耗电、发热、长时间播放、复杂透明增量帧/disposal、大尺寸高帧率动画及旧系统实际运行。iOS 15 为声明的最低版本，本轮运行系统为 iOS 26.5。库继续保持独立，尚未集成主项目。
