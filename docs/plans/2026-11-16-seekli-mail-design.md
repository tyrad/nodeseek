# seek.li 邮箱接入设计

## 目标与范围

在 App 内查看和管理 NodeSeek 邮箱（seek.li）的邮件。用户在 seek.li 控制台创建 API Key，粘贴到 App 后存入钥匙串；所有请求从本机直接发往 seek.li，不经过开发者的服务。

- **P0（收信）**：绑定 Key、验证码（顶部卡片和行内复制）、邮件列表（切换邮箱和文件夹，邮箱很多时用选择面板；只搜当前文件夹；分页）、邮件详情（HTML 正文、附件预览）、单封邮件的已读/星标/移动/延迟删除、用量查看。回收站只读。
- **P1（发信与提醒）**：写信与回复（只限 seek.li 域邮箱，纯文本，无附件）、回到前台增量检查新邮件并在 Tab 上显示未读数、入口未读数、第一屏列表快照缓存（打开时先显示上次内容再刷新）、本机给邮箱起名字（待评估）。
- **不做**：联系人、过滤规则、签名、标签管理、邮箱创建与释放、全部标为已读、恢复已删除邮件（接口不支持）。菜单里放「在网页中管理」跳到 seek.li 控制台。

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
| | `DELETE /mails/{id}` | mail:manage | ✅ | 只是移到回收站；在回收站里再删，提示不变，无法彻底删除。**无法恢复**：对回收站邮件调用移动接口（`folderId` 为 null 或文件夹 ID）都返回成功，但状态仍是 `deleted` |
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
- `GET /mails` 列表里的新邮件同样带 `verificationCode`，早期入库的旧邮件没有这个字段。
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

视觉稿 v2：`docs/assets/2026-11-16-seekli-mail-ui.png`（源文件为同名 `.html`）。共 11 屏：绑定 Key、全部邮箱收件箱、邮箱选择面板（邮箱很多时）、详情、深色单邮箱与滑动删除、长按菜单、搜索、更多菜单、列表状态、入口，以及邮箱较少时的系统菜单。

整体沿用 App 的黑白主题（见 `docs/project-overview.md` 第 7 节）。所有颜色都用系统动态色，深色模式自动适配。强调色用 `.label`；主按钮用 `.label` 底、`.systemBackground` 字的反色样式；不用站点绿。只有删除用红色、星标用橙色。

### 入口

- 「我的」页在「探针」下方加一行「邮箱」。
- 侧边栏加「邮箱」。
- `MainTabItem` 新增 `.mail`（标题「邮箱」，图标 `envelope`）。默认不在底部栏，用户自己添加。
- 第一期入口**不显示未读数**：没有自动刷新，数字会过时。P1 做了回到前台刷新后再加，统一表示全部邮箱的未读数。

### 邮箱名的显示规则（邮箱很多时的可读性）

| 情况 | 显示 |
|---|---|
| 网页上设了别名 | 别名为主；需要完整地址的地方用小字补充 |
| 没设别名 | 只显示 @ 前面的部分，域名用浅灰 |
| 不同域名下 @ 前部分相同 | 补上域名，例如 `me@seek.li` 和 `me@nodeseek.org` |
| 名字过长 | 省略中间（`lineBreakMode = .byTruncatingMiddle`），开头和结尾都保留 |

- 别名只读：修改邮箱设置的接口实测 404，App 内改不了。本机起名字放到 P1 再评估。
- 详情页的收件地址始终显示完整地址，可以长按复制。
- 显示名的计算写成纯函数，方便单测。输入是全部邮箱列表，因为是否重名要和其他邮箱比较。

### 绑定 Key（未授权时）

- 主界面只有：一句话说明、Key 输入框（带「粘贴」）、「验证并保存」按钮、「去 seek.li 创建 Key」链接（用 SFSafariViewController 打开 `https://seek.li/manage/developer`）。
- 需要哪些权限收进「如何获取 Key、需要哪些权限」，点开推入一页说明。
- 粘贴时自动去掉 `Bearer ` 前缀，规则和 `NodeImageAPIKeyNormalizer` 一致。
- 验证只请求一次 `GET /mailboxes`，成功后再写入钥匙串；返回 401 时，在输入框下方提示「Key 无效或已失效」。
- 其他权限不在绑定时逐项验证。用到时遇到 403，就按接口对应的权限给出具体提示，例如「Key 缺少 attachment:read 权限，无法下载附件」，不笼统说 Key 失效。

### 邮件列表

```
┌ ‹      全部邮箱 23 ▾          🔍  ⋯ ┐  ← 标题切换邮箱；小数字是邮箱个数
│ 收件箱  垃圾邮件  回收站  📁账单 …   │  ← 横向 tab，多了可横向滚动
│ ┌────────────────────────────────┐ │
│ │ 482913  GitHub → github-alt  复制│ │  ← 只放当前范围最新的一条验证码
│ └────────────────────────────────┘ │
│ ● GitHub                     09:39 │
│   [GitHub] Please verify…  ┌──────┐│
│   → github-alt · Verifi…   │482913││  ← 带验证码的行，右侧可直接复制
│ ● VMISS                  📎  昨天  │
│   Invoice Payment Confirmation     │
│   → VMISS 账单 · This is a paym…   │  ← 摘要一行；「全部邮箱」时开头标收件邮箱
└────────────────────────────────────┘
```

- 用高密度列表加细分割线，不做成卡片。未读用左侧 `.label` 小圆点加粗体表示。次要文字用系统二级灰，不用三级灰。
- 摘要只显示一行。选「全部邮箱」时，摘要开头用灰字标出收件邮箱（`→ 显示名 ·`）；选中单个邮箱时不显示。
- 「已发送」tab 不放：用 API 发出的邮件不在里面。
- **验证码**：
  - 数据直接取自列表接口里每封邮件的 `verificationCode` 字段（新邮件都有，早期入库的旧邮件没有），不再另外请求 `/mails/unread`。这样也只会显示当前邮箱和文件夹范围内的验证码。
  - 顶部卡片只放当前范围内、15 分钟内收到的最新一条，只写「几分钟前收到」，不暗示有效期。
  - 带验证码的邮件行右侧也显示验证码，点一下就复制。
  - 复制只写剪贴板并给轻触觉反馈，原位显示「已复制」约 2 秒；**不标已读**，卡片也保留。进入详情页才标已读。
- 搜索：用 UISearchController，**只搜当前邮箱和文件夹**，搜索栏下方写明范围。输入停顿 400ms 后才请求。关键字在本地高亮。搜索时隐藏顶部验证码卡片。
- 下拉刷新；滑到底部时按 offset 分页，每页 20 条。
- 右滑只有「已读/未读」，星标在详情页和长按菜单里操作。
- **左滑删除，延迟提交**：
  - 实测接口无法恢复回收站里的邮件：移回收件箱或移到文件夹后，状态仍是 `deleted`。所以撤销只能靠延迟提交。
  - 删除后先把邮件从列表里隐藏，底部 toast 倒计时 4 秒，期间点「撤销」就直接恢复显示，不发任何请求。
  - 4 秒到了，或离开页面、App 进入后台，就立即发 `DELETE`。失败时邮件重新出现，并提示原因。
- **回收站只读**：顶部固定说明「回收站只能查看 · 网页中恢复」，滑动和长按菜单里都没有删除或恢复。
- 长按邮件弹出系统上下文菜单：只看「这封信的收件邮箱」（副标题是完整地址）、标为已读或未读、加或去星标、移动到…、删除。
- 「⋯」菜单：刷新、存储用量（菜单项里直接显示 `6.4 MB / 80 MB` 和进度条）、在网页中管理、更换 Key、移除 Key（需二次确认）。第一期**不做**「全部标为已读」。
- 状态：
  - 首次加载显示骨架行；空列表按文件夹给不同文案；没有内容时网络失败，显示「重试」。
  - 被限流时保留当前列表，顶部条倒计时；401 时回到绑定流程；403 提示具体缺哪个权限。

### 切换邮箱

- **5 个及以内**：标题弹出系统 UIMenu，不显示未读数，也不额外请求。
- **超过 5 个**：弹出可拖拽的面板（UISheetPresentationController，半屏或全屏）：
  - 顶部搜索框，按地址和别名过滤。
  - 搜索框下方是最近打开的 3 个邮箱，作为快捷入口，存在 UserDefaults。
  - 第一行固定是「全部邮箱」。
  - 下面按「置顶 → 有未读 → 其他」分组。置顶读接口的 `isPinned`，组内按 `sortOrder` 排，没有排序就按字母排。
  - 每行显示：显示名、浅灰的域名（或别名下面的完整地址）、未读数；能发信的 seek.li 邮箱带「可发信」小标记。
  - 未读数在打开面板时请求一次 `/mails/counts`，一个请求就能拿到全部邮箱的数量。
- 选中的邮箱和文件夹会记住，下次进来直接打开。

### 邮件详情

- 头部：主题（大号粗体）、发件人名称和地址、时间。下一行是「发给 完整收件地址」，可以长按复制。SPF/DKIM/DMARC 有失败项时，显示一行弱提示「发件人未通过验证，请留意链接」，不拦截内容。
- 正文：
  - 有 HTML 时用 WKWebView，**不套外框**，占满可读宽度。禁用 JavaScript。
  - 远程图片默认不加载（用 `WKContentRuleList` 拦截），上方显示横幅「已阻止 N 张远程图片 · 加载」，加载只对这一封生效。
  - 注入 `color-scheme: light dark` 和最小样式，让没有样式的邮件在深色模式下也能看清。邮件自带背景色的保持原样。
  - 只有纯文本时用 UITextView，自动识别链接。
  - **链接用 `UIApplication.open` 打开**：很多验证邮件给的是登录链接，用系统方式打开才能跳回对应的 App。长按链接可以复制。
  - 正文里有验证码时，顶部显示验证码反色条，可以一键复制。
- 附件区：显示文件名和大小。点开先下载到临时目录，再用 QLPreviewController 预览，可以分享。
- 底部用系统工具栏：移动、标为未读、删除（同样延迟提交）。星标放在导航栏。第一期不放「回复」占位。
- 打开详情时自动标为已读（`PUT /mails/{id}/read`），失败不提示。
- 请求次数：打开一封邮件发 2 个请求（详情 + 标已读）；有附件时再加 1 个附件列表请求。

### 写信（P1）

- 发件邮箱只能选 seek.li 域的邮箱；nodeseek.org 的邮箱显示为禁用，并说明「该域名不支持发信」。没有可用的发件邮箱时，不显示写信入口。
- 字段：收件人、抄送（折叠）、主题、纯文本正文。不支持附件，界面不放附件按钮。
- 回复时自动填好收件人、`Re:` 主题和引用的原文。
- 发送时按钮变成菊花，禁止重复点击。成功后关闭页面，提示「已提交发送」：接口返回 `queued` 只代表进了发送队列，不代表已经送达。失败时保留草稿，并显示服务端返回的提示。

### 新邮件提醒（P1）

- 只在 App 回到前台时检查，不做后台轮询，两次检查至少间隔 30 秒。
- 用 `after_id` 增量查询，最大 ID 存在 UserDefaults；每天做一次不带 `after_id` 的完整同步。
- 入口和底部栏的「邮箱」显示全部邮箱的未读数，数据来自 `/mails/counts`。

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
2. ✅ `feat(mail): 绑定 seek.li API Key`：钥匙串存储、绑定页和三个入口。
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
- **已确认（2026-11-16）**：P0 只做收信；入口为「我的」、侧边栏，加上可选的底部栏；远程图片默认拦截；删除用 4 秒延迟提交；文件夹保留横向 tab；P0 入口不显示未读数；邮箱超过 5 个改用选择面板。
- **删除的时间窗**：延迟提交期间如果 App 被杀掉，删除请求不会发出，邮件仍然保留。这是可以接受的退化方向（宁可没删掉，也不误删）。
