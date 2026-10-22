# 详情页动态 WebP 集成

分支：`feat/frameplay-webp-integration`，基线：`e3570d8`。

## 范围与数据流

首批接入帖子详情正文、评论的独立图片块和富文本图片附件。Xcode App target 引用本地 `Packages/FramePlay`，根 SwiftPM 测试入口保持原样。

加载仍经过 `ImageDataLoader`，复用请求头、原始文件缓存和请求合并。`DetailImageLoader` 在生成静态缩略图前，根据 Data 的 WebP 标记和 ImageIO 帧数识别动画，返回静态首帧、原图尺寸和可选的动画资源。保存、分享继续使用原始 Data。

视图保留现有 UIImageView、手势、长图裁剪和布局，新增的 `DetailAnimatedImageBinding` 将 FramePlay 帧回调写入 UIImageView。GIF、SVG、头像、表情选择器和大图预览继续使用既有路径。

## 实现约束

- 动画输出最大边 512px，每资源缓存预算 16 MiB，所有绑定复用 FramePlay 的 32 MiB 全局环境及最多两个后台解码任务。
- 同一规范化 URL 的在用视图复用 `DetailAnimatedImageAsset`。加载器只保存弱引用，动画结果不进入长期展示图缓存，避免压缩原图常驻。
- 显式 `.webp` 和 `data:image/webp` 请求先检查原图，再决定是否使用旧 JPEG 缩略图。静态 WebP 确认后可复用缩略图；其他静态图片保留既有缓存路径。新读取的原始 Data 即使扩展名错误，也可识别为动画。
- 磁盘命中的识别和首帧生成也在后台执行；回调线程不保证为主线程，视图统一回到主线程应用。
- 原始尺寸只在加载结果中通知一次，切帧不触发行高刷新。独立图片块布局时不再反复把首帧写回正在播放的视图。
- Texture 的 `didEnterVisibleState` / `didExitVisibleState` 控制播放；离开窗口或进入后台暂停，恢复前台后只恢复可见视图。富文本移除附件时 reset 并丢弃旧加载回调。
- 初始化失败、解码失败和缓冲超时沿用库的静态回退；极端长图仍按原展示规则使用静态图。

## 验证方式

核心测试：

```sh
swift test --package-path Packages/FramePlay
make xcode-build-tests
```

主项目专项测试使用 `DetailImageLoaderTests`、`DetailAnimatedImageIntegrationTests` 和 `PostDetailViewControllerTests`。新增覆盖旧 JPEG 缩略图迁移、静态 WebP、原始文件保持、在用资源共享与弱引用释放、尺寸通知、布局不覆盖动画、背景恢复、Texture 图片块及富文本附件的真实离屏/返回。

独立启用主项目性能采样（先设置空闲模拟器的 `SIMULATOR_ID`）：

```sh
TEST_RUNNER_FRAMEPLAY_INTEGRATION_PERFORMANCE=1 xcodebuild test \
  -project nodeseek.xcodeproj -scheme nodeseek \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath .build/XcodeDerivedData \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
  -collect-test-diagnostics never \
  -only-testing:nodeseekTests/DetailAnimatedImageIntegrationTests/testTexturePlaybackMeasurements
```

采样在主 App 宿主的真实 ASTableNode 中显示四个图片块，使用本地 640×640、25 帧、120ms/帧的 WebP，160pt 显示尺寸，解码目标为 480px。准备完成并预热 2 秒后自动滚动采样 9 秒，记录图像变化、循环、60Hz 回调、共享缓存及整个测试宿主进程的 CPU。像素散列只在图像变化时计算，采样自身也有开销。最后滚动到远处，验证 Texture 可见状态使播放暂停。

## 本次测量

功能与构建结果：

- `swift test --package-path Packages/FramePlay`：32 项通过，无预期失败。
- `make xcode-build-tests`：App 和测试 target 编译通过；Xcode 工程格式检查、`git diff --check` 通过。
- 主项目最终专项：150 项通过、0 失败，1 项性能用例按默认配置跳过；参数化用例展开后为 153 次通过。
- 性能用例单独启用：两次通过。Texture 图片块及富文本附件的图像持续变化、离屏暂停、返回恢复均有断言；最终截图已查看，两个 160pt 图片正常显示。
- 新增 Texture 测试最初未禁用富文本节点的 `flexGrow`，组合运行时出现宽度异常及等待播放超时；测试场景固定宽度并等待附件重排后，最终组合回归通过。此项只修改测试约束，没有更改通用富文本布局。

Xcode 27.0，专用 iPhone 17 Pro / iOS 26.5 arm64 模拟器，**主项目 Debug 构建**。以下 CPU 为整个 App 测试宿主的单核心占用百分比，包含应用启动后的其他工作和采样开销，不代表播放器独占 CPU。两轮均为四图同步共享同一原始资源，采样 9 秒。

| 指标 | 首轮，无显式预热 | 预热 2 秒后复测 |
| --- | ---: | ---: |
| CPU / 单核心 | 46.6% | 71.4% |
| 帧缓存峰值 | 5.27 MiB | 5.27 MiB |
| 共享解码资源数 | 1 | 1 |
| 每图画面变化次数 | 75 | 75 |
| 循环间隔 | 3000.1–3007.9ms | 2996.4–3000.1ms |
| 60Hz 回调 P95 | 17.2ms | 17.2ms |
| 最长回调间隔 | 157.5ms | 87.0ms |
| 超过 33.34ms 的间隔数 | 3 | 4 |

样本在 App 中保持约 3 秒一轮，四图复用一个解码资源；两轮 CPU 波动较大，且均出现长回调，不能据此认定播放成本很低或完全无卡顿。该采样没有隔离 App 自身的网络、解析及其他启动工作，也没有静态对照组，因此不把长回调归因于某一模块。独立库的 Release 对照、错峰共享及不同尺寸结果见 [FramePlay 验证记录](../Packages/FramePlay/VALIDATION.md)。

原始本地证据（`.build/` 被 Git 忽略）：

- `.build/FramePlayIntegration-functional-complete.xcresult`：最终专项 150 项通过，含 Texture 截图及附件几何记录。
- `.build/FramePlayIntegration-performance-1.xcresult`：首轮性能数据及四图截图。
- `.build/FramePlayIntegration-performance-warm.xcresult`：预热性能数据及截图；用例通过后模拟器诊断收集卡住，结束该诊断进程后结果正常保存。后续测试关闭详细诊断收集。
- `.build/FramePlayIntegration-baseline-magic.xcresult`：原始 `e3570d8` 基线上复现两项 MagicTab 既有布局断言失败。

MagicTab 扩展回归发现两项原有失败：`testTCPQualityFixtureKeepsFiveFullLengthImagesInOneGallery` 与 `testThirdAndFourthTabImagesKeepFullHeightAfterThumbnailLoads`，涉及长图 contentMode、行高和小数舍入预期。未集成 FramePlay 的独立基线工作树中两项同样失败，本轮保留失败记录，不修改无关布局逻辑或断言。

## 限制

模拟器回调和截图不能替代 GPU 实际呈现、真机耗电或长时间发热验证。字节预算只覆盖帧缓存，不是进程总内存。详情页尚未接入大图预览的动画播放。

测试宿主还记录了一条 QoS 等待的运行时警告，未据此作消除优先级反转的结论；构建仍有既有 Texture 头文件、主线程隔离和 XCTest 部署版本警告。

历史缓存中若某非 WebP 扩展名 URL 只有 JPEG 缩略图、没有重新读取原始 Data，仍可能先按旧静态缓存显示；本轮不为所有旧静态缩略图强制重新下载原图。
