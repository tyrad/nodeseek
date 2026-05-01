# Xterm Unsupported Content Manual Test

## 测试目标

验证帖子详情中遇到 xterm 终端渲染内容时，App 不再展示终端 DOM 文本，而是显示：

`不支持显示此内容，请前往网页查看。`

文案后应带有 Safari 图标。其它非 xterm 的 magic tab 内容仍应正常展示。

## 测试环境

- 分支：`feature/xterm-unsupported-content-dev`
- Worktree：`.worktrees/xterm-unsupported-content-dev`
- 目标页面：包含 `nsk-magic-tabs` 且其中 tab body 包含 `xterm-rows` 或 `terminal-container` + `xterm` class 的帖子详情页。

## 操作步骤

1. 在 Xcode 或本地脚本中运行当前分支的 App。
2. 打开一个包含 xterm 终端输出的 NodeSeek 帖子详情。
3. 找到原本应展示终端输出的 magic tab 内容区。
4. 检查该内容区是否显示：
   `不支持显示此内容，请前往网页查看。`
5. 检查文案后是否出现 Safari 图标。
6. 检查该内容区中不应出现终端输出正文，例如硬件质量报告、IP 质量报告、终端样式 class、隐藏 textarea 文本等。
7. 继续查看同一组 magic tabs 的其它 tab。
8. 如果后续 tab 是图片内容，确认图片仍能正常显示和点击预览。
9. 打开一个只包含普通代码块或 ANSI code block、但不包含 xterm DOM 的帖子，确认代码块仍能正常展示。

## 通过标准

- xterm 终端 body 被整块替换为不支持提示。
- 提示文案为 `不支持显示此内容，请前往网页查看。`。
- 提示文案后显示 Safari 图标。
- xterm 内部 DOM 文本、CSS class、textarea helper 不出现在详情页。
- 同一帖子中的后续图片 tab 正常展示。
- 非 xterm 的普通代码块和 ANSI code block 不受影响。

## 注意事项

- 当前改动只负责展示提示，不负责点击跳转网页。
- 如果页面本身没有 xterm DOM，只是普通 `<pre><code>`，不应触发该提示。
