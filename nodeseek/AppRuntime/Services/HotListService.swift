//
//  HotListService.swift
//  nodeseek
//

import Foundation

/// App 内共用一份热榜缓存，从不同入口进入时不重复请求。
enum HotListService {
    static let shared = HotListRepository(settings: .shared, loader: load)

    /// 超时与原插件一致；第三方地址不带 NodeSeek Cookie，直接用独立会话。
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.httpShouldSetCookies = false
        // 也不接收第三方的 Set-Cookie，避免写进 App 共享的 Cookie 存储
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }()

    @Sendable
    private static func load(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
