# 删除 Texture 详情列表

依据：[2026-11-24 最终评估](../performance/detail-textkit-vs-texture-2026-11-24.md)。目标是详情页只保留 UICollectionView + TextKit，行为与当前默认（TextKit）一致。

## 范围

删除：
- 开关 `postDetail.useTextKitList`、调试页开关及三语 `use-list` 文案；`PostDetailViewController` 的 `usesTextKitList` 参数，`collectionList` 改为非可选。
- 只服务旧列表的 4 个节点：`PostDetailSkeletonCellNode`、`PostDetailEntryHintCellNode`、`PostDetailAuthorFilterBannerCellNode`、`PostRepliesDividerCellNode`。
- `tableNode` 及数据源/批量加载、行重载调度、首屏遮罩等待、评论预渲染缓存，以及 ViewProtocol / AuthorFilter / PageJump / Web 中 `collectionList == nil` 的分支（约 1,350 行）。
- 只测旧列表的测试（约 1,300 行）、`thread-pagination` E2E、`scripts/compare-detail-lists.py`；`DetailBaselineTests` 与 `DetailCollectionBaselineTests` 合并为一个。

保留：
- DTCoreText 渲染器（新版兜底、签名退回）。
- Texture 依赖：个人主页内容列表、发帖预览、楼层预览仍在用；`PostBodyCellNode`、`CommentCellNode` 及正文块节点随之保留。
- 新版借用的类型：`PostDetailContentLayout`、`DetailQuoteLayout`、各 `*View` / `*Layout`、`reactionCountText`、风险提示文案。

## 风险

- `availableHeaderContentWidth` / `availableCommentContentWidth` 读 `tableNode` 宽度，新版打开楼层预览时会间接建出 tableNode；改为读 `detailScrollView`。
- 约 75 处测试默认构造的是 Texture，删参数后改跑 TextKit，需要逐个回归；不再适用的改写或删除。
- 热评楼层匹配（`+Web.swift:180`）两版逻辑不同，保留新版。

## 步骤与提交

1. 控制器与开关：删旧分支和 tableNode，修宽度来源，删调试开关和文案。
2. 删除 4 个旧节点文件。
3. 测试：删除或改写旧版用例，合并基线测试，清理 `usesTextKitList:` 参数。
4. E2E 与脚本：删 `thread-pagination` 及对比脚本，更新相关文档。

每步单独提交，均需编译通过。

## 验证

- `make xcode-test-class` 跑详情相关测试类：PostDetailViewControllerTests、DetailCollectionTests、DetailFloorAnchorTests、DetailEntryHintTests、DetailPagingGestureTests、MagicTabIntegrationTests、DetailUnavailablePostTests、基线测试。
- E2E：textkit-pagination、textkit-backscroll、textkit-paging-timing、last-page-filter。
- 模拟器手动看楼层预览、只看 TA、页码跳转、锚点高亮。

后续（不在本次范围）：发帖预览和楼层预览迁到 TextKit 后，可再删约 3,500 行正文节点。
