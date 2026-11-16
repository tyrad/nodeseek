//
//  SeekMailTargetType.swift
//  nodeseek
//

import Foundation

/// 仿 Moya 的接口描述：每个接口是一个 case，由 Provider 统一转成 URLRequest。
/// 只覆盖邮箱模块用到的能力，没有引入 Moya 是为了不让包体积增加约 10%。
protocol SeekMailTargetType {
    var baseURL: URL { get }
    var path: String { get }
    var method: SeekMailHTTPMethod { get }
    var task: SeekMailTask { get }
    var headers: [String: String]? { get }
    /// 是否需要带 Bearer Key，默认需要。
    var requiresAuthorization: Bool { get }
    /// 接口需要的 Key 权限，403 时用来提示用户缺哪一项。
    var requiredScope: String? { get }
}

extension SeekMailTargetType {
    var headers: [String: String]? { nil }
    var requiresAuthorization: Bool { true }
    var requiredScope: String? { nil }
}

enum SeekMailHTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

enum SeekMailTask {
    case requestPlain
    /// 参数拼在 URL query 上，值为 nil 的参数会被省略。
    case requestParameters([String: String?])
    /// JSON 请求体，可同时带 query。
    case requestJSON(any Encodable, query: [String: String?] = [:])
}

extension SeekMailTargetType {
    func makeURLRequest(timeoutInterval: TimeInterval) throws -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SeekMailError.invalidRequest
        }

        let query: [String: String?]
        var body: Data?
        switch task {
        case .requestPlain:
            query = [:]
        case .requestParameters(let parameters):
            query = parameters
        case .requestJSON(let encodable, let parameters):
            query = parameters
            body = try JSONEncoder().encode(encodable)
        }

        // 按 key 排序，保证同一请求生成的 URL 稳定，方便测试和日志比对
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
            .sorted { $0.name < $1.name }
        components.queryItems = items.isEmpty ? nil : items
        guard let finalURL = components.url else { throw SeekMailError.invalidRequest }

        var request = URLRequest(url: finalURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeoutInterval)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return request
    }
}
