# 热榜设计

对应 Issue：[tyrad/nodeseek#21](https://github.com/tyrad/nodeseek/issues/21)。设计稿：[NS Connect 热榜设计稿](https://claude.ai/artifact/9q7hXq3H2QuMFe63FfsYnD)（私有链接，需在页面分享菜单开放后他人才能打开）。

## 目标与范围

在 App 内查看社区热榜（实时榜 / 日榜 / 周榜），点条目打开原生帖子详情。

- **做**：三种榜单切换、下拉刷新、加载/空榜/失败状态、失败时保留旧数据、热榜设置页（查看数据来源、编辑三个接口地址、恢复默认）、三个入口。
- **不做**：排名变化（需本地存历史快照，口径不稳）、自建代理、定时自动刷新。

## 已核实的数据契约

来源：[NodeSeek 热榜插件](https://greasyfork.org/zh-CN/scripts/560065)（MIT，作者 NodeSeek 用户 space/10539）使用的第三方接口，不是 NodeSeek 官方接口。2026-11-24 实测：

| 榜单 | 默认地址 | 条数 | 覆盖时间 | Cache-Control |
|---|---|---|---|---|
| 实时 | `https://api.bimg.eu.org/hot.json` | 30 | 约 2 小时 | `max-age=60` |
| 日榜 | `https://api.bimg.eu.org/daily.json` | 50 | 约 24 小时 | `max-age=300` |
| 周榜 | `https://api.bimg.eu.org/weekly.json` | 100 | 约 7 天 | `max-age=600` |

```json
{
  "updated_at": 1795508253,
  "posts": [
    {
      "post": {
        "id": 1076818, "title": "…", "author": "…", "author_id": 73375,
        "post_timestamp": 1795507488, "views": 1002, "comments": 45,
        "summary": "…", "category": "trade"
      },
      "score": 522.91
    }
  ]
}
```

- 时间为 Unix 秒。`posts` 已按 `score` 降序。`summary` 偶有空字符串。`category` 为网页板块 slug，与 `DiscussionCategory` 一致。
- Cloudflare 托管，`access-control-allow-origin: *`。插件每 60 秒请求一次并加 `?t=` 绕过缓存；App 不加，直接利用 CDN 缓存。
- 头像不在接口里，按站内规则 `/avatar/<author_id>.png` 拼接，用现有 `AvatarImageLoader` 加载（命令行直接请求返回 403，需走 App 已有的头像请求方式）。

## 方案

### 数据层（SharedCore，SwiftPM 可测）

- `HotListKind`：`realtime` / `daily` / `weekly`，带默认地址和统计范围文案。
- `HotListResponse` / `HotListEntry`：容错解码，单条缺必要字段（id、title）时跳过该条，不让整份榜单失败；可选字段缺失给默认值。
- `HotListEntry` 转 `PostSummary`：帖子地址 `/post-<id>-1`，头像 `/avatar/<author_id>.png`，作者主页 `/space/<author_id>`。
- 真实响应样本放 `nodeseekTests/Fixtures/hot-list-*.json`。

### 网络与缓存（AppRuntime）

- `HotListProviding` 协议，默认实现 `RemoteHotListProvider`：URLSession，超时 8 秒。
- 内存缓存按榜单分别保存，有效期跟服务端一致（60 / 300 / 600 秒）；有效期内切换榜单不发请求。下拉刷新距上次请求不足 15 秒时直接用缓存。
- 请求失败但有旧数据时继续显示旧数据，弹出「更新失败」提示并可重试。
- `HotListSourceSettings`（UserDefaults）：保存三个自定义地址；为空表示用默认地址。地址变化后清空缓存。

### 页面（Features/HotList）

- `HotListViewController`：顶部轻量 tab 切换三种榜单；tab 下灰色说明条显示统计范围、条数和更新时间；列表每行为「排名｜标题（两行）＋信息行（16pt 头像、作者、分类、发帖时间、浏览、回复、热度）」。前三名排名放大加粗，只用黑白灰。右上角为设置按钮，刷新靠下拉。
- `HotListSettingsViewController`：数据来源（提供方、上次更新、查看插件主页）、三个接口地址可编辑、恢复默认地址。保存前先请求一次校验格式，失败不保存并提示。
- 文案放 `HotList.strings`，补齐 zh-Hans / zh-Hant / en。支持暗黑模式与动态字号。

### 入口

- 侧边栏：「最近浏览」下方加「热榜」。
- 多 Tab「我的」：「我的内容」第二组，签到、最近浏览之后加「热榜」。
- 可选 Tab：新增 `MainTabItem.hot`，默认不在底栏，用户可在自定义底栏中添加。

## 风险

- 第三方接口无 SLA，可能失效或变更格式：容错解码、保留旧数据、允许用户改地址。
- 热度算法不公开，App 只展示，不解释算法。

## 验证

- `make spm-test`：解码、容错与 `PostSummary` 转换。
- `make xcode-test-class`：缓存与刷新节流、设置存储、页面状态。
- 模拟器手动验证：三种榜单切换、点开详情、下拉刷新、断网失败、改地址与恢复默认、暗黑模式、大字号。
