# 2026-11-18 模拟器体验测试问题清单（TDD）

来源：2026-11-18 在 iPhone 17 Pro 模拟器（iOS 26.5）上的体验测试，完整报告与截图见 Notion「NS App优化 / 模拟器体验测试报告 2026-11-18」。

做法：每个问题先写一个**当前会失败**的测试（红），修复时让它变绿，不改测试的期望。失败测试统一放在 `nodeseekTests/UXAudit/`，类名、方法名带问题编号，方便对照。

优先级：
- **P0**：功能错误或让用户卡住、误操作。
- **P1**：明显影响体验或信息错误。
- **P2**：一致性、视觉细节。

| 编号 | 优先级 | 问题 | 测试 |
| --- | --- | --- | --- |
| U01 | P0 | 评论正文最后一行的链接被签名链接抢点击（点 #0 打开了签名里的帖子） | `PostDetailUXAuditTests.test_U01_bodyLastLineLinkCenterTapResolvesToBodyURL`<br>`PostDetailUXAuditTests.test_U01_signatureHitAreaDoesNotCoverBodyLastLinePlainText`（已修复） |
| U02 | P0 | 未授权 NodeImage 时授权页堆满十几个「加载API密钥失败」提示 | `AppUXAuditTests.test_U02_nodeImageExtractionDoesNotClickAPIButtonInsidePollingTimer`<br>`AppUXAuditTests.test_U02_nodeImageClicksAPIButtonOnceAfterSignInAndReturnsKey`（已修复，模拟器真实授权通过） |
| U03 | P0 | 「每日签到」网页已加载完，但一直白屏 + 转圈，要滑一下才显示 | `AppUXAuditTests.test_U03_webPageStopsSpinnerOnceNavigationCommits` |
| U04 | P0 | 详情页浮动「评论」按钮盖住评论行的操作按钮（编辑 / 引用） | 不修：浮动评论按钮支持拖拽，用户可自行移开；已删除对应测试 |
| U05 | P0 | 拼音组字中点评论框外部，评论框收起、组字被打断 | 不修：点外部收起以用户意图为准，组合文字由系统上屏；已删除对应测试 |
| U06 | P0 | 私信列表的系统通知预览显示 Markdown 原文 | 不修：与网页一致，网页私信预览同样显示原文；已删除对应测试 |
| U07 | P1 | 首页相对时间（「2s ago」）不会随时间刷新 | `AppUXAuditTests.test_U07_postSummaryKeepsAbsoluteLastActivityDate` |
| U08 | P1 | 详情页评论相对时间不会刷新 | `PostDetailUXAuditTests.test_U08_commentCarriesAbsoluteCreatedDate` |
| U09 | P1 | 浅色模式看大图时状态栏是深色字，黑底上看不见 | `PostDetailUXAuditTests.test_U09_photoBrowserUsesLightStatusBarInLightMode` |
| U10 | P1 | 表情面板展开时，面板下方露出后面的内容 | 不修：表情面板下方留白属预期行为；已删除对应测试 |
| U11 | P1 | 发帖按钮被滑动隐藏后，切换分类它仍保持隐藏 | `AppUXAuditTests.test_U11_composeButtonReappearsAfterSwitchingCategory`（已修复：切换分类后发帖按钮重新出现） |
| U12 | P1 | 「我的」页发帖上限 0/4 与个人主页 0/20 不一致 | `AppUXAuditTests.test_U12_mePageAndProfileShowSamePostLimit` |
| U13 | P1 | 特别关注说明写「右滑删除」，实际是左滑 | `AppUXAuditTests.test_U13_specialFollowFooterSaysSwipeToDelete`（已修复：文案改为滑动删除） |
| U14 | P1 | App 内字号 +8 时首页元信息行的时间被截断 | 不修。保留首页元信息的单行布局。 |
| U15 | P1 | 回复成功后停在原位，看不到自己刚发的评论 | 不修：回复后停在原位属预期行为；已删除对应测试 |
| U16 | P1 | 表情面板打开时点输入框，面板不收起，与键盘同时出现 | 不修：表情面板与键盘同时显示属预期行为；已删除对应测试 |
| U17 | P1 | 「发帖时间优先」排序下仍显示最后回复时间，看起来没排好 | 不修：「发帖时间优先」下显示最后回复时间属预期行为（列表 HTML 也只有最后回复时间）；未写测试 |
| U18 | P1 | 错误提示（如「更多评论加载失败」）也带绿色成功勾 | `PostDetailUXAuditTests.test_U18_loadMoreFailureDoesNotUseSuccessToast`（已修复：失败提示改用橙色警示图标） |
| U19 | P1 | 自己的帖子和评论仍显示点赞 / 鸡腿 / 反对按钮，点了才报错 | `PostDetailUXAuditTests.test_U19_ownContentHidesSelfVoteButtons`（已修复：自己的内容计数为 0 的投票按钮不显示，已有计数只显示数字不可点） |
| U20 | P1 | 评论框内容为空时「发送」仍可点，点了弹错误框 | 不修：空内容点「发送」给出提示属预期行为；已删除对应测试 |
| U21 | P1 | 引用多行评论时换行被压成一行 | `PostDetailComposerUXAuditTests.test_U21_quotePreservesLineBreaks`（已修复：与网页一致，引用正文取页面配置里的原始 Markdown 逐行加 `> `，编辑过带编辑时间，楼层链接指向楼层所在页；不解析 HTML，拿不到原文时只保留标题行） |
| U22 | P1 | 引用纯表情 / 图片评论时引用块没有内容 | `PostDetailComposerUXAuditTests.test_U22_quoteOfImageOnlyCommentCarriesSourceMarkdown`（已修复：随 U21 改为引用原文，图片和表情以原文 `![](…)`、`:xhj001:` 带入引用块，与网页一致，不另加占位文字） |
| U23 | P1 | 「我的评论」点评论文字只打开帖子顶部，不跳到对应楼层 | `AppUXAuditTests.test_U23_userCommentRowTapOpensCommentFloor`（已修复：点回复文字整行跳到对应楼层，点标题仍打开帖子开头） |
| U24 | P1 | 楼层跳转后没有高亮，看不出跳到了哪一层 | 不修：跳转后已有整行闪烁高亮，保持现有颜色和时长；未写测试 |
| U25 | P1 | 「在浏览器打开」在第 2 页时打开的是第 1 页 | 不修：「在浏览器打开」沿用进入时的页码，属预期行为；已删除对应测试 |
| U26 | P1 | 暗黑模式看大图时图片仍被「图片变暗」压暗 | `PostDetailUXAuditTests.test_U26_photoPreviewIsNotDimmedInDarkMode`（不修：大图沿用图片变暗设置，属预期行为） |
| U27 | P1 | 系统 Dynamic Type 调大后首页 / 详情字号不变 | `AppUXAuditTests.test_U27_typographyScalesWithSystemDynamicType` |
| U28 | P2 | 「回复楼主」输入框头部显示「回复 缭雾 #0」 | 不修：回复楼主沿用网页做法，正文为 `@作者 [#0](…)`，输入框头部显示「回复 作者 #0」与之对应；已删除对应测试 |
| U29 | P2 | 多页帖子的热评和正常楼层重复出现，没有分区标题 | 不修。沿用网页做法，热评提前展示并用楼号旁的火焰标识，原楼层保留。 |
| U30 | P2 | 0 条评论的帖子下方空白，没有空状态提示 | 不修。帖子正常加载且没有回复时，正文下方自然留白。 |
| U31 | P2 | 编辑评论的草稿条写「无标题」 | 不修：草稿条沿用通用格式显示「无标题」，属预期行为；已删除对应测试 |
| U32 | P2 | 自己评论的长按菜单里有「投放鸡腿」 | `PostDetailUXAuditTests.test_U32_ownCommentContextMenuHasNoChickenLeg`（已修复） |
| U33 | P2 | 「我的」页点「粉丝」进入个人主页而不是粉丝列表 | `AppUXAuditTests.test_U33_meFansStatOpensFollowersList`（已修复：鸡腿、星辰、粉丝、关注均可直接打开对应明细） |
| U34 | P2 | 「添加探针」填了内容点关闭不确认 | `AppUXAuditTests.test_U34_probeEditorAsksBeforeDiscardingTypedAddress` |
| U35 | P2 | 侧边栏菜单文字左边缘不齐（73~80pt） | `AppUXAuditTests.test_U35_sideMenuRowTitlesShareLeadingEdge`（已修复：菜单图标统一画进 28pt 宽画布居中，各行文字左边缘对齐） |
| U36 | P2 | 搜索结果不高亮关键词 | `AppUXAuditTests.test_U36_searchResultTitleHighlightsKeyword` |
| U37 | P2 | 搜索切到「用户」tab 时不自动用已有关键字搜索 | `AppUXAuditTests.test_U37_switchingToUserScopeSearchesExistingKeyword`（已修复：从「帖子」切到「用户」时自动搜索已提交的同一关键词） |
| U38 | P2 | 通知只显示帖子标题，看不到对方说了什么 | 不修。「@我」和「回复主题」通知继续只显示帖子标题。现有接口不返回评论正文，展示摘要需逐条请求。 |
| U39 | P2 | 收藏后帖子操作栏图标整体左移（布局跳动） | `PostDetailUXAuditTests.test_U39_postActionRowStaysStableWhenFavoriteCountAppears` |
| U40 | P2 | 字号滑块、复制面板「复制」按钮使用系统蓝，不符合黑白主题 | `AppUXAuditTests.test_U40_textSizeSliderUsesMonochromeTint`<br>`PostDetailUXAuditTests.test_U40_copySheetPrimaryButtonIsNotSystemBlue`（已修复：滑块已选轨道与复制按钮改用 .label 反色） |
| U41 | P2 | 暗黑模式下表情面板的表情是刺眼白底 | `PostDetailComposerUXAuditTests.test_U41_stickerCellsAreDimmedInDarkMode`（不修：白底来自表情图片本身，非界面问题） |
| U42 | P2 | 全 App 时间格式不统一（「2s ago」/「2分钟前」/「刚刚」/ 绝对时间） | `AppUXAuditTests.test_U42_listTimeUsesLocalizedRelativeFormat` |

以下问题只能靠真机或人工验证，没写自动化测试：签到网页首屏不绘制的根因、私信网页对话不停在最新消息、断网 / 弱网、长按与双击看大图。

## 运行与状态

```bash
make xcode-test-class TEST="PostDetailUXAuditTests PostDetailComposerUXAuditTests AppUXAuditTests"
```

2026-11-19 全量运行：40 个测试全部失败（红），失败原因均为断言，不是崩溃。U17、U24、U38 不写测试，原因见上表。

修复时注意：
- U40 的复制按钮修复会让现有 `ReplyAuthorContextMenuTests.copySheetPrimaryButtonUsesDarkModeFriendlyColor`（断言 `.systemBlue`）失败，需一并改。
- U03 要求在 `didCommit` 时停止转圈，只加超时兜底仍是红；首屏不绘制的根因不在测试范围。
- U18 要求错误走独立方法；若新方法默认回落到 `showToast`，测试仍红。
- U42 依赖 U07（列表先要有绝对时间）。
