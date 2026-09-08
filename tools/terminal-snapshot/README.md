# 终端异步截图验证

验证目标：用帖子 `https://www.nodeseek.com/post-916971-1` 的前两个分栏，检查“完整 ANSI → 本地 WebKit 渲染 → PNG”是否可行。本目录是独立验证工具，没有接入 NodeSeek App，也没有修改现有 tab 展开或不支持提示的行为。

## 样本与实现

- 样本来自帖内 NodeQuality 报告页的“复制为 NodeSeek 格式”导出。`post-916971.json` 保存两个完整 ANSI 分栏，各 49 行，保留颜色、背景、粗体、下划线及退格符。
- 原帖后两个分栏本身就是图片，正式接入时可直接复用图片加载，不需要再次截图。本工具没有把导出时重新生成的图片 URL 写入 App。
- 固定 `@xterm/xterm` 5.5.0，离线载入其 JS/CSS；不加载原站整页，不执行报告里的文本或链接。依赖使用 MIT 许可证，可在安装后的包目录查看许可证。
- 从 50 行的终端开始，等待 `write` 完成，读取完整 buffer，然后扩展终端自身的行数、滚到顶部、等待 `onRender` 和布局帧。对比扩展前后的逐行文本，再进行 WKWebView 截图。
- 固定 100 列、14px 等宽字体和终端配色，生成 2 倍像素图片。深浅模式只改变宿主的 UIKit traits，报告本身保留配色。
- 当前限制：1000 行、2 倍图片最多 2400 万像素、30 秒超时。超限报错；没有实现分段截图。

## 复现

在仓库根目录安装验证依赖：

```bash
npm ci --prefix tools/terminal-snapshot --ignore-scripts --no-audit --no-fund
```

macOS 验证：

```bash
node tools/terminal-snapshot/prepare.mjs .build/terminal-snapshot
swiftc -parse-as-library tools/terminal-snapshot/Snapshot.swift -o .build/terminal-snapshot/snapshot
swiftc tools/terminal-snapshot/VerifyImages.swift -o .build/terminal-snapshot/verify-images
for report in basic ip long-report controls; do
  .build/terminal-snapshot/snapshot ".build/terminal-snapshot/$report.html" ".build/terminal-snapshot/$report.png"
done
node tools/terminal-snapshot/verify.mjs .build/terminal-snapshot
.build/terminal-snapshot/verify-images .build/terminal-snapshot
```

iOS 验证需要一个已启动的模拟器。通过 `xcrun simctl list devices available` 选择已有设备，只启动一次，然后运行：

```bash
bash tools/terminal-snapshot/run-ios.sh SIMULATOR_UDID
```

脚本编译并安装独立的 `com.nodeseek.TerminalSnapshotProbe`，按顺序在 light/dark 下执行四个样本。每轮使用唯一输出目录，避免读取旧结果。不会覆盖 NodeSeek App；结束后终止验证 App，保留模拟器和验证安装。

输出位于 `.build/terminal-snapshot/ios/light/` 和 `dark/`。每份报告包括 PNG、逐行文本、DOM 样式、截图尺寸和耗时 JSON。生成的 HTML 和图片均在忽略目录中。

## 验证结果

环境：Xcode 26.5、iPhone 17 Pro 模拟器、iOS 26.5。macOS 和 iOS 都执行了真实 WKWebView 截图；没有真机性能结论。

| 样本 | 行数 | iOS PNG 像素 | PNG 大小（约） | 最后一轮耗时 light / dark |
| --- | --- | --- | --- | --- |
| 基本信息 | 49 | 1750 × 2122 | 605 KiB | 1037 / 946 ms |
| IP 质量 | 49 | 1750 × 2122 | 521 KiB | 964 / 963 ms |
| 长报告 | 160 | 1750 × 6784 | 1214 KiB | 1190 / 1126 ms |
| 控制字符 | 7 | 1750 × 358 | 45 KiB | 915 / 1113 ms |

这些是本次单次观测，包含 WebView 加载、渲染、截图和 PNG 编码，不含外部网络请求。首次模拟器启动后的首张曾耗时约 12.9 秒，不能把后一轮约 1 秒作为首屏承诺。

检查项：

1. 所有输入逐行比对，扩展前后文本一致；160 行样本实际产生 scrollback，最终第 160 行完整。
2. 验证红色前景、绿色背景、粗体、下划线、真彩色、256 色和退格覆盖。HTML 标签在报告中保留为文字。
3. 校验最终 PNG 像素尺寸；使用 Vision 从位图末尾识别报告链接、`ROW-160` 等标记，确认真正截到了末尾。
4. 人工检查真实报告 PNG 的颜色、中文排版、条形图、链接和底部完整性。
5. iOS light/dark 各四个样本全部通过。

实际发现并解决的问题：UIKit 默认的 `contentInsetAdjustmentBehavior` 会给 WebView 加入安全区顶部留白，使固定高度截图漏掉底部，尽管 DOM 行数完全正确。旧图在位图尾部 OCR 检查中失败；设置 `.never` 和零 inset 后重新生成，检查通过。

## 正式接入前的边界

本轮验证证明了“持有完整 ANSI 原文时，本地异步生成完整彩色图片”可行，没有证明任意已渲染 xterm DOM 都能恢复原文。

- 生产加载需要从 HTTP 原文提取并保留 ANSI；WebView 回退路径若只有终端 DOM，应保留可靠的完整原文入口，否则继续提示网页查看，不能拿当前可见行冒充完整报告。本次原文通过报告页手动导出，不是新增的自动获取服务。
- tab 应在原有展开步骤之前转成结构化分栏数据；图片栏复用现有图片组件，终端栏走独立串行渲染队列。
- 原生 tab、按需调度、取消、失败重试、稳定高度、缩放、复制原文、磁盘及内存缓存尚未实现。
- 缓存应包含完整内容摘要、列宽/字号、配色和渲染器版本。当前固定报告配色可以跨深浅模式共享图片。
- 每张真实报告解码约 14.2 MiB，160 行样本约 45.3 MiB；长报告进入生产前需要分段和像素预算，不能只按压缩文件大小估算内存。
- 当前是有渲染宿主的 WebView。iOS 后台、完全隐藏/离屏宿主、不同系统版本、超长/超宽报告和真机内存仍需验证。

参考：[WKSnapshotConfiguration](https://developer.apple.com/documentation/webkit/wksnapshotconfiguration)、[xterm Terminal API](https://xtermjs.org/docs/api/terminal/classes/terminal/)。
