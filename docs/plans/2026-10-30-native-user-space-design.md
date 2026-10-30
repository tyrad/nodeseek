# 原生个人页

设计稿：`docs/assets/2026-10-30-native-user-space-ui.png`（第六版定稿；中间几版花哨 / 偏灰的方案已否决）

## 现状

- 所有 `/space/<uid>` 入口都打开 `UserInfoWebViewController`（隐藏站点 header 的 WebView）：帖子详情作者、评论作者头像预览、通知列表、侧边栏自己的主页、推送深链。
- 侧边栏已有原生「我的帖子 / 我的评论 / 我的收藏」（`Features/UserContent/`），uid 固定取当前账号。
- 签到页也借用 `UserInfoWebViewController`（`boardURL`），与个人页无关，不动。

## 网页版数据（2026-10-30 用 opencli 确认）

- 资料：`GET /api/account/getInfo/<uid>?readme=1`
  ```json
  {"success":true,"detail":{"member_id":1,"member_name":"Lloyd","isAdmin":1,"rank":6,
   "coin":8282,"stardust":21,"bio":"本论坛的创建者","created_at":"2022-11-23T17:11:12.000Z",
   "nPost":26,"nComment":90,"follows":0,"fans":77,"readme":"…","created_at_str":"1436days ago",
   "roles":[{"name":"creater","display_text":"服主"},{"name":"admin","display_text":"管理"}],
   "followed":false}}
  ```
  看自己时多 `collectionCount`；没写过的用户 `bio`、`readme` 为 `null`（网页显示「没有找到readme 🙄」）。
- 今日进度（只对当前登录用户有效）：
  - `GET /api/progress/today` → `{postBonusCount, maxPostBonusCount, commentBonusCount, maxCommentBonusCount, freeLikeUsed, maxFreeLike}`
  - `GET /api/attendance/board?page=1` 的 `record` → 今日签到 `{gain, ...}`，`null` 表示未签到。
  - 网页进度算法：发帖 `5 × postBonusCount / 5 × maxPostBonusCount`；评论 `commentBonusCount / maxCommentBonusCount`；签到 `gain / gain`（未签到 `0 / 20`）；免费投喂 `freeLikeUsed / maxFreeLike`。
  - 等级：门槛 `level² × 100`，当前值为鸡腿 `coin`；网页取 `min(rank, 5)`，App 对 Lv6 及以上显示「已满级」。
- 首页个人卡片链接：等级 `/progress`、鸡腿 `/credit`、星辰 `/stardust/list?member_id=<uid>`、粉丝 `/fans?type=fans`、关注 `/fans?type=follow`、收藏 `/space/<uid>#collections`。
- 私信：`/notification#/message?mode=talk&to=<uid>`。

## 页面

- 黑白高对比：主要信息 `.label`，辅助 `.secondaryLabel`；系统分组背景 + 卡片（圆角 14）；无渐变、无阴影、无彩色图标。
- 头部：头像 72pt 圆角 16 在左；名字 24pt 粗体 + `.label` 描边角色徽章；bio、`UID · 加入 N 天` 灰字。看别人时名字右侧依次是「关注 / 已关注」按钮（与关注列表同款，点已关注先确认再取消，成功后粉丝数就地 ±1，结果用底部 toast）和灰底小胶囊「私信」；`getInfo` 的 `followed` 决定初始状态。
- 数字：看别人四格「等级 / 鸡腿 / 星辰 / 粉丝」；看自己五格，多「关注」。居中 20pt 粗体等宽数字 + 12pt 灰标签。
  - 可点：星辰（都可点）、粉丝 / 关注（仅自己），先开网页。
  - 等级 → 进度页、鸡腿 → 鸡腿明细：**后续做原生**，本期不可点。
- 今日进度（仅自己）：「距 Lv N+1 还差 X 鸡腿」+ `coin / 门槛` + 进度条；签到 / 发帖 / 评论 / 免费投喂四行。只有进度条用颜色：等级 indigo、签到 orange、发帖 blue、评论 teal、投喂 pink（系统色），轨道 `.systemFill`。接口失败时只隐藏这张卡片。
- 内容：主题帖 / 评论（看自己为「我的帖子 / 我的评论 / 我的收藏」），push 现有原生列表并传入 uid。
- 自述：Markdown 转站点同款 HTML 后走详情页 DTCoreText 渲染，用 UIKit 排版（文字、列表、链接、代码块、图片）；为空时整块不显示。站内帖子链接走原生详情。
- 「···」：网页版主页、复制主页链接。
- 首次加载显示骨架（头部、数字卡片、列表占位，呼吸动画）；失败用现有错误视图 + 重试；下拉刷新。

## 实现

1. `NodeSeekUserContentClient` 加 `loadProfile(uid:)`、`loadTodayProgress()`；模型放 `UserContentRecords.swift`（`UserProfileRecord`、`UserTodayProgressRecord`、`UserLevelProgress`）。
2. 帖子 / 评论 / 收藏列表 init 加可选 `uid`、`title`；不传时保持现状（取当前账号）。
3. 新增 `Features/UserContent/UserProfileViewController.swift`（UIKit 滚动视图 + stack，内容少不需要 Texture）。
4. 新增 `UserProfileRouter.makeViewController(profileURL:title:)`：能解析出 uid 走原生页，否则回落 `UserInfoWebViewController`；替换 5 个 `/space` 入口，签到入口不动。
5. 测试：getInfo / 今日进度解码、加入天数、等级进度、路由回落。

## 待定

- 私信本期跳网页，私信原生化另议。
- 等级、鸡腿原生页后续再做。
