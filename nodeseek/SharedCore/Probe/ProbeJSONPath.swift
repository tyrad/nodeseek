import Foundation

/// 极简 JSON 路径：`$`、`.key`、`[n]`、`[*]`（数组展开）、`.*`（字典的值展开）。
/// 只做取值，不支持过滤和表达式，避免配置文件变成脚本。
nonisolated enum ProbeJSONPath {
    nonisolated enum Step: Equatable {
        case key(String)
        case index(Int)
        case allElements
        case allValues
    }

    static func parse(_ path: String) -> [Step]? {
        guard path.hasPrefix("$") else { return nil }
        var steps: [Step] = []
        var rest = Substring(path.dropFirst())
        while !rest.isEmpty {
            if rest.hasPrefix(".*") {
                steps.append(.allValues)
                rest = rest.dropFirst(2)
            } else if rest.hasPrefix("[*]") {
                steps.append(.allElements)
                rest = rest.dropFirst(3)
            } else if rest.hasPrefix("[") {
                guard let close = rest.firstIndex(of: "]"), let index = Int(rest[rest.index(after: rest.startIndex)..<close]) else { return nil }
                steps.append(.index(index))
                rest = rest[rest.index(after: close)...]
            } else if rest.hasPrefix(".") {
                rest = rest.dropFirst()
                let end = rest.firstIndex { $0 == "." || $0 == "[" } ?? rest.endIndex
                let key = String(rest[..<end])
                guard !key.isEmpty else { return nil }
                steps.append(.key(key))
                rest = rest[end...]
            } else {
                return nil
            }
        }
        return steps
    }

    /// 返回所有匹配值；包含展开步骤时可能多于一个。
    static func values(_ path: String, in root: Any) -> [Any] {
        guard let steps = parse(path) else { return [] }
        var current: [Any] = [root]
        for step in steps {
            var next: [Any] = []
            for value in current {
                switch step {
                case let .key(key):
                    if let dict = value as? [String: Any], let child = dict[key], !(child is NSNull) { next.append(child) }
                case let .index(index):
                    if let array = value as? [Any], array.indices.contains(index) { next.append(array[index]) }
                case .allElements:
                    if let array = value as? [Any] { next.append(contentsOf: array) }
                case .allValues:
                    if let dict = value as? [String: Any] {
                        // 字典无序，按键排序保证结果稳定。
                        next.append(contentsOf: dict.keys.sorted().compactMap { dict[$0] })
                    }
                }
            }
            current = next
        }
        return current
    }

    static func first(_ path: String, in root: Any) -> Any? {
        values(path, in: root).first
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let double = number.doubleValue
            return double.isFinite ? double : nil
        case let text as String:
            return Double(text.trimmingCharacters(in: .whitespaces))
        default:
            return nil
        }
    }

    static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return number.stringValue
        default:
            return nil
        }
    }

    /// 只有日期的写法（到期日 2030-01-01）按本地时区的当天零点算，剩余天数才和用户的日历一致。
    private static func day(_ text: String) -> Date? {
        guard text.count == 10 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    /// 解析时间。ISO 8601 小数部分超过 3 位（Komari 为纳秒）时先截到毫秒。
    static func date(_ value: Any?, format: ProbeAdapterSpec.FieldMapping.Format) -> Date? {
        switch format {
        case .unixSeconds:
            return number(value).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
        case .unixMillis:
            return number(value).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil }
        case .iso8601, .number, .string:
            guard var text = string(value) else { return nil }
            if let dot = text.firstIndex(of: ".") {
                let start = text.index(after: dot)
                let end = text[start...].firstIndex { !$0.isNumber } ?? text.endIndex
                if text.distance(from: start, to: end) > 3 {
                    text.replaceSubrange(start..<end, with: text[start..<end].prefix(3))
                }
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date.timeIntervalSince1970 > 0 ? date : nil }
            return day(text)
        }
    }
}
