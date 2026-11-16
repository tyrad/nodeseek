//
//  SeekMailProvider.swift
//  nodeseek
//

import Foundation

struct SeekMailResponse {
    let statusCode: Int
    let data: Data
    let response: HTTPURLResponse
}

/// 每分钟 60 次，取自响应头 x-ratelimit-*。
nonisolated struct SeekMailRateLimit: Equatable, Sendable {
    let limit: Int
    let remaining: Int
    let resetAt: Date?
    /// 额度按分钟窗口计算，太久之前的剩余数已经不准。
    let observedAt: Date

    init?(response: HTTPURLResponse, observedAt: Date = Date()) {
        guard let limit = response.value(forHTTPHeaderField: "x-ratelimit-limit").flatMap(Int.init),
              let remaining = response.value(forHTTPHeaderField: "x-ratelimit-remaining").flatMap(Int.init) else {
            return nil
        }
        self.limit = limit
        self.remaining = remaining
        resetAt = Self.resetDate(response)
        self.observedAt = observedAt
    }

    static func resetDate(_ response: HTTPURLResponse) -> Date? {
        response.value(forHTTPHeaderField: "x-ratelimit-reset")
            .flatMap(TimeInterval.init)
            .map(Date.init(timeIntervalSince1970:))
    }
}

/// 仿 Moya 插件：请求发出前可改写 URLRequest，收到结果后可做记录。
protocol SeekMailPlugin {
    func prepare(_ request: URLRequest, target: any SeekMailTargetType) -> URLRequest
    func didReceive(_ result: Result<SeekMailResponse, Error>, target: any SeekMailTargetType)
}

extension SeekMailPlugin {
    func prepare(_ request: URLRequest, target: any SeekMailTargetType) -> URLRequest { request }
    func didReceive(_ result: Result<SeekMailResponse, Error>, target: any SeekMailTargetType) {}
}

/// 只记方法、路径和状态码，不记请求头，避免 Key 进日志。
struct SeekMailLoggerPlugin: SeekMailPlugin {
    func didReceive(_ result: Result<SeekMailResponse, Error>, target: any SeekMailTargetType) {
        switch result {
        case .success(let response):
            AppLog.info(.service, "seek.li \(target.method.rawValue) \(target.path) status=\(response.statusCode)")
        case .failure(let error):
            AppLog.warning(.service, "seek.li \(target.method.rawValue) \(target.path) failed: \(error)")
        }
    }
}

final class SeekMailProvider<Target: SeekMailTargetType> {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    private let apiKey: () -> String?
    private let transport: Transport
    private let plugins: [SeekMailPlugin]
    private let timeoutInterval: TimeInterval

    /// 最近一次响应里的限流信息，界面可据此暂停自动刷新。
    private(set) var rateLimit: SeekMailRateLimit?

    init(
        apiKey: @escaping () -> String?,
        plugins: [SeekMailPlugin] = [SeekMailLoggerPlugin()],
        timeoutInterval: TimeInterval = 15,
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }
    ) {
        self.apiKey = apiKey
        self.plugins = plugins
        self.timeoutInterval = timeoutInterval
        self.transport = transport
    }

#if compiler(<6.4)
    // Swift 6.2/6.3 优化泛型类型的自动析构时会崩溃，只跳过析构函数的优化。
    // https://github.com/swiftlang/swift/issues/88173
    @_optimize(none)
    deinit {}
#endif

    /// 发出请求并校验状态码，非 2xx 统一转成 SeekMailError。
    func request(_ target: Target) async throws -> SeekMailResponse {
        let result: Result<SeekMailResponse, Error>
        do {
            result = .success(try await perform(target))
        } catch {
            result = .failure(error)
        }
        plugins.forEach { $0.didReceive(result, target: target) }
        return try result.get()
    }

    /// 解出 `{"data": ...}` 里的数据；`data` 为 null 时，数组按空数组处理。
    func request<T: Decodable>(_ target: Target, as type: T.Type) async throws -> T {
        let response = try await request(target)
        let envelope: SeekMailEnvelope<T> = try Self.decode(response.data)
        if let value = envelope.data { return value }
        if let empty = T.self as? SeekMailEmptyRepresentable.Type, let value = empty.emptyValue as? T {
            return value
        }
        throw SeekMailError.decoding(description: "缺少 data 字段")
    }

    /// 直接按整个响应体解码，用于带分页信息的列表。
    func requestRoot<T: Decodable>(_ target: Target, as type: T.Type) async throws -> T {
        try Self.decode(try await request(target).data)
    }

    private func perform(_ target: Target) async throws -> SeekMailResponse {
        var request = try target.makeURLRequest(timeoutInterval: timeoutInterval)
        if target.requiresAuthorization {
            guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), key.isEmpty == false else {
                throw SeekMailError.missingAPIKey
            }
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request = plugins.reduce(request) { $1.prepare($0, target: target) }

        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await transport(request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw SeekMailError.network(error)
        }
        try Task.checkCancellation()

        guard let http = urlResponse as? HTTPURLResponse else {
            throw SeekMailError.network(URLError(.badServerResponse))
        }
        if let limit = SeekMailRateLimit(response: http) { rateLimit = limit }
        guard (200..<300).contains(http.statusCode) else {
            throw SeekMailError.from(
                statusCode: http.statusCode, data: data,
                resetAt: SeekMailRateLimit.resetDate(http), scope: target.requiredScope
            )
        }
        return SeekMailResponse(statusCode: http.statusCode, data: data, response: http)
    }

    static func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try SeekMailJSON.decoder.decode(T.self, from: data)
        } catch {
            throw SeekMailError.decoding(description: String(describing: error))
        }
    }
}

/// 常用接口的类型化入口，调用方不用关心每个接口的响应形状。
extension SeekMailProvider where Target == SeekMailAPI {
    func mailboxes() async throws -> [SeekMailbox] {
        try await request(.mailboxes, as: [SeekMailbox].self)
    }

    func checkMailbox(address: String) async throws -> SeekMailboxAvailability {
        try await request(.checkMailbox(address: address), as: SeekMailboxAvailability.self)
    }

    func createMailbox(address: String) async throws -> SeekMailbox {
        try await request(.createMailbox(address: address), as: SeekMailbox.self)
    }

    func mails(_ query: SeekMailListQuery) async throws -> SeekMailList {
        try await requestRoot(.mails(query), as: SeekMailList.self)
    }

    func unreadMails(limit: Int = 50, cursor: String? = nil, afterID: Int64? = nil) async throws -> SeekUnreadMailPage {
        try await requestRoot(.unreadMails(limit: limit, cursor: cursor, afterID: afterID), as: SeekUnreadMailPage.self)
    }

    func mail(id: Int64) async throws -> SeekMailDetail {
        try await request(.mail(id: id), as: SeekMailDetail.self)
    }

    func unreadCounts() async throws -> SeekMailUnreadCounts {
        try await request(.mailCounts, as: SeekMailUnreadCounts.self)
    }

    func markRead(id: Int64, read: Bool) async throws {
        _ = try await request(.markRead(id: id, read: read))
    }

    func markFlagged(id: Int64, flagged: Bool) async throws {
        _ = try await request(.markFlagged(id: id, flagged: flagged))
    }

    func moveMail(id: Int64, folderID: Int64?) async throws {
        _ = try await request(.moveMail(id: id, folderID: folderID))
    }

    func deleteMail(id: Int64) async throws {
        _ = try await request(.deleteMail(id: id))
    }

    func rawMail(id: Int64) async throws -> String {
        String(decoding: try await request(.rawMail(id: id)).data, as: UTF8.self)
    }

    func attachments(mailID: Int64) async throws -> [SeekMailAttachment] {
        try await request(.attachments(mailID: mailID), as: [SeekMailAttachment].self)
    }

    func downloadAttachment(mailID: Int64, index: Int) async throws -> SeekMailFile {
        let response = try await request(.downloadAttachment(mailID: mailID, index: index))
        return SeekMailFile(
            data: response.data,
            filename: response.response.suggestedFilename,
            contentType: response.response.mimeType
        )
    }

    func folders() async throws -> [SeekMailFolder] {
        try await request(.folders, as: [SeekMailFolder].self)
    }

    func quota() async throws -> SeekMailQuota {
        try await request(.quotas, as: SeekMailQuota.self)
    }

    func send(_ draft: SeekMailDraft) async throws -> SeekMailSendResult {
        try await request(.send(draft), as: SeekMailSendResult.self)
    }
}

private nonisolated struct SeekMailEnvelope<T: Decodable>: Decodable {
    let data: T?
}

/// 服务端在列表为空时返回 `data: null`，这些类型按空值处理。
private protocol SeekMailEmptyRepresentable {
    static var emptyValue: Any { get }
}

extension Array: SeekMailEmptyRepresentable {
    fileprivate static var emptyValue: Any { [Element]() }
}

nonisolated enum SeekMailJSON {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "无法解析时间：\(text)")
            }
            return date
        }
        return decoder
    }

    /// 服务端时间可能带 9 位纳秒，ISO8601DateFormatter 只认 3 位，先截到毫秒。
    nonisolated static func date(from rawValue: String) -> Date? {
        var text = rawValue
        if let dot = text.firstIndex(of: ".") {
            let start = text.index(after: dot)
            let end = text[start...].firstIndex { $0.isNumber == false } ?? text.endIndex
            if text.distance(from: start, to: end) > 3 {
                text.replaceSubrange(start..<end, with: text[start..<end].prefix(3))
            }
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
