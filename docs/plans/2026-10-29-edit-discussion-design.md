# 编辑已发帖子

设计稿：`docs/assets/2026-10-29-edit-discussion-ui.png`

## 网页版行为（2026-10-29 用 opencli 看 post-1016685 确认）

- 入口：主楼操作行「编辑」，只有 `logined && isMe` 时显示。
- 可改：标题、正文、阅读限制；板块不能改。
- 原文：页面 `__config__.postData.comments[i].markdown`（主楼 `floorIndex == 0`），标题 `postData.title`，阅读限制 `postData.rank`。
- 本人判断：`postData.op.uid == __config__.user.member_id`（任意页都有）；主楼 `poster.isMe` 只在第一页有。
- 保存：`POST /api/content/edit-discussion`，JSON `{content, mode: "edit-discussion", title, postId, rank}`，头部带前端随机 16 位 `csrf-token`。
- 规则：标题不能为空；原来不是私有、改成私有时确认“公开帖子设为私有需要收取10鸡腿手续费”。
- 网页草稿按 postId 存，保存成功后删除；成功后刷新页面定位到主楼。

## 方案

- 复用原生发帖模块，加 `NewDiscussionMode.edit(EditableDiscussion)`：
  - 打开前在隐藏 WebView 里加载 `/post-<id>-1`，读原文、标题、阅读限制、板块和是否本人。
  - 右上按钮「保存」，只有标题、正文、阅读限制和原文不同才可点。
  - 草稿按帖子单独存（`com.nodeseek.edit-discussion-draft.<postId>`），只在有改动时写入；再次编辑同一帖子时作为「上次没保存的修改」可恢复。
  - 设置面板标题「帖子设置」，板块只显示当前板块并说明不能修改。
  - 关闭：没改动直接关；有改动给「保存修改 / 留着下次继续 / 放弃修改」。
  - 保存超时显示「保存结果未知」，允许重试（重复提交同样内容无副作用）。
- 详情页：
  - 解析 `isOwnPost`；主楼操作行加「编辑」，「更多」菜单加「编辑帖子」。
  - 保存成功后刷新回到主楼，提示「已保存修改」。
- 编辑自己的回复（`edit-comment`）下一步再做。
