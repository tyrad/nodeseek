# NodeSeek Jump 链接跳转处理

## 背景

NodeSeek 详情页正文里会出现这类链接：

```text
https://www.nodeseek.com/jump?to=https%3A%2F%2Fshop.023168.xyz%2F
```

这类链接本质是站内 redirector，但点击后的内容属于外部页面。App 不应把它当作普通站内页面压入内部 `WKWebView`，也不应因为 `to` 指向 NodeSeek 帖子就转成原生详情页。

## 当前策略

- 直接外部链接：走 `SFSafariViewController`。
- 普通 NodeSeek 帖子链接：走原生详情页。
- 普通 NodeSeek 非帖子链接：走共享 Cookie 的内部 WebView。
- NodeSeek `/jump` 链接：解析 `to` 参数。
  - `to` 是合法 `http/https` URL 时，直接用解析出的目标 URL 打开 `SFSafariViewController`。
  - `to` 缺失、为空或不是 `http/https` 时，保底用原始 `/jump` URL 打开 `SFSafariViewController`。

这样可以避免外站进入内部 WebView，同时让 `SFSafariViewController` 承担外部页面承载边界。

## 覆盖测试

测试文件：

```text
nodeseekTests/Features/PostDetailViewControllerTests.swift
```

相关用例：

- `resolvesNodeSeekJumpLinksToDecodedSafariTarget`
  - 输入 `/jump?to=https%3A%2F%2Fshop.023168.xyz%2F`
  - 期望 `.safari(https://shop.023168.xyz/)`

- `resolvesNodeSeekJumpLinksToDecodedSafariTargetEvenWhenTargetIsNodeSeek`
  - 输入 `/jump?to=https%3A%2F%2Fwww.nodeseek.com%2Fpost-704174-1`
  - 期望 `.safari(https://www.nodeseek.com/post-704174-1)`
  - 不进入原生帖子详情

## 验证记录

项目所在卷 `/Volumes/meta` 曾出现空间不足，默认 `.build/XcodeDerivedData` 无法完整写入 `.xcresult`。验证时将 DerivedData 和测试结果临时放到 `/tmp`。

验证命令：

```bash
xcodebuild -quiet build-for-testing \
  -project "nodeseek.xcodeproj" \
  -scheme "nodeseek" \
  -configuration "Debug" \
  -destination "platform=iOS Simulator,id=F1FA4EFA-0399-438E-AC84-9326D32938E4" \
  -derivedDataPath "/tmp/nodeseek-dd" \
  -clonedSourcePackagesDirPath "/tmp/nodeseek-packages" \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1

xcodebuild -quiet test-without-building \
  -project "nodeseek.xcodeproj" \
  -scheme "nodeseek" \
  -configuration "Debug" \
  -destination "platform=iOS Simulator,id=F1FA4EFA-0399-438E-AC84-9326D32938E4" \
  -derivedDataPath "/tmp/nodeseek-dd" \
  -clonedSourcePackagesDirPath "/tmp/nodeseek-packages" \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:nodeseekTests/PostDetailViewControllerTests \
  -resultBundlePath /tmp/nodeseek-postdetail-green.xcresult
```

结果：

```text
PostDetailViewControllerTests: 48 passed, 0 failed
```
