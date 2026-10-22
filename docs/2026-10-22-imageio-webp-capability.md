# ImageIO 动画 WebP 能力实测

## 范围与环境

- 测试：`nodeseekTests/AppRuntime/ImageIOWebPCapabilityTests.swift`。
- 样本：`nodeseekTests/Fixtures/post-881951-animated.webp`，746,146 bytes。
- 来源：[帖子](https://www.nodeseek.com/post-881951-1)、[原图](https://cdn.nodeimage.com/i/WS2rftGPk8LhRyJ3wH4nHEgRDqU67Hhq.webp)。
- WebP 容器基准：640×640，25 个 ANMF，每帧 120 ms，总时长 3 秒，ANIM 循环次数为 0（无限循环）。
- 环境：iPhone 17 Pro 模拟器，iOS 26.5（23F77），arm64。
- 测试离线运行，不调用业务图片加载器，不新增第三方依赖，不改变业务流程。

## 结果

5 项测试全部通过，0 失败、0 跳过。

| 检查项 | 实测结果 |
| --- | --- |
| 格式识别 | `org.webmproject.webp` |
| 动画元数据 | 25 帧、640×640、每帧 0.12 秒、总时长 3 秒、循环值 0；容器与各帧的时长一致 |
| 完整帧解码 | 25 帧全部成功，均为完整 640×640 画布；标准化 RGBA 后得到 25 种不同哈希 |
| 乱序读取 | 新 source 按 24、0、12、1、23 读取，与顺序解码对应帧的像素哈希一致 |
| 逐帧缩小解码 | `CGImageSourceCreateThumbnailAtIndex` 可生成全部 25 帧的 320×320 图像，得到 25 种不同哈希 |
| 系统动画回调 | `CGAnimateImageDataWithBlock` 返回 0；主线程按 0…24 回调；末帧设置 `stop` 后，随后 0.3 秒未再回调 |
| UIKit 普通初始化 | `UIImage(data:)` 返回 640×640 静图，`images == nil`、`duration == 0` |

测试结果中保留了首帧、中间帧、末帧 PNG 附件，已目视检查画面变化。

## 首轮能力测试中的性能观察

后续已补充独立的解码与界面测量，详见 [性能与播放时序实测](2026-10-22-imageio-webp-performance.md)。以下保留能力测试本身的观测，不能代替后续基准。

本次完整帧解码、RGBA 哈希及 PNG 附件合计约 0.94 秒；逐帧缩略图解码和 RGBA 哈希合计约 0.94 秒。这些数值包含测试开销，并非纯解码基准。

系统动画回调首帧至末帧实测约 3.93 秒，高于按原始间隔计算的 2.88 秒（24 个间隔）。因此本次只确认动画回调和停止能力，不能据此认定系统接口能在实际界面中精确计时、流畅播放。测试不对墙钟时间设置断言，以免模拟器负载造成不稳定失败。

对这张图，ImageIO 已具备获取帧、时序、循环及缩小解码的能力，后续可以探索使用系统能力接入动画展示。`UIImage(data:)` 本身不会生成动画，现有静态缩略图路径仍需分流。此次没有验证其他 WebP 样本的透明混合、不同帧间隔、旧版 iOS、真机性能或滚动中的资源占用。

## 复现

```sh
make xcode-test-class TEST=ImageIOWebPCapabilityTests SIMULATOR_ID=61FBBFA6-0161-4C3D-9E1D-84C5C6962643
```

在其他机器上将 `SIMULATOR_ID` 替换为可用模拟器的标识。Xcode 的测试结果包含图像附件与观测文本。
