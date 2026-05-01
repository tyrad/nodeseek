# 2026-05-01 账号刷新重构待测清单

对应提交：`a36fa34 refactor: clean up account refresh plumbing`

这次主要是结构清理，没有刻意改功能。真机回归重点放在账号状态、侧栏展示、详情渲染和隐藏 WebView 抓取是否仍然正常。

## 测试前准备

- 使用已登录过 NodeSeek 的真机环境，确认 Safari/WebView Cookie 里仍有登录态。
- 安装最新构建后冷启动 App。
- 如果要看账号调试日志，用 Debug 包打开侧栏里的“账号调试日志”区域。

## 账号侧栏

- [ ] 冷启动后打开左侧菜单，账号区域先显示缓存账号或游客态，不闪退。
- [ ] 侧栏打开后会触发账号刷新，调试日志里能看到 `ui: refresh requested`、`service: request`、`webview: cookies count`、`service: parsed` 或对应失败回退日志。
- [ ] 已登录状态下，侧栏显示用户名、头像、前三项 stats；头像能正常加载。
- [ ] 未登录或 Cookie 失效时，侧栏显示“未登录”和默认头像，不出现旧账号误展示。
- [ ] 重复快速打开/关闭侧栏，不会重复并发刷新；日志里应能看到 `task running` 或正常串行刷新。
- [ ] 点击未登录账号区域仍然能进入登录流程；已登录账号区域不可重复触发登录。
- [ ] Debug 下点击“复制日志”，剪贴板内容包含当前账号调试日志。

## 登录关闭后的账号刷新

- [ ] 打开登录 WebView 后关闭登录页，侧栏下一次打开会强制刷新账号状态。
- [ ] 如果侧栏已经打开，关闭登录页后能自动刷新当前侧栏账号区域。
- [ ] 强制刷新时不依赖 60 秒缓存，日志里 `force=true`。

## 详情页布局与渲染

- [ ] 打开帖子详情页，底部内容不被安全区额外留白，页面可以充分占用屏幕高度。
- [ ] 详情富文本、引用、图片、链接仍然能正常渲染和点击。
- [ ] 切换系统深色/浅色模式后，详情页富文本颜色能刷新，没有残留旧主题颜色。
- [ ] 打开带图片/表情/视频贴纸的帖子，内联附件布局不塌、不遮挡正文。

## WebView 抓取与隔离加载

- [ ] 首页列表仍可正常加载，Cloudflare 通过后的 Cookie 能被 WebView 请求使用。
- [ ] 账号刷新不会影响列表详情的共享 WebView 预热和加载。
- [ ] 多次触发账号刷新后，App 内存没有持续明显上涨；隐藏 WebView 不应因为 isolated loader 静态缓存而长期累积。
- [ ] 网络较慢或请求失败时，账号侧栏能回退到缓存或游客态，不阻塞 UI。

## 回归范围

- [ ] 首页列表翻页、分类、排序正常。
- [ ] 帖子详情分享菜单正常。
- [ ] 登录流程正常打开、关闭、回到主界面。
- [ ] 评论提交入口如果可用，确认页面加载和 Cookie 状态没有被这次 isolated loader 释放影响。

## 已完成的本地验证

- `swift test --filter KannaNodeSeekParserTests`：18 个通过。
- `swift test --filter CurrentAccountStoreTests`：3 个通过。
- `git diff --check`：通过。
- iOS Simulator build：通过。

备注：模拟器编译仍有一个既有 `NodeSeekSplashAnimator.swift` MainActor warning，不是这次改动新增。
