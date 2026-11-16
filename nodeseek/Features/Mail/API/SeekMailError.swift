//
//  SeekMailError.swift
//  nodeseek
//

import Foundation

nonisolated enum SeekMailError: Error, Equatable, Sendable {
    /// 本机还没有保存 API Key。
    case missingAPIKey
    /// Key 无效或已失效（401）。
    case unauthorized(message: String?)
    /// Key 有效但没勾选这个接口需要的权限（403）；scope 为接口对应的权限名。
    case forbidden(scope: String?, message: String?)
    /// 429 或认证限流；resetAt 来自 x-ratelimit-reset。
    case rateLimited(resetAt: Date?)
    case notFound(message: String?)
    case badRequest(message: String?)
    /// 发信被服务端拒绝，例如「该域名已禁止发信」。
    case sendFailed(message: String?)
    case server(statusCode: Int, code: String?, message: String?)
    case invalidRequest
    case decoding(description: String)
    case network(URLError)

    var userMessage: String {
        switch self {
        case .missingAPIKey: return SeekMailL10n.text("请先绑定 seek.li API Key")
        case .unauthorized: return SeekMailL10n.text("API Key 无效或已失效，请重新绑定")
        case .forbidden(let scope, _):
            return scope.map { SeekMailL10n.format("API Key 缺少 %@ 权限，请在 seek.li 重新创建 Key", $0) } ?? SeekMailL10n.text("API Key 权限不足")
        case .rateLimited: return SeekMailL10n.text("请求太频繁，请稍后再试")
        case .notFound(let message): return message ?? SeekMailL10n.text("邮件不存在或已被删除")
        case .badRequest(let message): return message ?? SeekMailL10n.text("请求参数有误")
        case .sendFailed(let message): return message ?? SeekMailL10n.text("发送失败，请稍后重试")
        case .server(_, _, let message): return message ?? SeekMailL10n.text("seek.li 服务暂时不可用")
        case .invalidRequest: return SeekMailL10n.text("请求参数有误")
        case .decoding: return SeekMailL10n.text("邮箱数据格式异常")
        case .network: return SeekMailL10n.text("网络连接失败，请检查网络")
        }
    }

    /// 服务端错误体有两种：`{"error":{"code","message"}}` 和 `{"error":"文本"}`。
    static func from(statusCode: Int, data: Data, resetAt: Date?, scope: String? = nil) -> SeekMailError {
        let body = try? JSONDecoder().decode(SeekMailErrorBody.self, from: data)
        let code = body?.code
        let message = body?.message

        if statusCode == 429 || code == "AUTH_RATE_LIMITED" || code == "RATE_LIMITED" {
            return .rateLimited(resetAt: resetAt)
        }
        if code == "SEND_FAILED" { return .sendFailed(message: message) }
        switch statusCode {
        case 401: return .unauthorized(message: message)
        case 403: return .forbidden(scope: scope, message: message)
        case 404: return .notFound(message: message)
        case 400: return .badRequest(message: message)
        default: return .server(statusCode: statusCode, code: code, message: message)
        }
    }
}

private nonisolated struct SeekMailErrorBody: Decodable {
    let code: String?
    let message: String?

    private enum CodingKeys: String, CodingKey { case error }
    private enum DetailKeys: String, CodingKey { case code, message }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? container.decode(String.self, forKey: .error) {
            code = nil
            message = text
            return
        }
        let detail = try container.nestedContainer(keyedBy: DetailKeys.self, forKey: .error)
        code = try detail.decodeIfPresent(String.self, forKey: .code)
        message = try detail.decodeIfPresent(String.self, forKey: .message)
    }
}
