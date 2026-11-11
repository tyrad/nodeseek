import XCTest
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

/// fixture 来自真实 Komari 1.6.1 面板（2026-11-10 抓取），节点 UUID 已替换为固定假值。
/// 用内置的 komari 配置驱动通用引擎，断言与原先手写解析器的结果一致。
final class ProbeAdapterEngineTests: XCTestCase {
    private let hk = "11111111-1111-4111-8111-111111111111"
    private let sg = "22222222-2222-4222-8222-222222222222"
    private let base = URL(string: "https://pin.example.com")!

    // MARK: - Komari 内置配置

    func testBuiltinKomariSpecLoads() throws {
        let engine = try komari()
        XCTAssertEqual(engine.spec.id, "komari")
        XCTAssertEqual(engine.spec.auth, .none)
    }

    func testDecodesGuestNodeListWithoutSensitiveFields() throws {
        let engine = try komari()
        let nodes = try engine.nodes(from: json(engine, "komari-nodes"))
        XCTAssertEqual(nodes.map(\.name), ["HK-01", "SG-01"])
        let first = try XCTUnwrap(nodes.first { $0.id == hk })
        XCTAssertEqual(first.region, "🇭🇰")
        XCTAssertEqual(first.cpuCores, 4)
        XCTAssertEqual(first.memTotal, 4_115_853_312)
        XCTAssertNil(first.group, "空字符串分组按缺失处理")
        let raw = try XCTUnwrap(String(data: fixture("komari-nodes"), encoding: .utf8))
        XCTAssertFalse(raw.contains("ipv4"))
    }

    func testDecodesBatchLatestStatus() throws {
        let engine = try komari()
        let statuses = try engine.statuses(from: json(engine, "komari-latest-status"))
        XCTAssertEqual(Set(statuses.keys), [hk, sg])
        let status = try XCTUnwrap(statuses[hk])
        XCTAssertTrue(status.online)
        XCTAssertNotNil(status.sampledAt, "纳秒精度的时间也要能解析")
        XCTAssertNotNil(status.metrics.cpuPercent)
        XCTAssertNotNil(status.metrics.memPercent)
        XCTAssertNotNil(status.metrics.diskPercent)
        XCTAssertNotNil(status.metrics.netInRate)
        XCTAssertNotNil(status.metrics.uptime)
        XCTAssertNil(status.metrics.swapTotal, "swap_total 为 0 表示没有 swap，不能算出百分比")
    }

    func testOfflineNodeKeepsLastReportedMetrics() throws {
        let engine = try komari()
        let statuses = try engine.statuses(from: json(engine, "komari-latest-status-offline"))
        let offline = try XCTUnwrap(statuses[sg])
        XCTAssertFalse(offline.online)
        XCTAssertNotNil(offline.sampledAt)
        XCTAssertNotNil(offline.metrics.cpuPercent, "离线后面板仍返回最后一次上报的指标")
        XCTAssertEqual(statuses[hk]?.online, true)
    }

    func testMapsAllStatusFieldsFromRealResponse() throws {
        let engine = try komari()
        // 单节点响应 result 是对象而不是字典，把它包成批量结构再解析，验证字段映射。
        let single = try XCTUnwrap(try JSONSerialization.jsonObject(with: fixture("komari-latest-status-single")) as? [String: Any])
        let wrapped: [String: Any] = ["result": [hk: single["result"]!]]
        let status = try XCTUnwrap(try engine.statuses(from: wrapped)[hk])
        let metrics = status.metrics
        XCTAssertEqual(metrics.memUsed, 437_231_616)
        XCTAssertEqual(metrics.diskTotal, 32_061_511_680)
        XCTAssertEqual(metrics.netInRate, 58_369)
        XCTAssertEqual(metrics.netOutRate, 64_639)
        XCTAssertEqual(metrics.netTotalOut, 354_386_652_918)
        XCTAssertEqual(metrics.load5, 0.02)
        XCTAssertEqual(metrics.uptime, 5_680_265)
        XCTAssertEqual(metrics.processCount, 132)
        XCTAssertEqual(metrics.connectionCount, 369)
        XCTAssertEqual(try XCTUnwrap(status.sampledAt).timeIntervalSince1970, 1_794_291_129.212, accuracy: 0.001)
    }

    func testDecodesHistoryInAscendingOrder() throws {
        let engine = try komari()
        let points = try engine.history(from: json(engine, "komari-records-load"))
        XCTAssertEqual(points.count, 6)
        XCTAssertEqual(points.map(\.date), points.map(\.date).sorted())
        XCTAssertNotNil(points.last?.metrics.cpuPercent)
        XCTAssertNotNil(points.last?.metrics.memUsed)
        XCTAssertNil(points.last?.metrics.memTotal, "历史记录里没有内存总量")
    }

    func testClassifiesErrors() throws {
        let engine = try komari()
        XCTAssertThrowsError(try engine.json(from: fixture("komari-latest-status-not-found"), httpStatus: 200)) {
            XCTAssertEqual($0 as? ProbeFetchError, .nodeNotFound)
        }
        XCTAssertThrowsError(try engine.json(from: fixture("komari-rpc-permission-denied"), httpStatus: 200)) {
            XCTAssertEqual($0 as? ProbeFetchError, .unauthorized)
        }
        // 私有站点下 rpc2 和 REST 都返回 REST 风格错误 + 401。
        XCTAssertThrowsError(try engine.json(from: fixture("komari-private-site"), httpStatus: 401)) {
            XCTAssertEqual($0 as? ProbeFetchError, .privateSite)
        }
        XCTAssertThrowsError(try engine.json(from: Data("<html>502 Bad Gateway</html>".utf8), httpStatus: 502)) {
            XCTAssertEqual($0 as? ProbeFetchError, .unreachable)
        }
        XCTAssertThrowsError(try engine.json(from: Data("404 page not found".utf8), httpStatus: 404)) {
            XCTAssertEqual($0 as? ProbeFetchError, .unsupported)
        }
        // 格式变了：路径对不上时报解析错误，而不是返回空列表。
        XCTAssertThrowsError(try engine.statuses(from: ["unexpected": true])) {
            XCTAssertEqual($0 as? ProbeFetchError, .decoding)
        }
        // 面板刚重启时结果确实为空，这是正常情况。
        XCTAssertEqual(try engine.statuses(from: ["result": [String: Any]()]).count, 0)
    }

    func testPreflightDetectsPrivateSite() throws {
        let engine = try komari()
        XCTAssertNoThrow(try engine.runChecks(for: "public", object: json(engine, "komari-public")))
        XCTAssertThrowsError(try engine.runChecks(for: "public", object: ["data": ["private_site": true]])) {
            XCTAssertEqual($0 as? ProbeFetchError, .privateSite)
        }
        XCTAssertEqual(engine.version(from: ["data": ["version": "1.6.1"]]), "1.6.1")
    }

    func testMergeMarksNodesMissingFromLatestAsUnknown() throws {
        let engine = try komari()
        let nodes = try engine.nodes(from: json(engine, "komari-nodes"))
        var statuses = try engine.statuses(from: json(engine, "komari-latest-status-offline"))
        XCTAssertEqual(ProbeServer.merge(nodes: nodes, statuses: statuses).map(\.availability), [.online, .offline])
        statuses.removeValue(forKey: sg)
        XCTAssertEqual(ProbeServer.merge(nodes: nodes, statuses: statuses).map(\.availability), [.online, .unknown])
    }

    func testBuildsRequestsInsidePanelHost() throws {
        let engine = try komari()
        let latest = try engine.request("latest", baseURL: base)
        XCTAssertEqual(latest.url?.absoluteString, "https://pin.example.com/api/rpc2")
        XCTAssertEqual(latest.httpMethod, "POST")
        XCTAssertFalse(latest.httpShouldHandleCookies)
        let body = try XCTUnwrap(latest.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertEqual(body["method"] as? String, "common:getNodesLatestStatus")
        XCTAssertNil(latest.value(forHTTPHeaderField: "Authorization"))

        let history = try engine.request("history", baseURL: base, nodeID: hk, hours: 6)
        XCTAssertEqual(history.url?.absoluteString, "https://pin.example.com/api/records/load?hours=6&uuid=\(hk)")
    }

    func testNormalizesBaseURL() {
        XCTAssertEqual(ProbeAdapterEngine.normalizedBaseURL(" pin.example.com/admin?x=1 ")?.absoluteString, "https://pin.example.com")
        XCTAssertEqual(ProbeAdapterEngine.normalizedBaseURL("https://Pin.Example.com:8443/")?.absoluteString, "https://pin.example.com:8443")
        XCTAssertNil(ProbeAdapterEngine.normalizedBaseURL("http://pin.example.com"))
        XCTAssertNil(ProbeAdapterEngine.normalizedBaseURL("https://user:pass@pin.example.com"))
    }

    // MARK: - 配置安全校验

    func testRejectsRequestPathsThatLeaveThePanel() {
        for path in ["https://evil.example/x", "//evil.example/x", "/a/../b", "/x?token=1", "relative", "/a@evil", "/a b", "/a%2Fb", "/中文"] {
            XCTAssertThrowsError(try ProbeAdapterEngine(data: minimalSpec(path: path)), path) {
                XCTAssertEqual($0 as? ProbeAdapterSpecError, .unsafeRequestPath(path))
            }
        }
    }

    func testRejectsMalformedSpecs() {
        XCTAssertThrowsError(try ProbeAdapterEngine(data: Data("{".utf8))) {
            XCTAssertEqual($0 as? ProbeAdapterSpecError, .invalidJSON)
        }
        XCTAssertThrowsError(try ProbeAdapterEngine(data: minimalSpec(version: 2))) {
            XCTAssertEqual($0 as? ProbeAdapterSpecError, .unsupportedSpecVersion(2))
        }
        XCTAssertThrowsError(try ProbeAdapterEngine(data: minimalSpec(itemsPath: "data[*]"))) {
            XCTAssertEqual($0 as? ProbeAdapterSpecError, .invalidPath("data[*]"))
        }
    }

    func testNodeIDCannotInjectPathSegments() throws {
        let engine = try ProbeAdapterEngine(data: minimalSpec(path: "/api/recent/{nodeID}"))
        let request = try engine.request("list", baseURL: base, nodeID: "../../admin?x=1")
        XCTAssertEqual(request.url?.host, "pin.example.com")
        XCTAssertFalse(request.url?.absoluteString.contains("/admin") ?? true)
    }

    // MARK: - 通用性：哪吒 V2 风格的配置

    func testNezhaStyleSpecWithBearerFreshnessAndSums() throws {
        let spec = """
        {
          "id": "nezha", "name": "哪吒", "specVersion": 1,
          "auth": { "type": "header", "header": "Authorization", "prefix": "Bearer " },
          "requests": { "servers": { "method": "GET", "path": "/api/v1/server" } },
          "nodes": { "request": "servers", "items": "$.data[*]",
                     "fields": { "id": "$.id", "name": "$.name", "memTotal": "$.host.mem_total" } },
          "status": { "request": "servers", "items": "$.data[*]",
                      "online": { "type": "freshness", "path": "$.last_active", "seconds": 60 },
                      "fields": { "id": "$.id", "cpu": "$.state.cpu", "memUsed": "$.state.mem_used",
                                  "memTotal": "$.host.mem_total", "sampledAt": { "path": "$.last_active", "format": "iso8601" },
                                  "connectionCount": { "sum": ["$.state.tcp_conn_count", "$.state.udp_conn_count"] } } }
        }
        """
        let engine = try ProbeAdapterEngine(data: Data(spec.utf8))
        let request = try engine.request("servers", baseURL: base, token: "nzp_secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer nzp_secret")

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fresh = ISO8601DateFormatter().string(from: now.addingTimeInterval(-20))
        let stale = ISO8601DateFormatter().string(from: now.addingTimeInterval(-300))
        let response: [String: Any] = ["success": true, "data": [
            ["id": 7, "name": "a", "last_active": fresh, "host": ["mem_total": 1000],
             "state": ["cpu": 12.5, "mem_used": 250, "tcp_conn_count": 10, "udp_conn_count": 2]],
            // omitempty：值为 0 的字段整体缺失，不能当成解析失败。
            ["id": 8, "name": "b", "last_active": stale, "host": ["mem_total": 1000], "state": ["cpu": 1]],
        ]]
        XCTAssertEqual(try engine.nodes(from: response).map(\.id), ["7", "8"])
        let statuses = try engine.statuses(from: response, now: now)
        XCTAssertEqual(statuses["7"]?.online, true)
        XCTAssertEqual(statuses["8"]?.online, false)
        XCTAssertEqual(statuses["7"]?.metrics.memPercent, 25)
        XCTAssertEqual(statuses["7"]?.metrics.connectionCount, 12)
        XCTAssertNil(statuses["8"]?.metrics.connectionCount, "求和字段缺任一项时显示缺失")
        XCTAssertNil(statuses["8"]?.metrics.memUsed)
    }

    // MARK: - 极简探针

    func testBuiltinMonitorSpecLoads() throws {
        let engine = try monitor()
        XCTAssertEqual(engine.spec.id, "monitor")
        XCTAssertEqual(engine.spec.name, "极简探针")
        XCTAssertEqual(engine.spec.auth, .none)
    }

    func testMonitorDecodesPublicNodesAndKeepsBytesUnscaled() throws {
        let engine = try monitor()
        let nodes = try engine.nodes(from: json(engine, "monitor-nodes"))
        XCTAssertEqual(nodes.map(\.id), ["7", "8", "9"])
        XCTAssertEqual(nodes.map(\.name), ["SG-01", "HK-01", "刚连上"])
        let online = try XCTUnwrap(nodes.first { $0.id == "7" })
        XCTAssertEqual(online.region, "SG")
        XCTAssertEqual(online.group, "亚太")
        XCTAssertEqual(online.cpuCores, 4)
        XCTAssertEqual(online.memTotal, 4_115_853_312)
        XCTAssertEqual(online.weight, 1)
        let offline = try XCTUnwrap(nodes.first { $0.id == "8" })
        XCTAssertNil(offline.region, "空的国家代码按缺失处理")
        XCTAssertNil(offline.group)
        let raw = try XCTUnwrap(String(data: fixture("monitor-nodes"), encoding: .utf8))
        XCTAssertFalse(raw.contains("ipv4"))
        XCTAssertFalse(raw.contains("hostname"))
    }

    func testMonitorStatusUsesOnlineFlagAndByteRates() throws {
        let engine = try monitor()
        let statuses = try engine.statuses(from: json(engine, "monitor-nodes"))
        let online = try XCTUnwrap(statuses["7"])
        XCTAssertTrue(online.online)
        XCTAssertEqual(try XCTUnwrap(online.sampledAt).timeIntervalSince1970, 1_794_291_129, accuracy: 0.001)
        XCTAssertEqual(online.metrics.cpuPercent, 12.5)
        XCTAssertEqual(online.metrics.memUsed, 437_231_616)
        XCTAssertEqual(online.metrics.memTotal, 4_115_853_312)
        XCTAssertEqual(online.metrics.diskUsed, 10_000_000_000)
        XCTAssertNil(online.metrics.swapTotal, "swap_total 为 0 表示没有 swap")
        XCTAssertEqual(online.metrics.netInRate, 58_369, "net_rx 已是 B/s，不能再乘 1024")
        XCTAssertEqual(online.metrics.netOutRate, 64_639)
        XCTAssertEqual(online.metrics.netTotalIn, 1_000)
        XCTAssertEqual(online.metrics.netTotalOut, 2_000)
        XCTAssertEqual(online.metrics.load1, 0.4)
        XCTAssertEqual(online.metrics.load5, 0.2)
        XCTAssertEqual(online.metrics.load15, 0.1)
        XCTAssertEqual(online.metrics.uptime, 3_600)
        XCTAssertEqual(online.metrics.processCount, 132)
        XCTAssertEqual(online.metrics.connectionCount, 12, "tcp 与 udp 相加")

        let offline = try XCTUnwrap(statuses["8"])
        XCTAssertFalse(offline.online)
        XCTAssertNotNil(offline.sampledAt)
        XCTAssertNil(offline.metrics.cpuPercent, "离线时 metrics 为 null，不能显示成 0%")

        let pending = try XCTUnwrap(statuses["9"])
        XCTAssertTrue(pending.online, "刚连上、还没有指标时仍以 online 为准")
        XCTAssertNil(pending.metrics.cpuPercent)
        XCTAssertNil(pending.metrics.connectionCount)
    }

    func testMonitorHistoryUsesUnixSecondsAndSkipsUnsetTimestamps() throws {
        let engine = try monitor()
        let points = try engine.history(from: json(engine, "monitor-metrics"))
        XCTAssertEqual(points.count, 2, "ts 为 0 的点不是有效采样时间")
        XCTAssertEqual(points.map(\.date), points.map(\.date).sorted())
        XCTAssertEqual(points.first?.metrics.cpuPercent, 1.5)
        XCTAssertEqual(points.last?.metrics.memUsed, 110)
        XCTAssertEqual(points.last?.metrics.netInRate, 30)
        XCTAssertNil(points.last?.metrics.memTotal, "历史点没有内存总量")
        let empty = try JSONSerialization.jsonObject(with: Data(#"{"metrics":[]}"#.utf8))
        XCTAssertEqual(try engine.history(from: empty).count, 0)
        let wrongShape = try JSONSerialization.jsonObject(with: Data(#"{"ping":[]}"#.utf8))
        XCTAssertThrowsError(try engine.history(from: wrongShape)) {
            XCTAssertEqual($0 as? ProbeFetchError, .decoding)
        }
    }

    func testMonitorClosedPageAndHistoryRequest() throws {
        let engine = try monitor()
        XCTAssertThrowsError(try engine.json(from: Data("需要登录后查看".utf8), httpStatus: 401)) {
            XCTAssertEqual($0 as? ProbeFetchError, .unauthorized)
        }
        let history = try engine.request("history", baseURL: base, nodeID: "7", hours: 24)
        XCTAssertEqual(history.url?.absoluteString, "https://pin.example.com/api/nodes/7/metrics?hours=24&series=metrics")
        XCTAssertEqual(history.httpMethod, "GET")
    }

    // MARK: - CF-Server-Monitor

    /// fixture 的结构参照 CF-Server-Monitor 2.8.7 的接口，数值全部是编造的。
    func testBuiltinCFSMSpecLoads() throws {
        let engine = try cfsm()
        XCTAssertEqual(engine.spec.id, "cfsm")
        XCTAssertEqual(engine.spec.name, "CF-Server-Monitor")
        XCTAssertEqual(engine.spec.auth, .none)
        XCTAssertEqual(engine.version(from: try json(engine, "cfsm-config")), "2.8.7 Beta6")
    }

    func testCFSMDecodesServersAndConvertsMegabytes() throws {
        let engine = try cfsm()
        let nodes = try engine.nodes(from: json(engine, "cfsm-servers"))
        XCTAssertEqual(nodes.map(\.name), ["HK-01", "US-01", "刚添加"])
        let hk = try XCTUnwrap(nodes.first)
        XCTAssertEqual(hk.region, "HK")
        XCTAssertEqual(hk.group, "香港")
        XCTAssertEqual(hk.cpuCores, 1)
        XCTAssertEqual(hk.memTotal, 1_024 * 1_048_576, "面板给的是 MB")
        XCTAssertEqual(hk.diskTotal, 40_960 * 1_048_576)
        XCTAssertEqual(hk.weight, 1)
        XCTAssertNil(nodes.last?.region, "还没上报的机器地区为空")
    }

    func testCFSMStatusUsesLastUpdatedWithinFiveMinutes() throws {
        let engine = try cfsm()
        let now = Date(timeIntervalSince1970: 1_800_000_040)
        let statuses = try engine.statuses(from: json(engine, "cfsm-servers"), now: now)

        let hk = try XCTUnwrap(statuses["11111111-1111-4111-8111-111111111111"])
        XCTAssertTrue(hk.online, "40 秒前上报")
        XCTAssertEqual(try XCTUnwrap(hk.sampledAt).timeIntervalSince1970, 1_800_000_000, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(hk.metrics.cpuPercent), 1.25, accuracy: 0.001)
        XCTAssertEqual(hk.metrics.memUsed, 300 * 1_048_576)
        XCTAssertEqual(hk.metrics.memTotal, 1_024 * 1_048_576)
        XCTAssertEqual(hk.metrics.diskUsed, 8_192 * 1_048_576)
        XCTAssertEqual(hk.metrics.swapUsed, 16 * 1_048_576)
        XCTAssertEqual(hk.metrics.netInRate, 4_000, "网速已是 B/s")
        XCTAssertEqual(hk.metrics.netOutRate, 3_000)
        XCTAssertEqual(hk.metrics.netTotalIn, 10_000_000_000)
        XCTAssertEqual(hk.metrics.processCount, 100)
        XCTAssertEqual(hk.metrics.connectionCount, 7, "tcp 与 udp 相加")
        XCTAssertNil(hk.metrics.load1, "load_avg 是整段文字，暂不解析")

        let us = try XCTUnwrap(statuses["22222222-2222-4222-8222-222222222222"])
        XCTAssertFalse(us.online, "15 分钟没上报算离线")
        XCTAssertEqual(Double(try XCTUnwrap(us.metrics.memUsed)), 288.5 * 1_048_576, accuracy: 1_048_576 * 0.001, "内存可能带小数")

        let fresh = try XCTUnwrap(statuses["33333333-3333-4333-8333-333333333333"])
        XCTAssertFalse(fresh.online, "从未上报")
        XCTAssertNil(fresh.sampledAt)
        XCTAssertNil(fresh.metrics.cpuPercent)
    }

    func testCFSMHistoryIsTopLevelArrayInMilliseconds() throws {
        let engine = try cfsm()
        let points = try engine.history(from: json(engine, "cfsm-history"))
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(try XCTUnwrap(points.first).date.timeIntervalSince1970, 1_799_996_400, accuracy: 0.001)
        XCTAssertEqual(points.first?.metrics.memUsed, 300 * 1_048_576)
        XCTAssertEqual(points.first?.metrics.netInRate, 3_900)
        XCTAssertEqual(try engine.history(from: [Any]()).count, 0)

        let request = try engine.request("history", baseURL: base, nodeID: "abc", hours: 6)
        let components = try XCTUnwrap(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        XCTAssertEqual(components.path, "/api/history/all")
        XCTAssertEqual(Set(components.queryItems ?? []), [URLQueryItem(name: "id", value: "abc"), URLQueryItem(name: "hours", value: "6")])
    }

    func testPlanFieldsFromAllThreeProbes() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_040)
        let gb: Int64 = 1_073_741_824

        // CF-Server-Monitor：价格是文字，流量上限按 GB 填，用开机时间算运行时长。
        let cfsm = try cfsm()
        let object = try json(cfsm, "cfsm-servers")
        let hk = try XCTUnwrap(cfsm.nodes(from: object).first)
        let plan = try XCTUnwrap(hk.plan)
        XCTAssertEqual(plan.price, 99)
        XCTAssertEqual(plan.currency, "¥")
        XCTAssertEqual(plan.cycle, .months(12))
        XCTAssertEqual(plan.trafficLimit, 500 * gb)
        XCTAssertEqual(plan.trafficMode, .sum)
        XCTAssertEqual(plan.trafficResetDay, 1)
        let expiry = try XCTUnwrap(plan.expiresAt)
        XCTAssertEqual(Calendar.current.dateComponents([.year, .month, .day], from: expiry), DateComponents(year: 2030, month: 1, day: 1))
        XCTAssertEqual(hk.tags, ["vps", "中转"])
        XCTAssertEqual(hk.arch, "amd64")
        XCTAssertNil(try cfsm.nodes(from: object)[1].plan, "价格、到期、上限都没填")
        let status = try XCTUnwrap(cfsm.statuses(from: object, now: now)[hk.id])
        XCTAssertEqual(status.metrics.trafficIn, 30_000_000_000)
        XCTAssertEqual(status.metrics.trafficOut, 20_000_000_000)
        XCTAssertEqual(status.metrics.uptime, Int64(now.timeIntervalSince1970 - 1_799_000_000))

        // Komari：周期是天数，上限是字节，已用流量取累计值。
        let komari = try komari()
        let komariNode: [String: Any] = [
            "uuid": "k1", "name": "k", "virtualization": "kvm", "arch": "amd64", "tags": "中转;香港",
            "public_remark": "公开备注\n", "price": 5, "currency": "$", "billing_cycle": 30,
            "expired_at": "2026-12-01T00:00:00Z", "traffic_limit": 4 * 1_099_511_627_776, "traffic_limit_type": "max",
        ]
        let node = try XCTUnwrap(komari.nodes(from: ["data": [komariNode]]).first)
        XCTAssertEqual(node.virtualization, "kvm")
        XCTAssertEqual(node.tags, ["中转", "香港"])
        XCTAssertEqual(node.remark, "公开备注")
        XCTAssertEqual(node.plan?.cycle, .months(1))
        XCTAssertEqual(node.plan?.trafficMode, .max)
        XCTAssertNotNil(node.plan?.expiresAt)
        let unset = try XCTUnwrap(komari.nodes(from: json(komari, "komari-nodes")).first)
        XCTAssertNil(unset.plan, "Komari 默认价格 0、周期 0、上限 0，都算未填")
        let komariStatus = try komari.statuses(from: ["result": ["k1": ["client": "k1", "online": true, "net_total_down": 10, "net_total_up": 20]]])
        XCTAssertEqual(komariStatus["k1"]?.metrics.trafficIn, 10)
        XCTAssertEqual(komariStatus["k1"]?.metrics.trafficOut, 20)

        // 极简探针：到期只有日期，币种是三字母，本月流量在节点顶层。
        let monitor = try monitor()
        let monitorNode: [String: Any] = [
            "id": 7, "name": "m", "virt": "kvm", "arch": "x86_64", "public_remark": "", "price": 10, "currency": "USD",
            "billing_cycle": "yearly", "expires_at": "2027-07-21", "traffic_limit": 1_099_511_627_776, "traffic_mode": "up",
            "traffic_reset_day": 5, "online": true, "month_rx": 100, "month_tx": 200, "metrics": ["uptime": 60],
        ]
        let mNode = try XCTUnwrap(monitor.nodes(from: ["nodes": [monitorNode]]).first)
        XCTAssertEqual(mNode.virtualization, "kvm")
        XCTAssertNil(mNode.remark, "空备注不显示")
        XCTAssertEqual(mNode.plan?.cycle, .months(12))
        XCTAssertEqual(mNode.plan?.trafficMode, .up)
        XCTAssertEqual(mNode.plan?.trafficResetDay, 5)
        XCTAssertEqual(ProbePlanSummary(plan: mNode.plan, metrics: nil)?.price, "$10/年")
        let mStatus = try XCTUnwrap(monitor.statuses(from: ["nodes": [monitorNode]])["7"])
        XCTAssertEqual(mStatus.metrics.trafficOut, 200)
        XCTAssertEqual(mStatus.metrics.uptime, 60)
    }

    func testCFSMPreflightAndErrors() throws {
        let engine = try cfsm()
        XCTAssertNoThrow(try engine.runChecks(for: "version", object: json(engine, "cfsm-config")))
        XCTAssertThrowsError(try engine.runChecks(for: "version", object: ["is_public": false, "turnstile_enabled": false])) {
            XCTAssertEqual($0 as? ProbeFetchError, .privateSite)
        }
        XCTAssertThrowsError(try engine.runChecks(for: "version", object: ["is_public": true, "turnstile_enabled": true])) {
            XCTAssertEqual($0 as? ProbeFetchError, .humanVerification)
        }
        let cases: [(String, Int, ProbeFetchError)] = [
            (#"{"error":"Unauthorized","code":401}"#, 401, .privateSite),
            (#"{"error":"Turnstile verification failed","code":403}"#, 403, .humanVerification),
            (#"{"error":"Server not found","code":404}"#, 404, .nodeNotFound),
            (#"{"message":"databaseUpgradeRequired"}"#, 409, .unsupported),
        ]
        for (body, status, expected) in cases {
            XCTAssertThrowsError(try engine.json(from: Data(body.utf8), httpStatus: status)) {
                XCTAssertEqual($0 as? ProbeFetchError, expected, body)
            }
        }
    }

    func testJSONPathSupportsArraysDictionariesAndIndexes() {
        let root: [String: Any] = ["a": ["b": [["c": 1], ["c": 2]]], "m": ["y": ["v": 2], "x": ["v": 1]]]
        XCTAssertEqual(ProbeJSONPath.values("$.a.b[*].c", in: root).compactMap { ProbeJSONPath.number($0) }, [1, 2])
        XCTAssertEqual(ProbeJSONPath.number(ProbeJSONPath.first("$.a.b[1].c", in: root)), 2)
        XCTAssertEqual(ProbeJSONPath.values("$.m.*.v", in: root).compactMap { ProbeJSONPath.number($0) }, [1, 2], "字典按键排序")
        XCTAssertNil(ProbeJSONPath.parse("a.b"))
        XCTAssertTrue(ProbeJSONPath.values("$.missing[*]", in: root).isEmpty)
    }

    // MARK: - 辅助

    private func komari() throws -> ProbeAdapterEngine {
        try ProbeAdapterEngine(data: BuiltinAdapterLoader.data(named: "probe-adapter-komari"))
    }

    private func monitor() throws -> ProbeAdapterEngine {
        try ProbeAdapterEngine(data: BuiltinAdapterLoader.data(named: "probe-adapter-monitor"))
    }

    private func cfsm() throws -> ProbeAdapterEngine {
        try ProbeAdapterEngine(data: BuiltinAdapterLoader.data(named: "probe-adapter-cfsm"))
    }

    private func json(_ engine: ProbeAdapterEngine, _ name: String) throws -> Any {
        try engine.json(from: fixture(name), httpStatus: 200)
    }

    private func minimalSpec(path: String = "/api/list", version: Int = 1, itemsPath: String = "$.data[*]") -> Data {
        Data("""
        { "id": "t", "name": "t", "specVersion": \(version), "auth": { "type": "none" },
          "requests": { "list": { "method": "GET", "path": "\(path)" } },
          "nodes": { "request": "list", "items": "\(itemsPath)", "fields": { "id": "$.id" } },
          "status": { "request": "list", "items": "$.data[*]", "online": { "type": "bool", "path": "$.on" }, "fields": { "id": "$.id" } } }
        """.utf8)
    }

    private func fixture(_ name: String) throws -> Data {
        #if SWIFT_PACKAGE
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        #else
        let url = try XCTUnwrap(Bundle(for: ProbeAdapterEngineTests.self).url(forResource: name, withExtension: "json"))
        #endif
        return try Data(contentsOf: url)
    }
}

/// 读取 App 内置的适配器配置。SwiftPM 测试进程没有 App bundle，按源码路径读取同一个文件。
enum BuiltinAdapterLoader {
    static func data(named name: String) throws -> Data {
        if let url = Bundle.main.url(forResource: name, withExtension: "json") {
            return try Data(contentsOf: url)
        }
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: repoRoot.appendingPathComponent("nodeseek/Resources/ProbeAdapters/\(name).json"))
    }
}
