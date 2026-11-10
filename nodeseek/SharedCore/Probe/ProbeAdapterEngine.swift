import Foundation

/// 配置文件本身不合法。与 `ProbeFetchError`（运行时请求失败）分开，便于在加载配置时就拒绝。
nonisolated enum ProbeAdapterSpecError: Error, Equatable {
    case unsupportedSpecVersion(Int)
    case invalidPath(String)
    case unsafeRequestPath(String)
    case missingRequest(String)
    case invalidJSON
}

/// 按配置构造请求、解析响应。纯函数，不发起网络，App 与以后的小组件扩展共用。
nonisolated struct ProbeAdapterEngine: Sendable {
    static let requestTimeout: TimeInterval = 10

    let spec: ProbeAdapterSpec

    init(spec: ProbeAdapterSpec) throws {
        try Self.validate(spec)
        self.spec = spec
    }

    init(data: Data) throws {
        let spec: ProbeAdapterSpec
        do {
            spec = try JSONDecoder().decode(ProbeAdapterSpec.self, from: data)
        } catch {
            throw ProbeAdapterSpecError.invalidJSON
        }
        try self.init(spec: spec)
    }

    // MARK: - 请求

    /// 规范化用户输入的面板地址：只接受 https，去掉路径、查询和账号信息。
    static func normalizedBaseURL(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard let components = URLComponents(string: text),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else { return nil }
        var normalized = URLComponents()
        normalized.scheme = "https"
        normalized.host = host.lowercased()
        normalized.port = components.port
        return normalized.url
    }

    /// 构造配置里名为 `name` 的请求。最终地址必须仍在 `baseURL` 的域名和端口下。
    func request(
        _ name: String,
        baseURL: URL,
        nodeID: String? = nil,
        nodeIDs: [String] = [],
        hours: Int? = nil,
        token: String? = nil
    ) throws -> URLRequest {
        guard let template = spec.requests[name] else { throw ProbeAdapterSpecError.missingRequest(name) }
        var path = template.path
        if let nodeID {
            let encoded = nodeID.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))) ?? nodeID
            path = path.replacingOccurrences(of: "{nodeID}", with: encoded)
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ProbeAdapterSpecError.unsafeRequestPath(template.path)
        }
        // 模板路径是 ASCII，节点 ID 已单独编码，这里直接按已编码路径设置，避免二次编码。
        components.percentEncodedPath = path
        if let query = template.query, !query.isEmpty {
            components.queryItems = query.keys.sorted().map { key in
                URLQueryItem(name: key, value: substitute(query[key] ?? "", nodeID: nodeID, hours: hours))
            }
        }
        guard let url = components.url, url.host == baseURL.host, url.port == baseURL.port, url.scheme == "https" else {
            throw ProbeAdapterSpecError.unsafeRequestPath(template.path)
        }
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.httpMethod = template.method.uppercased()
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = template.body {
            let object = substituteBody(body, nodeID: nodeID, nodeIDs: nodeIDs, hours: hours)
            request.httpBody = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if case let .header(header, prefix) = spec.auth, let token, !token.isEmpty {
            request.setValue(prefix + token, forHTTPHeaderField: header)
        }
        return request
    }

    // MARK: - 解析

    /// 校验响应状态与错误规则；通过时返回解析后的 JSON。
    func json(from data: Data, httpStatus: Int) throws -> Any {
        let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let body = String(data: data.prefix(4096), encoding: .utf8) ?? ""
        for rule in spec.errors ?? [] where matches(rule, httpStatus: httpStatus, body: body, object: object) {
            throw rule.error
        }
        switch httpStatus {
        case 200..<300: break
        case 401, 403: throw ProbeFetchError.unauthorized
        case 404: throw ProbeFetchError.unsupported
        case 500...: throw ProbeFetchError.unreachable
        default: throw ProbeFetchError.decoding
        }
        guard let object else { throw ProbeFetchError.decoding }
        return object
    }

    func version(from object: Any) -> String? {
        spec.version.flatMap { ProbeJSONPath.string(ProbeJSONPath.first($0.path, in: object)) }
    }

    /// 执行某个请求对应的检查项，命中时抛出配置指定的错误。
    func runChecks(for request: String, object: Any) throws {
        for check in spec.preflight ?? [] where check.request == request {
            if check.equals.matches(ProbeJSONPath.first(check.path, in: object)) { throw check.error }
        }
    }

    func nodes(from object: Any) throws -> [ProbeNode] {
        let items = ProbeJSONPath.values(spec.nodes.items, in: object)
        guard !items.isEmpty || isEmptyCollection(spec.nodes.items, in: object) else { throw ProbeFetchError.decoding }
        return items.compactMap { item in
            let fields = spec.nodes.fields
            guard let id = string("id", fields, item) else { return nil }
            return ProbeNode(
                id: id,
                name: string("name", fields, item) ?? String(id.prefix(8)),
                region: string("region", fields, item),
                group: string("group", fields, item),
                os: string("os", fields, item),
                cpuCores: number("cpuCores", fields, item).map { Int($0) },
                memTotal: positiveInt("memTotal", fields, item),
                diskTotal: positiveInt("diskTotal", fields, item),
                weight: number("weight", fields, item).map { Int($0) } ?? 0
            )
        }
    }

    /// 返回 `[节点 ID: 状态]`。`now` 用于时间新鲜度规则。
    func statuses(from object: Any, now: Date = Date()) throws -> [String: ProbeStatus] {
        let items = ProbeJSONPath.values(spec.status.items, in: object)
        guard !items.isEmpty || isEmptyCollection(spec.status.items, in: object) else { throw ProbeFetchError.decoding }
        var result: [String: ProbeStatus] = [:]
        let fields = spec.status.fields
        for item in items {
            guard let id = string("id", fields, item) else { continue }
            let sampledAt = date("sampledAt", fields, item)
            let online: Bool
            switch spec.status.online {
            case let .bool(path):
                online = (ProbeJSONPath.first(path, in: item) as? NSNumber)?.boolValue ?? false
            case let .freshness(path, format, seconds):
                let last = ProbeJSONPath.date(ProbeJSONPath.first(path, in: item), format: format)
                online = last.map { now.timeIntervalSince($0) <= seconds } ?? false
            }
            result[id] = ProbeStatus(nodeID: id, online: online, sampledAt: sampledAt, metrics: metrics(fields, item))
        }
        return result
    }

    /// 历史记录按时间升序返回。
    func history(from object: Any) throws -> [ProbeHistoryPoint] {
        guard let history = spec.history else { return [] }
        let items = ProbeJSONPath.values(history.items, in: object)
        guard !items.isEmpty || isEmptyCollection(history.items, in: object) else { throw ProbeFetchError.decoding }
        return items.compactMap { item -> ProbeHistoryPoint? in
            guard let date = date("time", history.fields, item) else { return nil }
            return ProbeHistoryPoint(date: date, metrics: metrics(history.fields, item))
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: - 私有

    private static func validate(_ spec: ProbeAdapterSpec) throws {
        guard spec.specVersion == ProbeAdapterSpec.supportedSpecVersion else { throw ProbeAdapterSpecError.unsupportedSpecVersion(spec.specVersion) }
        for template in spec.requests.values {
            let path = template.path
            // 只允许相对路径，禁止协议、主机名和目录穿越，防止请求被引到别的域名。
            // 字符限定为字母数字和少量符号：既挡住注入，也避免 percentEncodedPath 遇到非法字符时崩溃。
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/-_.{}"))
            guard path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains(".."),
                  path.unicodeScalars.allSatisfy({ $0.isASCII && allowed.contains($0) }) else {
                throw ProbeAdapterSpecError.unsafeRequestPath(path)
            }
        }
        var referenced = [spec.nodes.request, spec.status.request]
        referenced += spec.history.map { [$0.request] } ?? []
        referenced += spec.version.map { [$0.request] } ?? []
        referenced += (spec.preflight ?? []).map(\.request)
        for name in referenced where spec.requests[name] == nil {
            throw ProbeAdapterSpecError.missingRequest(name)
        }
        var paths = [spec.nodes.items, spec.status.items]
        paths += spec.history.map { [$0.items] } ?? []
        paths += spec.version.map { [$0.path] } ?? []
        paths += (spec.preflight ?? []).map(\.path)
        paths += (spec.errors ?? []).compactMap(\.path)
        for mapping in [spec.nodes.fields, spec.status.fields, spec.history?.fields ?? [:]] {
            paths += mapping.values.flatMap(\.paths)
        }
        switch spec.status.online {
        case let .bool(path), let .freshness(path, _, _): paths.append(path)
        }
        for path in paths where ProbeJSONPath.parse(path) == nil {
            throw ProbeAdapterSpecError.invalidPath(path)
        }
    }

    private func matches(_ rule: ProbeAdapterSpec.ErrorRule, httpStatus: Int, body: String, object: Any?) -> Bool {
        if let status = rule.status, status != httpStatus { return false }
        if let text = rule.bodyContains, !body.localizedCaseInsensitiveContains(text) { return false }
        if let path = rule.path {
            guard let object, let expected = rule.equals, expected.matches(ProbeJSONPath.first(path, in: object)) else { return false }
        }
        return rule.status != nil || rule.bodyContains != nil || rule.path != nil
    }

    /// 条目为空时，区分“确实是空列表”和“路径对不上（格式变了）”。
    private func isEmptyCollection(_ itemsPath: String, in object: Any) -> Bool {
        guard let steps = ProbeJSONPath.parse(itemsPath), let last = steps.last,
              last == .allElements || last == .allValues else { return false }
        let parentPath = itemsPath.hasSuffix("[*]") ? String(itemsPath.dropLast(3)) : String(itemsPath.dropLast(2))
        let parent = parentPath == "$" ? object : ProbeJSONPath.first(parentPath, in: object)
        if let array = parent as? [Any] { return array.isEmpty }
        if let dict = parent as? [String: Any] { return dict.isEmpty }
        return false
    }

    private func substitute(_ text: String, nodeID: String?, hours: Int?) -> String {
        var result = text
        if let nodeID { result = result.replacingOccurrences(of: "{nodeID}", with: nodeID) }
        if let hours { result = result.replacingOccurrences(of: "{hours}", with: String(hours)) }
        return result
    }

    private func substituteBody(_ value: JSONValue, nodeID: String?, nodeIDs: [String], hours: Int?) -> Any {
        switch value {
        case let .string(text) where text == "{nodeIDs}":
            return nodeIDs
        case let .string(text) where text == "{hours}":
            return hours ?? 0
        case let .string(text):
            return substitute(text, nodeID: nodeID, hours: hours)
        case let .array(values):
            return values.map { substituteBody($0, nodeID: nodeID, nodeIDs: nodeIDs, hours: hours) }
        case let .object(values):
            return values.mapValues { substituteBody($0, nodeID: nodeID, nodeIDs: nodeIDs, hours: hours) }
        default:
            return value.foundationObject
        }
    }

    private func metrics(_ fields: [String: ProbeAdapterSpec.FieldMapping], _ item: Any) -> ProbeMetrics {
        ProbeMetrics(
            cpuPercent: number("cpu", fields, item),
            memUsed: int("memUsed", fields, item),
            memTotal: positiveInt("memTotal", fields, item),
            diskUsed: int("diskUsed", fields, item),
            diskTotal: positiveInt("diskTotal", fields, item),
            swapUsed: int("swapUsed", fields, item),
            swapTotal: positiveInt("swapTotal", fields, item),
            netInRate: int("netIn", fields, item),
            netOutRate: int("netOut", fields, item),
            netTotalIn: int("netTotalIn", fields, item),
            netTotalOut: int("netTotalOut", fields, item),
            load1: number("load1", fields, item),
            load5: number("load5", fields, item),
            load15: number("load15", fields, item),
            uptime: int("uptime", fields, item),
            processCount: int("processCount", fields, item).map { Int($0) },
            connectionCount: int("connectionCount", fields, item).map { Int($0) }
        )
    }

    private func number(_ key: String, _ fields: [String: ProbeAdapterSpec.FieldMapping], _ item: Any) -> Double? {
        guard let mapping = fields[key] else { return nil }
        let values = mapping.paths.compactMap { ProbeJSONPath.number(ProbeJSONPath.first($0, in: item)) }
        // 求和字段要求所有路径都有值，避免只拿到一部分时显示偏小的数字。
        guard values.count == mapping.paths.count, !values.isEmpty else { return nil }
        return values.reduce(0, +) * mapping.scale
    }

    private func int(_ key: String, _ fields: [String: ProbeAdapterSpec.FieldMapping], _ item: Any) -> Int64? {
        number(key, fields, item).map { Int64($0.rounded()) }
    }

    /// 总量为 0 表示未提供（例如没有 swap），按缺失处理，避免算出除零百分比。
    private func positiveInt(_ key: String, _ fields: [String: ProbeAdapterSpec.FieldMapping], _ item: Any) -> Int64? {
        int(key, fields, item).flatMap { $0 > 0 ? $0 : nil }
    }

    private func string(_ key: String, _ fields: [String: ProbeAdapterSpec.FieldMapping], _ item: Any) -> String? {
        guard let mapping = fields[key], let path = mapping.paths.first else { return nil }
        return ProbeJSONPath.string(ProbeJSONPath.first(path, in: item))
    }

    private func date(_ key: String, _ fields: [String: ProbeAdapterSpec.FieldMapping], _ item: Any) -> Date? {
        guard let mapping = fields[key], let path = mapping.paths.first else { return nil }
        return ProbeJSONPath.date(ProbeJSONPath.first(path, in: item), format: mapping.format)
    }
}
