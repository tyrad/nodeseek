# seek.li 邮箱接入设计

## 目标与范围

在 App 内查看和管理 NodeSeek 邮箱（seek.li）的邮件。用户在 seek.li 控制台创建 API Key，粘贴到 App 后存入钥匙串；所有请求从本机直接发往 seek.li，不经过开发者的服务。

- **P0（收信）**：绑定 Key、验证码卡片、邮件列表（切换邮箱/文件夹、搜索、分页）、邮件详情（HTML 正文、附件预览）、已读/星标/移动/删除、用量查看。
- **P1（发信与提醒）**：写信与回复（只限 seek.li 域邮箱，纯文本，无附件）、回到前台增量检查新邮件并在 Tab 上显示未读数。
- **不做**：联系人、过滤规则、签名、标签管理、邮箱创建与释放。菜单里放「在网页中管理」跳到 seek.li 控制台。

## 已核实的数据契约

来源：`https://seek.li/api/openapi.json`（OpenAPI 3.0，v1.0.0），2026-11-16 用测试账号逐个接口实测。**实测结果与文档不一致时，以实测为准**，下文已标出差异。

### 基本信息

- Base URL：`https://seek.li/openapi/v1`
- 认证：`Authorization: Bearer sk_live_...`。Key 在控制台按权限范围勾选：
  - P0 需要：`mailbox:read`、`mail:read`、`mail:manage`、`attachment:read`、`folder:read`、`storage:read`
  - P1 另需：`mail:send`
- 文档页 `seek.li/manage/developer/docs` 有 WAF 人机校验，命令行访问返回 468；**`/openapi/v1` 不受影响**，curl 和 CFNetwork 风格的 UA 都能正常访问。
- 限流：响应头 `x-ratelimit-limit: 60`、`x-ratelimit-remaining`、`x-ratelimit-reset`（Unix 秒），即每分钟 60 次。超限返回 429。
  - 另外，短时间内连续请求十几次会触发 `AUTH_RATE_LIMITED`（“认证失败次数过多，请稍后再试”），约 2 分钟后恢复。即使 Key 有效也会触发。
- 时间格式：ISO 8601，部分字段带 9 位纳秒，例如 `2026-11-16T01:02:01.785362836Z`。新建对象的 `createdAt` 可能是 `0001-01-01T00:00:00Z`，按缺失处理。

### 错误格式

两种形态都会出现，解析时都要兼容：

```json
{"error":{"code":"BAD_REQUEST","message":"参数错误"}}
{"error":"无效的ID"}
```

已见错误码：`UNAUTHORIZED`（Key 无效，401）、`AUTH_RATE_LIMITED`、`BAD_REQUEST`（400）、`SEND_FAILED`（500，例如“该域名已禁止发信”）。路由不存在时返回 `{"error":"SPA not configured for user"}`（404）。

### 接口清单与实测结果

| 分类 | 接口 | 权限 | 实测 | 备注 |
|---|---|---|---|---|
| 邮箱 | `GET /mailboxes` | mailbox:read | ✅ | `data: Mailbox[]` |
| | `GET /mailboxes/{id}` | mailbox:read | ✅ | |
| | `POST /mailboxes` `{address}` | mailbox:write | ✅ 201 | 不做 |
| | `DELETE /mailboxes/{id}` | mailbox:write | ✅ 202 | 进入 7 天释放保留期；不做 |
| | `GET /mailbox-release-holds`、`POST .../{id}/restore` | mailbox:write | ✅ | 不做 |
| | `POST /mailboxes/check?address=` | mailbox:write | ✅ | **参数只能放 query**，放 body 会报 400 |
| | `PUT /mailboxes/{id}/settings` | mailbox:write | ❌ 404 | 服务端未实现 |
| 邮件 | `GET /mails` | mail:read | ✅ | 见下方「列表」 |
| | `GET /mails/{id}` | mail:read | ✅ | **返回 `data.mail` + `data.tags`**，文档写的是 `data` |
| | `GET /mails/unread` | mail:read | ✅ | 跨邮箱的未读邮件，**带 `verificationCode`** |
| | `GET /mails/counts` | mail:read | ✅ | 只有未读数：`{"mailboxes":{"<id>":8},"total":8}` |
| | `PUT /mails/{id}/read` `{read}` | mail:manage | ✅ | |
| | `PUT /mails/{id}/flag` `{flagged}` | mail:manage | ✅ | |
| | `PUT /mails/{id}/folder` `{folderId}` | mail:manage | ✅ | `null` 表示移回收件箱 |
| | `DELETE /mails/{id}` | mail:manage | ✅ | 只是移到回收站；在回收站里再删，提示不变，无法彻底删除 |
| | `GET /mails/{id}/raw` | mail:read | ✅ | `text/plain` 原文，含 Authentication-Results |
| | `POST /mails/{id}/tags` `{tagId}`、`DELETE .../tags/{tagId}` | mail:manage | ✅ | 不做 |
| 发信 | `POST /send` | mail:send | ⚠️ | 见下方「发信」 |
| 附件 | `GET /mails/{id}/attachments` | attachment:read | ✅ | `index` 用于下载 |
| | `GET /mails/{id}/attachments/{index}` | attachment:read | ✅ | 二进制；文件名从 `content-disposition` 取 |
| | `POST /upload/attachment` | attachment:write | ❌ 404 | 服务端未实现 |
| 文件夹 | `GET/POST/PUT/DELETE /folders` | folder:* | ✅ | 无自定义文件夹时 `data: null` |
| 标签 | `GET/POST/PUT/DELETE /tags` | tag:* | ✅ | 新账号有 5 个系统标签 |
| 联系人/过滤规则/签名 | 增删改查 | contact/filter/signature:* | 列表 ✅ | 创建签名报“参数错误”，字段名与文档不符；不做 |
| 存储 | `GET /storage`、`GET /quotas` | storage:read | ✅ | 已用 / 上限（字节）和百分比 |

### 列表（`GET /mails`）

- 查询参数：`mailbox_id`、`folder`（inbox/sent/trash/spam）、`folder_id`、`tag_id`、`search`、`limit`（默认 20）、`offset`。均已实测可用。
- 返回 `data: Mail[]` + `pagination {total, limit, offset}`。**结果为空时 `data` 是 `null`**。
- 列表里的 `bodyText` 是截断后的摘要（约 200 字），`bodyHtml` 为空字符串。完整正文要请求详情。
- 用 API 发出的邮件**不会出现在 `folder=sent`** 里。

### 全局未读（`GET /mails/unread`）

- 返回 `UnreadMail[]`：`id`、`mailboxId`、`mailboxAddress`、`fromAddress`、`fromName`、`subject`、`verificationCode?`、`receivedAt`。不含正文，不会把邮件标为已读。
- 分页：`page {limit, hasMore, nextCursor}`，`hasMore` 为 false 时 `nextCursor` 为空字符串。
- 增量：`after_id` 只返回该 ID 之后入库且仍未读的邮件。服务端建议客户端定期不带 `after_id` 做一次完整同步。
- 实测：邮件发出约 1 秒后就能查到，“您的验证码是 482913” 被正确提取为 `"482913"`。移到回收站的邮件不再出现。

### 发信（`POST /send`）

- 请求体：`mailboxId`（Int）、`to`、`cc`、`bcc`、`subject`、`bodyText`、`bodyHtml`。
- **`to`/`cc`/`bcc` 实际要传字符串**，例如 `"a@x.com"`。按文档传数组会报 400 “参数错误”。多个收件人用英文逗号拼成一个字符串，例如 `"a@x.com,b@x.com"`，已实测两个人都能收到。
- **nodeseek.org 域的邮箱禁止发信**，返回 500 `SEND_FAILED`“该域名已禁止发信”；seek.li 域可以发。每个邮箱有 `domainId`，但 API 没有提供查询域名能否发信的接口，只能按地址后缀判断，再以服务端返回为准。
- 成功时返回已入队的邮件（`status: "queued"`），带 `id`、`messageId`、`sentAt`。
- 不支持附件：请求体没有附件字段，上传接口也是 404。

### 模型字段（只列用到的）

- `Mailbox`：`id`、`address`、`alias?`、`domainId`、`status`、`sendDisabled`、`isPinned`、`sortOrder`
- `Mail`：`id`、`mailboxId`、`folderId?`、`fromAddress`、`fromName`、`toAddress`、`cc?`、`subject`、`bodyText`、`bodyHtml`、`verificationCode?`、`isRead`、`isFlagged`、`isPinned`、`hasAttachments`、`status`、`receivedAt`、`size`、`spamScore`、`scoreDetails`（JSON 字符串，含 spf/dkim/dmarc）
- `Attachment`：`id`、`filename`、`contentType`、`size`、`isInline`、`index`
- `Folder`：`id`、`name`、`icon`（emoji）、`color`、`mailCount`、`unreadCount`
- `Quota`：`storage {used, quota, usagePercent}`、`mailboxes {count}`

字段缺失或为 `null` 都按可选处理，未知字段忽略。

## 功能与 UI

整体沿用 App 的黑白主题（见 `docs/project-overview.md` 第 7 节），所有颜色用系统动态色，深色模式自动适配。强调色用 `.label`，主按钮用 `.label` 底、`.systemBackground` 字的反色样式，不用站点绿。

### 入口

- 「我的」页加一行「邮箱」，放在「探针」旁边。
- 侧边栏加「邮箱」。
- `MainTabItem` 新增 `.mail`（标题「邮箱」，图标 `envelope`），用户可以自己加到底部栏。

### 绑定 Key（未授权时）

- 一句话说明：「用 seek.li 的 API Key 在 App 里收发邮件，Key 只保存在本机钥匙串。」
- 多行输入框粘贴 Key，可以识别带 `Bearer ` 前缀的写法，规则和 `NodeImageAPIKeyNormalizer` 一致。
- 「去 seek.li 创建 Key」按钮，用 SFSafariViewController 打开 `https://seek.li/manage/developer`。
- 列出需要勾选的权限，并提示「不要勾选全部权限」。
- 点「保存」时先请求一次 `GET /mailboxes` 校验 Key，通过后再写入钥匙串；401 时提示「Key 无效或已失效」。

### 邮件列表

```
┌ 全部邮箱 ▾                             ⋯ ┐   ← 标题按钮弹出 UIMenu 切换邮箱
│ 收件箱  垃圾  回收站  📁自定义…          │   ← 横向 tab，选中加粗+短下划线
├──────────────────────────────────────────┤
│ 482913   GitHub · x@seek.li · 2 分钟前  复制 │   ← 验证码卡片，最多 3 条
├──────────────────────────────────────────┤
│ ● GitHub                       10:42  📎★ │
│   [GitHub] Please verify your device      │
│   Verification code: 482913 ...           │   ← 摘要最多 2 行
└──────────────────────────────────────────┘
```

- 不做成卡片，用高密度列表加细分割线。未读用左侧 `.label` 小圆点加粗体表示。
- 「已发送」tab 先不放，因为 API 发出的邮件不在里面，放了会让人误以为没发出去。
- 验证码卡片的数据来自 `/mails/unread` 中 30 分钟内、带 `verificationCode` 的邮件。点「复制」后：写入剪贴板、轻触觉反馈、标记已读，卡片随即消失。
- 搜索用 UISearchController，输入停顿 400ms 后再请求，节省限流次数。
- 下拉刷新；上滑到底部时用 offset 分页，每页 20 条。
- 左滑删除（移到回收站）；右滑切换已读/未读、加或去星标。
- 「⋯」菜单：刷新、用量（显示 `已用 6.4MB / 80MB`）、在网页中管理、更换 Key、移除 Key。
- 状态：加载中用骨架或菊花；空列表显示「没有邮件」；401 时回到绑定页并提示 Key 失效；限流时显示「请求太频繁，稍后再试」，保留当前列表。

### 邮件详情

- 头部：主题（大号粗体）、发件人名称和地址、收件人、时间。SPF/DKIM/DMARC 有失败项时显示一行弱提示「发件人未通过验证」。
- 正文显示：
  - 有 HTML 时用 WKWebView：禁用 JavaScript，链接一律交给系统或 Safari 打开。
  - 远程图片默认不加载（用 `WKContentRuleList` 拦截），顶部横幅「已阻止远程图片 · 加载」。
  - 注入 `color-scheme: light dark` 和最小样式，让无样式的邮件在深色模式下可读。邮件自带背景色的保持原样。
  - 只有纯文本时用 UITextView，自动识别链接。
  - 正文里有验证码时，顶部显示验证码条，可以一键复制。
- 附件区：文件名、大小。点开先下载到临时目录，再用 QLPreviewController 预览，可以分享。
- 底部工具栏：星标、移动到文件夹、删除；P1 再加回复。
- 打开详情时自动标为已读（`PUT /mails/{id}/read`），失败不提示。

### 写信（P1）

- 发件邮箱只列 seek.li 域的邮箱；nodeseek.org 邮箱显示为禁用，并说明「该域名不支持发信」。没有可用发件邮箱时，写信按钮隐藏。
- 字段：收件人、抄送（折叠）、主题、纯文本正文。不支持附件，界面不放附件按钮。
- 回复时自动填好收件人、`Re:` 主题和引用的原文。
- 发送时按钮转菊花并禁止重复点击；成功后关闭页面并提示「已发送」；失败时保留草稿，并显示服务端返回的提示。

### 新邮件提醒（P1）

- 只在 App 回到前台时检查，不做后台轮询。两次检查至少间隔 30 秒。
- 用 `after_id` 增量查询，最大 ID 存在 UserDefaults；每天做一次不带 `after_id` 的完整同步。
- 底部栏的「邮箱」显示未读数角标，数据来自 `/mails/counts`。

## 技术方案

### 分层

所有邮箱代码都放在 `nodeseek/Features/Mail/`，不拆到 SharedCore；测试走 Xcode（`make xcode-test-class`）。

| 目录 | 文件 | 内容 | 状态 |
|---|---|---|---|
| `Mail/API` | `SeekMailTargetType.swift` | 仿 Moya 的 `TargetType` 协议：`baseURL`、`path`、`method`、`task`、`headers`；`makeURLRequest` 负责拼 query 和 JSON 请求体 | ✅ 已实现 |
| | `SeekMailAPI.swift` | 接口枚举，每个接口一个 case；`SeekMailListQuery`、`SeekMailDraft` | ✅ |
| | `SeekMailProvider.swift` | 仿 `MoyaProvider`：加 Bearer Key、插件、状态码校验、`data` 外壳解码、限流记录；`where Target == SeekMailAPI` 提供带类型的便捷方法 | ✅ |
| | `SeekMailModels.swift` | 邮箱、邮件、未读、附件、文件夹、配额等模型 | ✅ |
| | `SeekMailError.swift` | 错误类型、给用户看的文案、两种错误体的解析 | ✅ |
| `Mail/` | Keychain Key 存储、绑定页、列表、详情、写信 | 结构参考 Probe | 待做 |

### 自写的仿 Moya 接口层

没有引入 Moya（原因见下文「体积实测」）。自己写了一套只覆盖邮箱模块所需的简化版，用法和 Moya 接近：

```swift
// 接口定义：一个 case 对应一个接口
enum SeekMailAPI {
    case mails(SeekMailListQuery)
    case markRead(id: Int64, read: Bool)
    case send(SeekMailDraft)
    // ...
}
extension SeekMailAPI: SeekMailTargetType {
    var path: String { ... }
    var method: SeekMailHTTPMethod { ... }
    var task: SeekMailTask { ... }   // .requestPlain / .requestParameters / .requestJSON
}

// 调用
let api = SeekMailProvider<SeekMailAPI>(apiKey: { keyStore.apiKey() })
let list = try await api.mails(SeekMailListQuery(folder: .inbox))
try await api.markRead(id: mail.id, read: true)
// 或者直接用底层方法
let raw = try await api.request(.rawMail(id: 1))
```

和 Moya 的对应关系、以及简化掉的部分：

| Moya | 这里 | 说明 |
|---|---|---|
| `TargetType` | `SeekMailTargetType` | 去掉了 `sampleData`、`validationType`；多了 `requiresAuthorization` |
| `Task` | `SeekMailTask` | 只保留三种：无参数、query、JSON（JSON 时也可以带 query） |
| `MoyaProvider` | `SeekMailProvider` | 只支持 async/await，不用回调；通过 `transport` 闭包注入请求，测试时传本地假数据 |
| `PluginType` | `SeekMailPlugin` | 只保留 `prepare` 和 `didReceive`；默认带 `SeekMailLoggerPlugin`，日志只记方法、路径和状态码，不记请求头 |
| `AccessTokenPlugin` | 内置 | Provider 每次请求时调用 `apiKey()` 取 Key，没有 Key 时不发请求，直接抛 `missingAPIKey` |
| 下载 | `downloadAttachment` | 直接返回 `Data`、文件名和类型，由调用方写入临时文件 |

服务端行为和文档不一致的地方，都在这一层处理掉了，界面层不用关心：

- `data: null` 时，数组按空数组处理。
- `GET /mails/{id}` 多套的一层 `data.mail` 由 `SeekMailDetail` 解开。
- 发信时，收件人数组拼成逗号分隔的字符串。
- 「移回收件箱」时显式传 `"folderId": null`。
- 时间带 9 位纳秒的，先截到毫秒再解析。
- 两种错误格式统一转成 `SeekMailError`；`AUTH_RATE_LIMITED` 和 429 都当作限流处理。
- `x-ratelimit-*` 响应头记在 `provider.rateLimit` 里。

**体积实测（2026-11-16，Moya 方案已放弃）**：

- 测试方法：在工程副本里分别 archive Release 版本（不签名）。Moya 版额外加了一个文件，模拟邮箱模块的真实用法：4 个接口、鉴权和日志插件、附件下载。
- 版本：Moya 15.0.3、Alamofire 5.12.2，Xcode 27.2。

| | 基线 | 加 Moya | 增量 |
|---|---|---|---|
| 主二进制 | 9.11 MB | 10.45 MB | +1.34 MB（+14.7%） |
| .app | 13.47 MB | 14.82 MB | +1.35 MB（+10.0%） |
| 压缩后的 IPA（接近下载大小） | 7.12 MB | 7.62 MB | +0.50 MB（+7.0%） |

另外，SPM 解析时会把 RxSwift（11MB）和 ReactiveSwift（41MB）的源码一起拉下来；工程开启了 `MemberImportVisibility`，业务代码还得额外写 `import Alamofire`。

### 测试

- **`SeekMailAPITests`**（`nodeseekTests/Features/Mail/`）：17 个用例，覆盖：
  - 请求构造：query 去掉空值并排序、空游标省略、显式 null、收件人拼接、PUT 请求体、Bearer 头、没有 Key 时不发请求
  - 响应解析：分页、`data: null`、详情嵌套、未读和验证码、纳秒时间、未读计数、限流头
  - 错误映射：五种错误响应、网络错误
  - 发信域名判断
- 样例数据取自实测响应，地址和姓名都换成了假值。
- **人工**：用测试 Key 走一遍绑定、列表、详情、附件和发信；浅色、深色各截一张图。

## 实施步骤与提交拆分

1. ✅ `feat(mail): 新增 seek.li 邮箱接口层`：仿 Moya 的接口枚举、Provider、模型、错误和测试。
2. `feat(mail): 绑定 seek.li API Key`：钥匙串存储、绑定页和三个入口。
3. `feat(mail): 查看邮件列表和验证码`：列表、验证码卡片、滑动操作。
4. `feat(mail): 查看邮件详情和附件`：详情、HTML 安全渲染、附件预览。
5. P1：`feat(mail): 用 seek.li 邮箱写信和回复`、`feat(mail): 回到前台提醒新邮件`。

每一步单独构建、单独测试，然后再进行下一步。

## 风险与待定

- **接口和文档不一致**：`to` 的类型、详情的嵌套、错误格式都和文档不同，服务端以后可能修正。解码要两种写法都兼容，例如 `to` 先按字符串处理，数组也能接受。
- **限流**：每分钟 60 次，连续快速请求还会触发认证限流。列表页刷新、搜索、分页都要防抖，避免短时间内连续请求。
- **HTML 邮件的安全**：禁用 JS，拦截远程资源，链接一律外部打开，不让邮件内容访问 App 的 Cookie。
- **Key 安全**：只存在钥匙串，不写日志，不同步到 iCloud（`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`）。
- **联系人和签名的字段名**还没确认，本期不用，用到的时候再实测。
- **待确认**：P0 是否包含发信；三个入口的位置；远程图片是否默认拦截。
