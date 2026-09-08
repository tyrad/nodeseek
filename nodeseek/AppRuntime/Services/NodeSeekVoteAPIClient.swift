import CryptoKit
import Foundation

@MainActor
final class NodeSeekVoteAPIClient: NodeSeekVoteServing {
    enum WebRequest {
        case load(Int)
        case submit(Int, Set<Int>)

        var id: Int {
            switch self {
            case .load(let id), .submit(let id, _): return id
            }
        }

        var arguments: [String: Any] {
            switch self {
            case .load(let id): return ["voteID": id, "operation": "load", "ids": []]
            case .submit(let id, let ids): return ["voteID": id, "operation": "submit", "ids": ids.sorted()]
            }
        }
    }

    private let cookieSession: NodeSeekCookieSessionManaging
    private let httpLoad: (URLRequest) async throws -> (Data, URLResponse)
    private let webRequest: (WebRequest) async throws -> Data

    init(
        cookieSession: NodeSeekCookieSessionManaging? = nil,
        httpLoad: @escaping (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) },
        webRequest: ((WebRequest) async throws -> Data)? = nil
    ) {
        self.cookieSession = cookieSession ?? NodeSeekCookieSession()
        self.httpLoad = httpLoad
        self.webRequest = webRequest ?? Self.requestInWebView
    }

    func load(id: Int) async throws -> NodeSeekVote {
        let startedAt = Date()
        await cookieSession.prepareHTTPLoad()
        try Task.checkCancellation()
        let (data, response) = try await httpLoad(Self.makeReadRequest(id: id))
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let result: Data
        if Self.needsWebViewFallback(data: data, response: response) {
            AppLog.info(.service, "投票读取遇到验证，回退 WebView: id=\(id), status=\(response.statusCode)")
            result = try await webRequest(.load(id))
        } else {
            guard (200..<300).contains(response.statusCode) else {
                let message = (try? JSONDecoder().decode(NodeSeekVoteResponse.self, from: data))?.message
                throw NodeSeekVoteError(message: message ?? (response.statusCode == 401 ? "请先登录后参与投票。" : "无法读取投票，请稍后重新进入页面。"))
            }
            result = data
        }
        try Task.checkCancellation()
        let decoded = try JSONDecoder().decode(NodeSeekVoteResponse.self, from: result)
        guard decoded.success else {
            throw NodeSeekVoteError(message: decoded.message ?? "无法读取投票，请稍后重新进入页面。")
        }
        guard let vote = decoded.vote, vote.id == id, !vote.items.isEmpty,
              Set(vote.items.map(\.vote_item_id)).count == vote.items.count,
              vote.items.allSatisfy({ $0.vote_item_id > 0 && ($0.count ?? 0) >= 0 }) else {
            throw NodeSeekVoteError(message: "投票数据不完整，请稍后重新进入页面。")
        }
        AppLog.info(.service, "投票读取完成: id=\(id), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
        return vote
    }

    func submit(id: Int, ids: Set<Int>) async throws {
        try Task.checkCancellation()
        // 网页脚本负责提交前校验；写入只执行一次，结果由调用方重新读取确认。
        _ = try await webRequest(.submit(id, ids))
    }

    private static func makeReadRequest(id: Int) -> URLRequest {
        let url = NodeSeekSite.baseURL.appendingPathComponent("api/vote/info/\(id)")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        WebRequestFingerprint.applyJSONHeaders(to: &request)
        let text = ["GET", url.absoluteString, request.value(forHTTPHeaderField: "User-Agent") ?? "", ""].joined(separator: "\n\n")
        let signature = Insecure.SHA1.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        request.setValue(signature, forHTTPHeaderField: "x-dynamic-sign")
        return request
    }

    private static func needsWebViewFallback(data: Data, response: HTTPURLResponse) -> Bool {
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, field in
            result[String(describing: field.key)] = String(describing: field.value)
        }
        let payload = HTMLResponse(
            statusCode: response.statusCode, headers: headers,
            finalURL: response.url ?? NodeSeekSite.baseURL, html: String(data: data, encoding: .utf8) ?? ""
        )
        switch ChallengeDetector().detect(response: payload) {
        case .cloudflare, .blocked: return true
        default: return false
        }
    }

    private static func requestInWebView(_ request: WebRequest) async throws -> Data {
        let result = try await withHiddenWebViewPageActionLoader(logMessage: "投票 #\(request.id)") { loader in
            try Task.checkCancellation()
            return try await loader.runPageAutomationScript(
                pageURL: NodeSeekSite.baseURL,
                source: VoteAutomationScript.source,
                arguments: request.arguments,
                timeoutInterval: 20,
                actionName: "投票"
            )
        }
        try Task.checkCancellation()
        guard result["ok"] as? Bool == true,
              let body = result["body"] as? String, let data = body.data(using: .utf8) else {
            throw NodeSeekVoteError(message: result["message"] as? String ?? "投票请求失败，请检查登录状态后重新进入页面。")
        }
        return data
    }
}
