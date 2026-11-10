# 服务器探针桌面小组件

对应 issue：https://github.com/tyrad/nodeseek/issues/6

## 目标与范围

在 iPhone 主屏用 WidgetKit 小组件查看用户自建探针（Komari、哪吒 V2）上服务器的状态。主 App 仍是 UIKit/Texture，小组件扩展用 SwiftUI。凭证和快照只保存在本机，不经过开发者的服务。

- **第一阶段（已实现）**：内置 Komari 与极简探针两份 JSON 配置 + 通用引擎，App 内探针页面（列表、详情、添加探针），不做小组件。
- **P0**：只做 Komari 公开节点。主 App 设置页加探针管理；小组件做两种：小尺寸单台、中尺寸多台汇总。
- **P1**：哪吒 V2（PAT）、中尺寸单台详情、锁屏组件、iOS 17 AppIntent 配置、趋势图。
- **不做**：控制台、SSH、执行命令、服务端中转、秒级实时刷新。

## 已核实的数据契约

### Komari（游客，无凭证）

来源：Komari 1.6.1 源码 `web/rpc/jsonrpc/common.go` 和官方 API 文档。已用自建测试面板的真实响应核对。

- 节点静态信息：`GET /api/nodes` → `data: Client[]`。
  - 隐藏节点由服务端去掉；游客拿到的 `ipv4`/`ipv6`、备注、token 都是空的。
  - 用到的字段：`uuid`、`name`、`region`、`group`、`weight`、`os`、`cpu_cores`、`mem_total`、`disk_total`、`traffic_limit`、`expired_at`。
- 最新状态：`POST /api/rpc2`，body 为 `{"jsonrpc":"2.0","method":"common:getNodesLatestStatus","params":{"uuids":[...]},"id":1}`。
  - 返回 `result: { [uuid]: Status }`。省略 `params` 时返回全部可见节点。
  - Status 字段：
    - `online` (Bool)、`time`（采样时间，ISO 8601，带纳秒）
    - `cpu` (%)、`ram`/`ram_total`、`swap`/`swap_total`、`disk`/`disk_total`（字节）
    - `net_in`/`net_out`（B/s）、`net_total_up`/`net_total_down`（字节）
    - `load`/`load5`/`load15`、`uptime`（秒）、`process`、`connections`、`ping`
- 一次刷新固定 2 个请求，不随节点数增长。静态信息可以缓存一天，按需刷新。
- **回退**：面板不支持 rpc2（返回 404 或 method not found）时，改用 `GET /api/recent/:uuid` 逐个请求，最多请求 6 台。
- **私有站点**：面板开启 `private_site` 后，游客请求返回 `{"status":"error","message":"Private site is enabled..."}`，App 显示"站点为私有，暂不支持"。`GET /api/public` 能提前看出站点是否私有。
- **最新状态只存在面板内存里**：面板重启后，节点可能没有出现在 result 里，这种情况按"暂无数据"处理，不当作离线。
- 真实样例（2026-11-10，测试面板，已去掉 IP）：

```json
{"online":true,"time":"2026-11-10T05:53:54.21283744Z","cpu":0.417,"ram":415117312,"ram_total":4115853312,
 "disk":9017148928,"disk_total":32061511680,"net_in":47117,"net_out":46496,"load":0.11,"uptime":5679170}
```

### Komari 实测结论（2026-11-10，测试面板 HK-01 / SG-01）

| 场景 | 实测行为 | App 处理 |
|---|---|---|
| 正常 | 批量接口返回全部节点；`time` 带 9 位纳秒；agent 约每 3.5 秒上报一次 | 解析时把小数截到毫秒 |
| agent 停止 | 约 **37 秒**后 `online` 才变为 false；`time` 和各项指标保留最后一次上报的值 | 显示"离线 · 最后上报 X 前"；离线时的指标只能当作历史值 |
| 节点隐藏 | 从 `/api/nodes` 和批量结果中消失；`uuids` 指定该节点时返回空对象；`/api/recent` 返回误导性的 `"UUID is required"` | 当作节点不存在，提示用户重新选择节点 |
| 私有站点 | `/api/nodes`、rpc2、`/api/recent` 全部返回 **HTTP 401 + REST 风格错误体**（rpc2 也不返回 JSON-RPC 错误）；`/api/public` 和 `/api/version` 仍可访问，`private_site: true` | `privateSite` 错误；添加探针时先查 `/api/public` |
| 面板重启 | 刚重启时批量结果为空；在线节点几秒内重新出现；**离线节点不再出现，但仍在节点列表中** | `ProbeAvailability.unknown`，显示"暂无数据" |
| 面板进程停止 | nginx 返回 502 HTML | `unreachable`，继续显示缓存 |
| 未知 RPC 方法 | JSON-RPC 错误 `-32041 Permission denied` | `unauthorized` |
| 指定 uuid 不存在 | JSON-RPC 错误 `-32602 Node not found` | `nodeNotFound` |

- `/api/recent/:uuid` 的结构和文档里的 Record 不一样：是嵌套的 `cpu.usage`、`ram.used/total`、`network.up/down/totalUp/totalDown`、`updated_at`，**没有 online 字段**；只保留约 1 分钟的数据（17 条），按时间升序。
- 游客拿到的节点信息**不含** `ipv4`/`ipv6` 字段。`region` 是国旗 emoji，可以直接显示。
- `swap_total`、`traffic_limit` 为 0 表示未提供，按缺失处理。

对应代码：`SharedCore/Domain/ProbeModels.swift`、`SharedCore/Parsing/KomariProbeDecoder.swift`、`SharedCore/HTTP/KomariProbeRequests.swift`。测试用例 `KomariProbeDecoderTests` 基于真实响应（`nodeseekTests/Fixtures/komari-*.json`，UUID 已替换为假值）。

### 极简探针 monitor（游客，无凭证）

来源：`monitor-probe/monitor` 的公开节点视图（`src/api.rs`），以及官方主题 `monitor-theme-default` 的 `Node`、`Metrics`、`Point`（`src/lib/api.ts`、`src/components/NodeDetail.tsx`、`src/lib/format.ts`）。

- 列表和最新状态都是 `GET /api/nodes`，返回 `{ "nodes": [Node] }`。匿名只能看到公开节点，响应里没有 ip、hostname、remark。
- `online` 是布尔值，以它为准。离线或刚连上、还没有上报时 `metrics` 为 null：状态仍按 `online` 显示，指标用“—”，不把缺指标当成离线。
- 采样时间用 `last_seen`（Unix 秒）。`last_seen_ago` 是 hub 自己时钟上的秒数，不拿来当采样时间。
- 内存、磁盘、流量总量是字节；`net_rx` / `net_tx` 是 B/s。主题按 1024 进位显示，配置里不再乘系数。
- `country` 是 ISO 两位代码。`load` 是三项数组。`tcp` 与 `udp` 相加作为连接数。
- 历史：`GET /api/nodes/{id}/metrics?hours={hours}&series=metrics`。返回 `{ "metrics": [{ "ts", "cpu", "mem_used", "disk_used", "net_rx", "net_tx" }] }`，`ts` 是 Unix 秒。不传 `points` 时 hub 最多返回 1440 个点。历史点没有内存总量。
- 公开页关闭时返回 HTTP 401，正文是「需要登录后查看」，归类为拒绝访问。匿名的 `/api/me` 不提供 hub 版本，连接成功只显示服务器数量。
- 不接 WebSocket，刷新沿用现有轮询。

内置配置：`nodeseek/Resources/ProbeAdapters/probe-adapter-monitor.json`。添加探针时可以在 Komari 和极简探针之间选择。

### 哪吒 V2（P1，PAT）

来源：nezhahq/nezha `cmd/dashboard/controller/controller.go`、`model/server.go`、`model/host.go`。

- `GET /api/v1/server` 挂在 `auth` 路由组下，**必须认证**。游客只能连 WebSocket `/api/v1/ws/server`，不适合在小组件里用。
- PAT 用 `Authorization: Bearer nzp_...`，scope **只需要 `nezha:inventory:read`**，建议同时限制 server_ids。`nezha:server:read` 只在调 `/server/:id/metrics` 历史接口时才需要。
- 响应 `{"success":true,"data":[Server]}`：
  - `Server`：`id`、`name`、`public_note`、`display_index`、`last_active`、`geoip`、`host`、`state`
  - `host`：`mem_total`、`disk_total`、`swap_total`、`platform`、`cpu[]`、`arch`、`boot_time`
  - `state`：`cpu`、`mem_used`、`disk_used`、`swap_used`、`net_in_speed`/`net_out_speed`、`net_in_transfer`/`net_out_transfer`、`uptime`、`load_1/5/15`、`tcp_conn_count`、`temperatures`、`gpu`
  - 这些字段都带 `omitempty`，值为 0 时整个字段不出现，所以解码时缺字段要按 0 处理，不能报错。
- 接口没有 online 字段，按 `now - last_active < 60s` 判定在线。

## 统一模型（SharedCore/Domain/ProbeModels.swift）

只依赖 Foundation，可以用 SwiftPM 跑单测。

```swift
enum ProbeProviderKind: String, Codable { case komari, nezhaV2 }

struct ProbeInstance: Codable {          // 存 App Group，不含凭证
    let id: UUID
    var name: String
    var baseURL: URL                     // 只允许 https
    var kind: ProbeProviderKind
    var selectedServerIDs: [String]      // 有序，第一个是小尺寸默认展示的服务器
}

struct ProbeServerSnapshot: Codable {
    let serverID: String
    var displayName: String              // 用户可以改成别名，默认不暴露真实备注
    var region: String?
    var online: Bool?                    // nil 表示没有拿到数据
    var cpuPercent: Double?
    var memUsed: Int64?, memTotal: Int64?
    var diskUsed: Int64?, diskTotal: Int64?
    var netInRate: Int64?, netOutRate: Int64?
    var load1: Double?, uptime: Int64?
    var sampledAt: Date?                 // 探针那边的采样时间
}

struct ProbeInstanceSnapshot: Codable {
    let instanceID: UUID
    var servers: [ProbeServerSnapshot]
    var fetchedAt: Date                  // 最后一次成功拉取的时间
    var lastError: ProbeFetchError?      // 最后一次失败的原因，脱敏后保存
    var lastAttemptAt: Date
}

enum ProbeFetchError: String, Codable {
    case network, timeout, unauthorized, privateSite, unsupported, decoding
}
```

所有指标都用 Optional，拿不到时显示"—"，不显示成 0%。

## 分层（第一阶段已实现）

第一阶段只做 App 内的探针页面，不做小组件。探针接入用“声明式适配器配置 + 通用引擎”：每种探针是一份 JSON 配置（只是数据，不是代码），引擎按配置发请求、取字段、判断在线状态。目前内置 Komari 和极简探针，以后接入新探针时优先只加配置。

| 位置 | 内容 |
|---|---|
| `SharedCore/Domain/ProbeModels.swift` | 统一模型：`ProbeNode`、`ProbeMetrics`、`ProbeStatus`、`ProbeHistoryPoint`、`ProbeInstance`、`ProbeServer`、`ProbeFetchError` |
| `SharedCore/Probe/ProbeAdapterSpec.swift` | 适配器配置格式（请求模板、字段映射、在线规则、错误规则） |
| `SharedCore/Probe/ProbeJSONPath.swift` | 配置里用的 JSON 路径子集：`$`、`.key`、`[n]`、`[*]`、`.*` |
| `SharedCore/Probe/ProbeAdapterEngine.swift` | 校验配置、构造请求、解析节点 / 状态 / 历史、错误分类 |
| `SharedCore/Probe/ProbeServerList.swift` | 列表的筛选、排序、分组、汇总和数字格式化 |
| `Resources/ProbeAdapters/probe-adapter-komari.json` | 内置 Komari 配置 |
| `Resources/ProbeAdapters/probe-adapter-monitor.json` | 内置极简探针配置 |
| `AppRuntime/Services/Probe/ProbeService.swift` | 适配器注册表；独立 ephemeral URLSession（无 Cookie、无缓存、只允许同域 https 重定向、响应上限 8MB）；节点 10 分钟缓存、历史 2 分钟缓存 |
| `AppRuntime/Storage/ProbeInstanceStore.swift` | 探针配置和最后一次快照（UserDefaults，不存凭证） |
| `Features/Probe/` | 列表、详情、添加 / 编辑探针页面。入口不在设置里：多 Tab 模式在「我的」单独一组，阅读模式在侧栏，都叫「探针」 |

### 适配器配置格式

```jsonc
{
  "id": "komari", "name": "Komari", "specVersion": 1,
  "auth": { "type": "none" },              // 或 { "type": "header", "header": "Authorization", "prefix": "Bearer " }
  "requests": {                            // 只能写相对路径，请求只发往用户填写的面板域名
    "nodes":  { "method": "GET",  "path": "/api/nodes" },
    "latest": { "method": "POST", "path": "/api/rpc2", "body": { "method": "common:getNodesLatestStatus" } },
    "history":{ "method": "GET",  "path": "/api/records/load", "query": { "uuid": "{nodeID}", "hours": "{hours}" } }
  },
  "preflight": [ { "request": "public", "path": "$.data.private_site", "equals": true, "error": "privateSite" } ],
  "nodes":  { "request": "nodes",  "items": "$.data[*]",  "fields": { "id": "$.uuid", "name": "$.name" } },
  "status": { "request": "latest", "items": "$.result.*", "online": { "type": "bool", "path": "$.online" },
              "fields": { "cpuPercent": "$.cpu.usage", "sampledAt": { "path": "$.time", "format": "iso8601" } } },
  "errors": [ { "status": 401, "bodyContains": "Private site", "error": "privateSite" } ]
}
```

- 在线规则支持 `type: bool`（面板给出在线字段）和 `type: freshness`（最后上报时间距今不超过 N 秒，用于哪吒）。
- 字段支持 `sum`（多个字段相加，任一缺失则为空）、`scale`、`format`（number / string / iso8601 / unixSeconds / unixMillis）。
- 安全约束：路径必须以 `/` 开头、不含 `..` 和 `//`、只允许 ASCII 字母数字和 `/-_.{}`；占位符只有 `{nodeID}`、`{hours}`、`{nodeIDs}` 且会编码；构造出的请求必须与面板地址同 scheme / host / port；凭证只放进配置声明的请求头。App Store 审核 2.5.2 要求配置只能是数据，不能执行代码。
- 远程目录下载、用户导入配置放到后续阶段。

### 页面

- **列表**：一个探针一张反色汇总卡（名称、在线数、网速、离线 / 告警徽标、该探针自己的网速趋势），卡片占满这一行。多个探针时按页横向滑动，一页一张，卡片下有圆点；页落定后，筛选计数和服务器列表只显示这一页。只有一个探针时不滚动、不显示圆点。筛选胶囊（全部 / 离线 / 告警）、排序菜单（默认异常优先）、搜索；同一探针内按面板分组，可折叠；当前探针超过 8 台默认紧凑模式，可手动切换。卡片模式的 CPU 趋势线只为可见行请求最近 1 小时历史。页面可见时每 10 秒刷新，下拉刷新会重新拉节点列表。
- **数据状态**：请求失败或超过 90 秒没刷新成功的数据显示为“缓存”（虚线边框、灰色，不计入告警和网速）；离线显示最后上报时间，趋势线在离线点截断；面板重启后缺状态的节点显示“暂无数据”。
- **详情**：CPU 曲线（1H / 6H / 24H，纵轴按峰值取 5/10/25/50/100 档）、内存 / 硬盘 / 网络 / 负载四宫格、运行时间 / 进程 / 连接 / 交换。
- **添加 / 编辑**：填写地址后自动测试连接，成功后才能保存；可隐藏节点、拖动排序；长按列表行或详情页菜单可重命名（只改本机显示）。

小组件阶段再把 `ProbeInstanceStore` 换成 App Group 的 UserDefaults，并把 SharedCore 的探针文件和 `ProbeService` 编进小组件扩展。

## 刷新与缓存

1. TimelineProvider 先读缓存，有缓存就立即返回一条 entry；然后发请求，用 async 的 `getTimeline`，整体超时 10s。
2. 请求成功：写入快照，`fetchedAt = now`，生成两条 entry：
   - `now`：正常样式；
   - `fetchedAt + 45min`：切换为过期样式，这样即使系统一直不刷新，旧数据也不会一直显示成正常。
3. 请求失败：保留旧快照，记下 `lastError`，生成同样两条 entry，显示过期样式和错误类型。
4. 刷新策略统一用 `.after(now + 20min)`，失败时也一样；不用 `.atEnd`。系统会自行决定实际的刷新时间。
5. 主 App 回到前台，或者配置变更后，调用 `WidgetCenter.shared.reloadAllTimelines()`。
6. 删除实例时，同时删除它的快照和 Keychain 条目。

## 显示状态（ProbeDisplayState）

| 状态 | 判定 | 显示 |
|---|---|---|
| 未配置 | 没有实例，或者没选节点 | "添加探针"引导，点按进入设置页 |
| 正常 | 快照不超过 45 分钟，`online == true` | 绿点，加 `Text(sampledAt, style: .relative)` |
| 离线 | `online == false`，或者哪吒的 `last_active` 超过 60s | 红点，"离线 · 最后上报 X 前" |
| 暂无数据 | 节点不在最新状态的结果里 | 灰色"暂无数据"，不显示状态点 |
| 过期 | 快照超过 45 分钟，或者最近一次请求失败 | 用 `.secondary` 色显示旧数据，不显示状态点，加 `clock.arrow.circlepath` 和"缓存 · X 前" |
| 需要授权 | 401/403 或私有站点 | "需在 App 中重新授权"或"站点为私有" |

"离线"表示服务器确实离线，"过期"表示 App 拿不到新数据，这两种状态必须能区分开。

## UI 设计

颜色约定：
- 背景：iOS 17 及以上用 `containerBackground(.fill.tertiary)`，iOS 15/16 用 `Color(.secondarySystemBackground)`。
- 文字用 `.primary`/`.secondary`。
- 指标条的颜色：低于 70% 用 `.primary`，70–90% 用 `.orange`，90% 以上用 `.red`。
- 状态点：在线 `.green`，离线 `.red`。
- 不用品牌色和渐变。数字用 `.monospacedDigit()`；服务器名一行显示，超长时截断中间部分。

### 小尺寸 · 单台（P0）

```
┌──────────────────────┐
│ ● HK-01          HK  │  名称 + 地区（headline）
│ CPU  ▓▓░░░░░   12%   │  胶囊条 + 百分比
│ 内存 ▓▓▓▓░░░   58%   │
│ 磁盘 ▓▓░░░░░   28%   │
│ ↑46K ↓47K   3分钟前  │  caption2，次级色
└──────────────────────┘
```

### 中尺寸 · 多台汇总（P0）

```
┌───────────────────────────────────────────┐
│ NS Probe     在线 5/6          3分钟前    │
│ ● HK-01      CPU ▓░░ 12%   内存 ▓▓░ 58%   │
│ ● LAX-02     CPU ▓▓░ 41%   内存 ▓▓▓ 83%   │
│ ● TYO-NAS    离线 · 2小时前               │
└───────────────────────────────────────────┘
```

最多显示 3 行：离线的排在前面，其余按用户选择的顺序排列。空间不够时，用 `ViewThatFits` 去掉内存列。

### 中尺寸 · 单台详情（P1）

左边是三个 `Gauge(.accessoryCircularCapacity)` 环形（CPU/内存/磁盘）；右边四行：网速 ↑↓、负载、运行时长、本月流量（按 `traffic_limit` 显示进度）；底部显示更新时间。

### 锁屏（P1，iOS 16+）

- circular：CPU 环；
- rectangular：名称加三条迷你进度条；
- inline：`● 5/6 在线`。

锁屏组件全部用 `widgetAccentable`，不用颜色区分状态，改用 SF Symbol 区分。

### 点按跳转

注册 URL Scheme `nsconnect`：
- 小组件整体用 `widgetURL(nsconnect://probe/<instanceID>/<serverID>)`；
- 中尺寸每一行用 `Link` 跳到各自的服务器；
- 未配置状态跳到 `nsconnect://probe/settings`。

## 安全与隐私

- 只允许 https。主 App 添加实例时校验 scheme 和 host，测试连接时会跟随重定向，但只接受同一个 host。
- Komari P0 不使用任何凭证。哪吒的 PAT 存在共享 Keychain group，可访问性设为 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`，否则锁屏时小组件读不到。
- App Group 只保存实例元信息和脱敏快照，不保存 IP、备注和 token。
- 日志只记录实例 ID 和错误类型，不记录 URL 路径以外的内容，也不记录响应体。

## 工程准备

- 部署版本是 iOS 15.0，按系统版本分别处理：
  - `containerBackground`、`AppIntentConfiguration`、交互式刷新按钮需要 iOS 17；
  - accessory 尺寸需要 iOS 16；
  - P0 用 `StaticConfiguration`，在主 App 里选要展示的服务器。
- 新增 target `NodeSeekWidget`，Bundle ID 为 `com.mistj.nodeseek.widget`。
- 新增 App Group `group.com.mistj.nodeseek`，以及 Keychain group `$(AppIdentifierPrefix)com.mistj.nodeseek.shared`。主 App 的 `nodeseek.entitlements`、`nodeseek-release.entitlements` 和扩展的 entitlements 都要加上。
- 开发者后台：新建扩展的 App ID 和 App Group，重新生成两套 profile。
- fastlane：`get_provisioning_profile` 和导出时的 `provisioningProfiles` 要覆盖主 App 和扩展两个 ID。
- Info.plist 加 `CFBundleURLTypes`（`nsconnect`）。

## 测试环境

- 测试面板：自建 Komari 1.6.1，部署细节和地址不写入仓库。
- 需要在后台手动构造的场景：隐藏节点、私有站点、停掉 agent（离线）、停掉 komari 服务（不可达）、重启面板（暂无数据）。

## 验证计划

- SwiftPM：Komari/哪吒解码（包括真实 fixture、缺字段、`omitempty` 为 0 的字段、私有站点错误）、在线判定、`ProbeDisplayState` 状态推导、请求构造、URL 校验。
- Xcode：快照存储读写、Timeline entry 生成（正常、失败、过期切换）、设置页 presenter。
- 真机（iOS 15 和 iOS 17+）：添加小组件；冷启动后恢复所选服务器；断网后显示缓存；停掉 agent 后显示离线；暗黑模式；辅助功能大字；服务器名超长。
