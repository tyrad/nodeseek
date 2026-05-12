# 特别关注关键词设计

## 目标
在设置页增加“特别关注”入口，用户可以维护本地关键词及颜色；首页帖子列表中标题或发帖人命中关键词时，用关键词颜色高亮对应文本。

## 范围
- 设置列表展示 `特别关注    n  >`，`n` 为本地关键词数量。
- 点击进入关键词列表，支持添加、编辑、删除关键词。
- 每个关键词包含 `keyword` 和 `colorHex`，默认颜色为红色。
- 用户可手动选择颜色。
- 支持导出 JSON、导入 JSON；导入只接受合法格式，同名关键词覆盖。
- 首页帖子列表标题和发帖人名称包含关键词时应用对应颜色。

## 架构
- 新增 `SpecialFollowKeywordStore` 负责 UserDefaults 持久化、JSON 导入导出、同名覆盖和通知变更。
- 新增 `SpecialFollowKeywordHighlighter` 负责大小写不敏感匹配和富文本着色。
- 设置页注入 store，新增 `specialFollow` section；入口 cell 从 store 读取数量。
- 新增 `SpecialFollowKeywordsViewController` 管理列表和编辑弹窗。
- `PostSummaryCellNode` 读取共享 store 的关键词规则，生成标题和 metadata 富文本时应用颜色。

## 数据格式
导出 JSON 为数组：

```json
[
  {
    "keyword": "NodeImage",
    "colorHex": "#FF3B30"
  }
]
```

导入要求：
- 顶层必须是数组。
- `keyword` 去除首尾空白后不能为空。
- `colorHex` 必须为 `#RRGGBB` 或 `#RRGGBBAA`。
- 同名关键词按大小写不敏感覆盖，保留导入项颜色。

## 测试
- Store 测试持久化、无效 JSON 拒绝、同名覆盖、默认红色。
- Highlighter 测试标题和作者命中颜色。
- 设置页测试入口展示数量并能 push 列表。
- 列表测试新增/编辑/删除后更新 store。
