# NodeSeek 帖内投票支持调研

调研日期：2026-09-08。范围：读取真实帖子、官网脚本和项目代码，提出接入方案；未提交投票，未修改业务代码。

## 结论

建议增加原生投票内容块，复用现有 WebView 会话执行带签名的请求，并保留打开原帖的降级入口。无需为正文整体引入 WebView。

若只需尽快恢复可用性，可先识别投票标记并提供“打开网页参与投票”卡片，点击进入已有 NodeSeekWebViewController；这一阶段不包含原生选项和结果。

## 真实页面证据

- 帖子：https://www.nodeseek.com/post-917518-1
- 标题：大家是订阅codex的哪种套餐。
- 投票：3108，题目为“大家订阅codex的哪种套餐”。
- 当前配置：单选、公开、未锁定。选项 plus / pro / free / 中转，对应选项 ID 14131 / 14132 / 14133 / 14134。
- 原始 HTTP 正文只有标记：`<a href="javascript://void(0)" data-href="nsapp://vote?id=3108">nsapp://vote?id=3108</a>`。
- 官网 JavaScript 将该节点替换为 Vue 的 `.vote-panel > .embed-vote`，不是 iframe。
- 已渲染 DOM 中存在标题、单选框及投票编号文本，原始 data-href 链接已被替换。因此客户端必须兼容原始 HTML 和 WebView 渲染后的 HTML 两种输入。

官网实现来源：

- https://www.nodeseek.com/static/js/vote.88e0511fb187a45a164d.js
- https://www.nodeseek.com/static/js/index.fe1735d2c612b46e0cd9.js

## 接口与请求要求

| 操作 | 接口 | 验证程度 |
| --- | --- | --- |
| 读取投票 | GET /api/vote/info/3108 | 浏览器会话实测 200、success=true |
| 提交选项 | POST /api/vote/voteforitem，JSON `{"ids":[14131]}` | 官网脚本确认，未实际提交 |
| 公开投票人员翻页 | GET /api/vote/voter-of-item?id={选项ID}&page={页码} | 官网脚本确认，未实际请求 |

读取响应包含 vote.id、title、multiple、isPublic、locked、uid 和 items；选项包含 vote_item_id、vote_id、text、voted。

本次会话未投票，响应未包含 count 或 voters。不能将缺失票数显示为 0。官网按选项 voted 推导 hasVoted，并在投票后展示结果。

官网统一请求封装添加 `x-dynamic-sign`，值为以下文本的 SHA-1 十六进制摘要：

```text
[HTTP method, absolute URL, navigator.userAgent, exact request body].join("\n\n")
```

GET 请求体为空字符串。普通 fetch 实测返回 403 / success=false；按官网规则添加签名后，相同读取接口返回 200。项目尚未找到对应签名实现，不能直接照搬当前点赞请求。

请求应复用 App 的 WebView Cookie 会话；签名所用 URL、User-Agent 和 JSON 文本必须与实际发送值一致。签名属于当前官网实现，后续可能变化。

## 现有项目缺口

- KannaNodeSeekParser 保留正文 innerHTML，本身不执行投票组件。
- RenderedContentBlock 没有投票类型；DTCoreText 不会执行 Vue 或提供有效表单交互。
- iframeLink 只处理 iframe 的 HTTP(S) 地址，无法覆盖此类投票。
- PostDetailLinkResolver 没有 nsapp 专门分支；若 nsapp 链接进入该路由，会被当作 externalApp。原始正文还使用 javascript href，不能仅修改普通链接跳转。
- NodeSeekWebViewContext 已使用默认网站数据存储和 Cookie 会话，可复用登录能力。
- 当前工作区包含分栏、终端图片等未提交改动。本方案不调整那些功能。

## 建议实现范围

1. 在 SharedCore/Parsing 中统一提取投票引用：识别 data-href、正常 nsapp href，以及已挂载 vote-panel 中的编号。仅在已确认投票容器中解析编号，避免把普通正文或代码示例误判为投票。对已渲染结构优先保留或恢复统一标记。
2. 新增投票数据模型，票数与投票人员为可选字段；新增 `.vote` 渲染块并保持正文顺序，覆盖详情正文、评论和楼层预览中对应的渲染分支。
3. 增加 VoteService 与 WebView 请求实现。读取可重试；提交超时后先重新读取投票状态，不自动重复提交。按投票 ID 合并同一会话的并发读取，切换账号时清除会话相关状态。
4. 原生卡片展示标题、单选/多选、公开/匿名提示、选项和提交按钮；适配动态字体、浅色与暗黑模式。提交中禁用重复点击。
5. 按官网规则显示未投票、已投票、已锁定、加载失败和登录失效等状态。首次范围不包含创建投票、管理投票或投票人员分页。
6. 用户明确选择并提交时提示“提交后不可修改”，公开投票同时提示选择可公开。成功后重新读取服务端状态；已投票时显示选中项和服务端提供的票数。
7. 多选结果若提供百分比，应明确采用官网“选项票数之和”的分母；不能把选项总票数称为参与人数。没有票数时不展示虚构的统计。
8. 失败时提供打开原帖入口，并将 nsapp://vote 路由接入投票展示，避免调用外部 App。

## 验证方案

- SharedCore fixture：原始标记、已渲染 DOM、单选/多选、无效 ID、多投票、嵌套正文及代码示例误识别；运行 make spm-test。
- 请求验证：签名固定样本、精确 JSON 请求体、未返回票数、服务端拒绝、登录失效、提交超时后重新读取。
- Xcode 窄范围测试：投票卡片布局与状态、正文/评论/预览接入、现有图文与分栏回归；跨层改动后 make xcode-build-tests。
- 实际交互验证需使用可用于测试的投票；本次调研没有代用户选择或提交，提交端到端行为尚未验证。

## 待实现时确认

- 已投票、匿名、多选与锁定状态的真实响应样本，目前只有官网代码证据。
- App 当前会话在 WebView 中调用签名接口的实际表现及挑战页处理。
- 服务端实际错误文案、频率限制与响应变化。
