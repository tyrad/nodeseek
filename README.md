# NodeSeek iOS

[![TestFlight](https://github.com/tyrad/nodeseek/actions/workflows/testflight.yml/badge.svg)](https://github.com/tyrad/nodeseek/actions/workflows/testflight.yml)
![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-15%2B-000000?logo=apple&logoColor=white)
![License](https://img.shields.io/github/license/tyrad/nodeseek)

NodeSeek iOS 是一个非官方三方 iOS 客户端，使用 UIKit 构建，通过 HTML/XPath 解析提供原生浏览、帖子详情、登录态复用、回复、图片查看和 NodeImage 图片上传等能力。

本项目不隶属于 NodeSeek，也不代表 NodeSeek 官方。用户登录、授权和内容访问均发生在用户自己的 NodeSeek / NodeImage 账号上下文中。

## 功能

- 浏览 NodeSeek 主题列表、帖子详情和评论。
- 通过 WebView 登录，并在 WebView 与原生请求之间同步用户授权的 Cookie。
- 支持回复、引用、表情和 NodeImage 图片上传。
- 支持图片预览、保存和分享。
- 包含 SwiftPM 逻辑测试和 Xcode app-hosted 测试。

## 环境要求

- macOS + Xcode 26 或兼容版本。
- iOS 15+。
- Ruby/Bundler 用于 fastlane 发布流程。

## 构建与测试

打开主工程：

```bash
open nodeseek.xcodeproj
```

运行纯逻辑测试：

```bash
make spm-test
```

构建 Xcode 测试产物：

```bash
make xcode-build-tests
```

运行指定 XCTest 类：

```bash
make xcode-test-class TEST=NodeSeekServiceTests
```

完整 App 单测：

```bash
make xcode-test-full
```

如本机模拟器 ID 不一致，可覆盖 `SIMULATOR_ID`：

```bash
make xcode-test-class TEST=NodeSeekServiceTests SIMULATOR_ID=<simulator-udid>
```

## 隐私与安全

应用不在源码仓库中保存用户 Cookie、NodeSeek 凭据或 NodeImage API Key。运行时授权信息保存在系统 Cookie/Keychain 等本机存储中，退出登录会清除本机 NodeImage 授权。

如果你发现安全问题，请不要在公开 issue 中贴出账号、Cookie、API Key 或其它敏感信息。

## 许可证

本项目使用 MIT License，见 [LICENSE](LICENSE)。

## 截图

<p>
  <img src="screenshots/1.jpg" width="250" />
  <img src="screenshots/3.jpg" width="250" />
  <img src="screenshots/2.jpg" width="250" />
</p>
