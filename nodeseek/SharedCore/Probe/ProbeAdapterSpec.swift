import Foundation

/// 探针适配器配置：用纯数据描述“请求哪些接口、字段如何映射到统一模型”。
/// 只描述数据，不包含可执行代码；引擎只支持下面列出的固定能力。
nonisolated struct ProbeAdapterSpec: Decodable, Equatable, Sendable {
    static let supportedSpecVersion = 1

    let id: String
    let name: String
    let specVersion: Int
    /// 添加探针页的简短说明，例如“读取公开数据，不需要账号”。
    let summary: String?
    let auth: Auth
    let requests: [String: RequestTemplate]
    let version: ValueSource?
    /// 读取节点前的检查，例如 Komari 的私有站点开关。
    let preflight: [Check]?
    let nodes: Collection
    let status: StatusMapping
    let history: Collection?
    let errors: [ErrorRule]?

    nonisolated enum Auth: Decodable, Equatable, Sendable {
        case none
        /// 令牌只放进指定请求头，且只发往用户填写的面板域名。
        case header(name: String, prefix: String)

        private enum CodingKeys: String, CodingKey { case type, header, prefix }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .type) {
            case "none":
                self = .none
            case "header":
                self = .header(
                    name: try container.decode(String.self, forKey: .header),
                    prefix: try container.decodeIfPresent(String.self, forKey: .prefix) ?? ""
                )
            case let other:
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "不支持的认证方式 \(other)")
            }
        }
    }

    nonisolated struct RequestTemplate: Decodable, Equatable, Sendable {
        let method: String
        /// 只允许以 / 开头的相对路径，可包含 `{nodeID}` 占位符。
        let path: String
        let query: [String: String]?
        /// JSON 请求体；字符串值整体等于 `{nodeIDs}` 时替换为节点 ID 数组。
        let body: JSONValue?
    }

    nonisolated struct ValueSource: Decodable, Equatable, Sendable {
        let request: String
        let path: String
    }

    nonisolated struct Check: Decodable, Equatable, Sendable {
        let request: String
        let path: String
        let equals: JSONValue
        let error: ProbeFetchError
    }

    nonisolated struct Collection: Decodable, Equatable, Sendable {
        let request: String
        /// 指向条目的路径，支持 `[*]`（数组）和 `.*`（字典的值）。
        let items: String
        let fields: [String: FieldMapping]
    }

    nonisolated struct StatusMapping: Decodable, Equatable, Sendable {
        let request: String
        let items: String
        let fields: [String: FieldMapping]
        let online: OnlineRule
    }

    nonisolated enum OnlineRule: Decodable, Equatable, Sendable {
        /// 布尔字段直接给出在线状态。
        case bool(path: String)
        /// 时间字段距今不超过 `seconds` 视为在线（哪吒等没有 online 字段的探针）。
        case freshness(path: String, format: FieldMapping.Format, seconds: Double)

        private enum CodingKeys: String, CodingKey { case type, path, format, seconds }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let path = try container.decode(String.self, forKey: .path)
            switch try container.decode(String.self, forKey: .type) {
            case "bool":
                self = .bool(path: path)
            case "freshness":
                self = .freshness(
                    path: path,
                    format: try container.decodeIfPresent(FieldMapping.Format.self, forKey: .format) ?? .iso8601,
                    seconds: try container.decode(Double.self, forKey: .seconds)
                )
            case let other:
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "不支持的在线规则 \(other)")
            }
        }
    }

    /// 字段映射：可以直接写路径字符串，也可以写对象指定格式、倍数或求和。
    nonisolated struct FieldMapping: Decodable, Equatable, Sendable {
        nonisolated enum Format: String, Decodable, Sendable {
            case number, string, iso8601, unixSeconds, unixMillis
        }

        let paths: [String]
        let format: Format
        let scale: Double

        private enum CodingKeys: String, CodingKey { case path, sum, format, scale }

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer().decode(String.self) {
                paths = [single]
                format = .number
                scale = 1
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let sum = try container.decodeIfPresent([String].self, forKey: .sum) {
                paths = sum
            } else {
                paths = [try container.decode(String.self, forKey: .path)]
            }
            format = try container.decodeIfPresent(Format.self, forKey: .format) ?? .number
            scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        }
    }

    nonisolated struct ErrorRule: Decodable, Equatable, Sendable {
        let status: Int?
        let bodyContains: String?
        let path: String?
        let equals: JSONValue?
        let error: ProbeFetchError
    }
}

/// 配置里使用的 JSON 值。
nonisolated enum JSONValue: Decodable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    /// 转成 JSONSerialization 可用的对象。
    var foundationObject: Any {
        switch self {
        case let .string(value): return value
        case let .number(value): return value.rounded() == value && abs(value) < 1e15 ? Int(value) as Any : value
        case let .bool(value): return value
        case let .array(values): return values.map(\.foundationObject)
        case let .object(values): return values.mapValues(\.foundationObject)
        case .null: return NSNull()
        }
    }

    /// 与 JSONSerialization 解析出的值比较。
    func matches(_ value: Any?) -> Bool {
        switch self {
        case let .string(expected): return (value as? String) == expected
        case let .bool(expected):
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
            return number.boolValue == expected
        case let .number(expected): return ProbeJSONPath.number(value) == expected
        case .null: return value == nil || value is NSNull
        case .array, .object: return false
        }
    }
}
