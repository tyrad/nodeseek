# Multi Reply Quote Design

## Goal

支持在同一个回复编辑器中连续添加多个回复目标或多个引用目标，发送时一次性生成多个 mention 或 quote 块。

## Scope

- 保留现有单条回复、引用入口。
- 当回复编辑器已打开且当前模式也是回复时，再点另一条评论的“回复”会追加到回复目标。
- 当回复编辑器已打开且当前模式也是引用时，再点另一条评论的“引用”会追加到引用目标。
- 普通回复、回复模式、引用模式之间仍互斥；切换模式时使用新模式覆盖旧上下文。
- 清除上下文按钮一次清空全部回复或引用目标。

## Architecture

`CommentComposerMode` 从单个 `Comment` 扩展为多个 `Comment`。`CommentComposerContentBuilder` 负责把多个目标转换为最终提交文本：回复模式生成多个 mention 前缀并用空格连接；引用模式生成多个 Markdown quote block，并在 quote blocks 与用户正文之间保留空行。

`PostDetailViewController+Reply` 负责编辑器状态合并：同类型目标追加，不同类型目标覆盖。上下文栏显示紧凑摘要，例如 `回复 netcup #10、alice #11 等 3 条`，避免增加复杂的标签列表 UI。

## Data Flow

1. 用户点击评论或楼主的回复/引用按钮。
2. 详情页先确认登录状态。
3. 详情页根据当前 `replyComposerMode` 决定追加或覆盖目标。
4. 用户点击发送。
5. `CommentComposerContentBuilder.content` 根据目标数组生成最终提交文本。
6. 发送完成后沿用现有逻辑清空编辑器和上下文。

## Error Handling

- 空目标数组会按 `.plain` 行为处理，避免生成空上下文。
- 重复点击同一条评论不会重复追加，减少误触导致的重复 mention 或 quote。
- 目标楼层链接继续使用现有 anchor URL 规则。

## Testing

- `CommentComposerContentBuilderTests` 覆盖多回复和多引用输出格式。
- `PostDetailViewControllerTests` 覆盖编辑器打开后连续点击同类型动作会追加上下文，并验证发送内容包含多个目标。
- 运行 `swift test` 验证 SwiftPM core 测试；运行定向 Xcode 测试覆盖 UIKit 详情页行为。
