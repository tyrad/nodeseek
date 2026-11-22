---
name: nodeseek-e2e
description: 为 NodeSeek iOS 客户端编写和无人值守运行 Midscene 发布前回归，验证读帖、最近浏览、分类评论、游客登录入口、退出后会话清理、系统推送与站内通知跳转、收藏、引用、看图、翻页筛选、已登录搜索、发帖草稿恢复及指定帖真实回帖与编辑，定位失败并报告发布风险。
---

# NodeSeek iOS 发布前回归

[运行脚本](scripts/run.sh) 负责构建当前工作树的 `nodeseek` Debug App、安装到专用模拟器并启动 WebDriverAgent。[可执行用例](scripts/smoke.test.mjs) 逐条冷启动 `com.mistj.nodeseek`，等待首页分类栏和真实帖子加载，结束时检查原进程仍然存活。

## 按功能找用例

从仓库根目录执行 `make e2e-list`。每行给出固定编号、中文场景、运行模式和账号条件或数据影响。读取目录不会启动设备或模型。随后按编号执行单条，例如：

| 要验证的问题 | 单跑命令 | 如何判断 |
| --- | --- | --- |
| 短末页滑到底时是否仍显示上一页 | `make e2e-case CASE=thread-pagination` | 在公开帖 1069173 连续滑过第 10 楼，核对底部楼层及页码，再从面板跳到末页并回到第一页 |
| 已登录用户能否打开发帖页再返回 | `make e2e-case CASE=member-compose` | 原生标题、正文和发布按钮出现，关闭后首页列表恢复 |
| 看到「已存本机」时杀进程会不会丢稿 | `make e2e-case CASE=draft-autosave` | 冷启动后恢复本轮标题和完整正文 |
| 搜「搬瓦工」能否打开对应的帖子 | `make e2e-case CASE=member-search` | 结果标题命中关键词，详情标题与选中的结果一致 |

单跑会选择该编号的默认模式。支持游客和已登录两种模式时默认游客，可用 `E2E_PROFILE=member` 切换。`login-me` 需要在命令前指定游客态多 Tab 设备的 `SIMULATOR_ID`。`real-comment` 会公开回帖并编辑。用例 ID 出现在测试名称、JUnit 和对应的 Midscene 报告文件名中。

## 新增一条用例的最短路径

1. 用 `make e2e-list` 找相近场景。原生导航照着 [member-compose](scripts/smoke.test.mjs) 写，跨进程恢复照着 [draft-save](scripts/draft.test.mjs) 写，公开写入和中断续验参考 [real-comment](scripts/comment.test.mjs)。先写一句验收条件，例如「关闭编辑器后回到有帖子的首页」。
2. 在对应功能目录执行 `rg -n 'accessibilityIdentifier|accessibilityLabel' nodeseek/Features/SideMenu nodeseek/Features/NewDiscussion`，按实际页面替换目录。复用 [nativeControls()](scripts/simulator.mjs) 的 `tap`、`get`、`value`。例如打开编辑器用 `await ui.tap('post-list-side-menu-new-discussion-button')`，等正文框用 `await ui.get('new-discussion-body')`。这样失败时报告能指出缺哪个控件。等待界面就绪用控件或可见条件；测延迟时才显式计时。
3. 账号名、输入值、楼层和计数用代码比对；动态计数从同一对象的可信来源取期望值。富文本是否可读、按钮是否被遮挡等视觉问题，用一次聚焦的 Midscene 断言检查当前画面。把提交和等待结果拆开，避免等待期间再次提交。
4. 在 [cases.json](scripts/cases.json) 登记固定 ID、中文目的、适用模式和数据影响。冒烟脚本用 `smoke(id, body, skip)`，专项脚本用 `caseTest(id, …)`；报告名复用同一个 ID。变更冒烟覆盖范围时同步下方用例表和执行数量。
5. 调试时执行 `make e2e-case CASE=<编号>`，先看本轮 `junit.xml` 是否只有预期的一条且确实执行。失败先看该编号的截图或 HTML，修正后只重跑这一条。若修改了共享步骤，再跑使用该步骤的其他用例，例如搜索入口同时影响 `search-navigation` 和 `member-search`。

## 运行

在仓库根目录使用 macOS、Xcode、npm、jq 和 [package.json](scripts/package.json) 支持的 Node.js 版本。模型会读取模拟器截图，使用专用测试账号和数据。

脚本默认读本机 `~/.config/nodeseek/e2e.json`，可通过 `E2E_CONFIG_FILE` 换位置。本机配置放在仓库外，各字段如下。

| 字段 | 用途 |
| --- | --- |
| `envFile` | 含 `OPENAI_API_KEY` 的已有 dotenv 文件的绝对路径。显式 `E2E_ENV_FILE` 优先，其次用进程已有的 `OPENAI_API_KEY`，最后才读本机配置指向的文件。 |
| `guestUDID`、`memberUDID` | 游客与已登录测试账号各自使用的设备。显式 `SIMULATOR_ID` 优先。未指定时分别按设备名 `NodeSeek E2E` 和 `NodeSeek E2E Member` 查找。 |
| `memberDisplayName` | 测试账号在侧栏头像旁的显示名，可用 `E2E_MEMBER_USERNAME` 覆盖。搜索和发帖入口两条用例都会核对指定的显示名。 |

本机的 `memberEnvFile` 指向 `~/.config/nodeseek/account.env`，其中保存 `E2E_MEMBER_USERNAME` 和 `E2E_MEMBER_PASSWORD`，权限为 `600`。回归默认取文件中的用户名核对侧栏账号；显示名与登录名不同时填写 `memberDisplayName`。密码供首次登录或会话续期时使用。

首次使用或会话过期时，执行 `make e2e-login`。账号会话由该设备上的 App 保存。运行器复用会话，模型无需接触密码。游客设备继续保持未登录。

```sh
# 仅检查本机 API Key 能读取、设备存在
bash .agents/skills/nodeseek-e2e/scripts/run.sh --check
E2E_PROFILE=member bash .agents/skills/nodeseek-e2e/scripts/run.sh --check

# 实跑
make e2e-smoke
E2E_PROFILE=member make e2e-smoke
```

可用 `xcrun simctl list devices available` 核对设备。两轮顺序执行，各自保留会话。跟踪命令直至退出，自行读报告。只有用户想看过程时才需要打开 Device Hub。缺少已登录测试设备时先完成游客回归，在结论中列出尚未验证的已登录流程。

## 真实登录与会话保持

`make e2e-login` 单独运行 [登录用例](scripts/login.test.mjs)，默认使用 member 设备。从阅读模式的游客侧栏打开站点登录表单，确认 App 加载官方 HTTPS 登录地址后，本机 WebDriverAgent 填写账号和安全密码框，提交一次。通过条件包括登录页自动关闭、侧栏显示指定账号，以及终止旧进程后冷启动仍显示同一账号。报告保存在本轮目录的 `junit.xml` 和 `report/member-login.html`。

此用例保留成功登录的会话供后续 member 回归使用。如果设备已经登录，使用另一个未登录的专用模拟器执行 `SIMULATOR_ID=<UDID> make e2e-login`，或从专用测试账号的设置页退出后再跑。站点要求人工验证时记录阻断，保留界面供处理。

### 登录后第一次打开「我的」

用游客态的专用模拟器执行 `E2E_LOGIN_ME=1 SIMULATOR_ID=<UDID> make e2e-login`。使用默认多 Tab 栏，先在「我的」确认游客资料卡，切到「通知」登录，自动返回后立即切回「我的」。该分支保留登录会话。按帧验证需要本机的 FFmpeg、ffprobe 和 Python Pillow。

设备录像从提交登录前开始。`me-timing.json` 记录「我的」导航标题和「我的帖子」行均可辨认的首帧、首次出现该账号名的帧及两者间隔。使用同设备的游客资料卡截图和无障碍标签已确认账号的截图匹配文字。两者同帧且后续未闪现游客文字才通过；慢速的模型调用和 UI 查询只用于操作或确认最终账号，不作为首屏计时。

### 退出后会话清理

`make e2e-case CASE=logout-session` 默认使用「NodeSeek E2E Profile」专用设备，也可在本机配置中指定 `logoutUDID`。脚本用启动参数临时显示「我的收藏」标签。测试账号需要已有收藏；设备为游客时复用官方表单和本机 `memberEnvFile` 登录。用例结束后这台设备保留游客状态。

先核对账号并打开真实收藏，转到「我的」确认退出，再返回同一个收藏标签。旧收藏行必须消失，重新从「我的」点收藏必须进入站点登录表单。冷启动复查「我的」、收藏和通知的游客状态，再用阅读模式核对侧栏。查看运行目录的 `junit.xml`、`report/logout-session.html` 与截图。

排查「提交登录后立刻关闭」可跑 `make xcode-test-class TEST="LoginWebViewControllerTests CurrentAccountStoreTests NodeSeekServiceTests"`。固定网页样本分别模拟后台刷新确认会员和游客，也覆盖退出前的列表请求晚到。真实设备日志中搜索「冷启动退出清理」和「Cookie 清理前」「Cookie 清理后」，可分别核对 URLSession、WebKit 中的 Cookie 名。

## 指定帖真实回帖与编辑

在阅读布局、已登录的 member 设备执行 `make e2e-comment`。用例固定使用 [1016685 号帖](https://www.nodeseek.com/post-1016685-1)。每次完整新跑会公开留下一条带唯一标记的评论，并编辑同一楼。

[回帖用例](scripts/comment.test.mjs) 从侧栏核对测试账号，经设置里的「详情测试」打开指定链接，确认加载的帖子 ID 后发送。冷启动重开帖子，读取自己的评论原文，匹配本轮标记后才保存修改。再次冷启动后，按同一楼层及评论 ID 读取修改后的原文，由 Midscene 验证详情画面。报告目录内的 `comment.json` 记录进度和楼层链接，`junit.xml` 记录断言结果。

若提交结果未知，保留 `.build/midscene/comment-1016685-<设备 UDID>.json`，在同一设备重跑该命令会按标记续验。若站点明确拒绝，先检查站点提示及发帖记录，人工确认未产生评论后再归档该状态文件、启动新一轮。

## 发帖草稿保存、恢复与放弃

运行 `make e2e-draft`，使用阅读布局的 member 模拟器。三条[草稿用例](scripts/draft.test.mjs)覆盖手动保存、提示已保存后立即重启，以及延迟两秒重启的对照。每条先核对侧栏账号和空白编辑器，再输入本轮唯一标题及含中文、换行的正文。若设备已有草稿，用例会在输入前停止，保留原稿。

| 场景 | 操作 | 验收 |
| --- | --- | --- |
| 手动保存 | 关闭 → 保存草稿并关闭 → 冷启动 → 打开发帖页 → 恢复 | 标题和每行正文与输入逐字相等，编辑器能显示恢复的内容 |
| 自动保存 | 在编辑器看到「已存本机」后直接重启进程 → 打开发帖页 → 恢复 | 用户没有点保存也能读回相同标题、正文和换行 |
| 自动保存对照 | 看到「已存本机」后停留两秒，再重启和恢复 | 与立即重启采用相同断言，用于区分保存提示时序和恢复流程故障 |
| 放弃本轮草稿 | 每条用例在确认恢复内容后选择「放弃草稿」，再冷启动 | 新编辑器的标题和正文为空，无恢复入口 |

用例仅操作本机草稿。`junit.xml` 记录各场景的结果，自动保存用例额外记录观察到提示至请求重启的间隔。恢复成功后保留 Midscene 报告和截图，失败时保留现场截图。

单独复现提示时序问题可运行 `make e2e-case CASE=draft-autosave`。若立即重启丢稿而两秒对照通过，记录为数据丢失风险，保留两组结果。

## 系统通知与常用功能

在仓库根目录运行整组，也可从 `make e2e-list` 选一个 ID 单跑。两组复用 member 模拟器和已有账号配置。

```sh
E2E_PROFILE=push make e2e-smoke
E2E_PROFILE=daily make e2e-smoke
make e2e-case CASE=push-cold
```

[系统推送脚本](scripts/push.test.mjs) 使用 `xcrun simctl push` 投递含唯一标题的回复通知，由本机 `axe` 点按 SpringBoard 上实际显示的通知。后台用例连续投递两条到同一楼层的新通知；冷启动用例先退出 App 进程。每次只点一次，核对帖子 1016685 的第 18 楼和正文标记，再只点一次返回，必须看见首页。报告目录中的 `*-notification.png`、`*-detail.png`、`*-returned.png` 分别记录这三步。若返回后仍显示同一楼，检查 SceneDelegate 和通知中心代理是否处理了同一次系统响应。模拟投递覆盖设备端展示、点按和 App 路由；生产 APNs 服务的投递需另行验证。

[常用功能脚本](scripts/daily.test.mjs) 中，`home-paging` 核对首页刷新、排序和第二页加载；`quote-cancel` 在固定评论取消引用并逐字读回自己的输入；`photo-return` 用帖子 703863 的配图验证大图返回；`last-page-filter` 检查只看楼主、恢复全部和末页导航；`inbox-reply` 从通知记录取得帖子及楼层，重开核对已读；`favorite-sync` 临时收藏帖子 1016685，从「我的收藏」重开并恢复初始状态。有站内通知时优先使用未读样本；全部已读时单独注明。无通知或固定帖已被用户收藏时，报告中的跳过项不计入通过数。

## TextKit 详情页分页

[分页与回弹的详细用例](../../../docs/testing/detail-textkit-pagination-e2e.md)列出逐步操作、触发时机、坐标容差和证据位置。`thread-pagination` 在 Texture 上跑同一短末页对照，`textkit-pagination` 验收新版连续分页、回弹与跳页，`textkit-backscroll` 从第三页普通 #21 回读第二页。`textkit-paging-timing` 使用 AXe 和受控 HTML 在指定模拟器上验证慢响应和失败重试；报告在 `.build/detail-paging-e2e/`，实站用例沿用 daily 的 JUnit 和截图。

## 后续发布回归功能点

按故障影响安排后续用例，表中的用例尚待实跑。

| 顺序 | 功能点 | 验收条件 |
| --- | --- | --- |
| 1 | 升级后会话与草稿保留 | 在上一发布版登录并保存草稿，覆盖安装候选版；首次打开「我的」仍是该账号，编辑器恢复原文 |
| 4 | 断网重试与重复提交 | 在可控网络环境验证读帖失败后恢复；回帖提交结果不明时先查原楼，核对恢复后只有一条带标记的评论 |
| 5 | 新主题发布 | 在约定的测试版块发布唯一标题和正文；从「我的帖子」重开同一帖并逐项核对 |

## 七条冒烟用例

| 用例与账号 | 操作路径 | 通过条件 |
| --- | --- | --- |
| `read-history` · 两种账号 | 首页 → 帖子详情 → 返回首页 → 最近浏览 → 第一条记录 | 列表和详情标题一致，楼主正文有文字或图片，最近浏览首条及重开的详情都指向刚读的帖子 |
| `category-comments` · 两种账号 | 首页「技术」→ 有回复的帖子 → 浏览评论 → 返回 | 至少一条回复同时具有内容和楼层或作者，返回后仍选中「技术」且帖子列表可见 |
| `search-navigation` · 两种账号 | 搜一搜 → 用户 → 帖子 → 输入「搬瓦工」→ 返回首页 | 两次切换分别选中对应范围，输入框读回完整中文，返回后首页列表可见 |
| `guest-login` · 游客 | 菜单 → 通知 → 登录 → 关闭登录网页 | 游客先看到登录提示，网页登录容器可打开，取消后通知页再次出现登录入口 |
| `member-search` · 已登录 | 核对菜单账号 → 搜一搜 → 提交一次「搬瓦工」→ 打开匹配帖 | 出现实际结果，目标标题含关键词，详情标题与列表一致，楼主正文可读。可用 `E2E_SEARCH_TERM` 换成已知有结果的标题关键词 |
| `member-compose` · 已登录 | 首页 → 原生发帖编辑器 → 原样退出 | 标题区、正文区、发布操作均可见，空白退出后回到首页。此用例仅覆盖发帖入口 |
| `member-comment-jump` · 已登录 | 账号侧栏 → 评论 → 帖子 1016685 的第 18 楼 → 返回 → 点分组标题「测试贴」→ 返回 | 点回复首次请求第 2 页，目标评论 ID、楼层及原文标记可见；点标题首次请求第 1 页并显示首楼，再返回同一评论列表 |

该跳转用例复用「缭雾」已发布的样本 `NS-f6b80106`（评论 ID `14299736`），可用 `make e2e-case CASE=member-comment-jump` 单跑。样本被站点移除时，先核对样本状态，再更新用例中的预期值。

游客轮预期执行 4 条、跳过 3 条；已登录轮预期执行 6 条、跳过 1 条。按用例核对两份报告，确认七条流程各自在适用账号下执行。真实登录由独立登录用例验收。真实回帖与编辑由指定帖专项用例验收。发布新主题和升级后数据保留仍需专项验证。

单独复验时按测试名称筛选。例如，针对游客通知和技术分类两项，在游客设备执行下一条命令。该运行只计入选中的用例。

```sh
NODE_OPTIONS='--test-name-pattern=游客进入通知|切换技术分类' make e2e-smoke
```

## 无人值守验收

1. 记录脚本打印的设备和本轮 `.build/midscene/<运行目录>`。用退出码和 `junit.xml` 核对结果。若提前中断，查看对应的 `app.log`、`wda.log` 或安装依赖时的 `npm.log`，报告中写明哪些用例还没执行。
2. 对失败项查看 `report/<用例 ID>.html` 和同一运行目录下的 `<用例 ID>-failure.png`，指出第一个与预期不同的界面。若在创建会话时收到 404 或超时，检查本轮 `log/webdriver-client.log` 的窗口尺寸请求；业务操作可能尚未开始，此时可以只有失败截图。搜索为空时核对账号、输入词和应用日志中的最终 URL、解析条数。游客搜索曾跳转 Google；游客输入成功仅证明导航和输入正常。
3. 汇报通过、失败和跳过数，列出未验证的关键流程，链接到本轮证据。启动崩溃、核心读帖持续不可用或数据丢失应阻断发布。环境或模型故障单列，修复后保留首次证据并复验。需要补查草稿、回帖提交或会话桥接逻辑时，可运行下列单测，并单列其结果。

```sh
make xcode-test-class TEST="NewDiscussionPresenterTests NodeSeekCommentSubmitterTests CookieBridgeTests" SIMULATOR_ID="$TEST_UDID"
```
