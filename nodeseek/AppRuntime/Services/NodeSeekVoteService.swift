import CryptoKit
import Foundation

@MainActor
protocol NodeSeekVoteServing: AnyObject {
    func load(id: Int) async throws -> NodeSeekVote
    func submit(id: Int, ids: Set<Int>) async throws
}

struct NodeSeekVoteError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension Notification.Name {
    static let nodeSeekVoteDidChange = Notification.Name("nodeSeekVoteDidChange")
}

@MainActor
final class NodeSeekVoteService: NodeSeekVoteServing {
    static let shared = NodeSeekVoteService()
    private struct Read {
        let token: UUID
        let task: Task<NodeSeekVote, Error>
    }
    private var reads: [Int: Read] = [:]
    private var revisions: [Int: Int] = [:]
    private var submissions: Set<Int> = []
    private var sessionGeneration = 0
    private let cookieSession: NodeSeekCookieSessionManaging
    private let httpLoad: (URLRequest) async throws -> (Data, URLResponse)
    private let webRequestOverride: ((Int, Set<Int>?) async throws -> Data)?

    init(
        cookieSession: NodeSeekCookieSessionManaging? = nil,
        httpLoad: @escaping (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) },
        webRequest: ((Int, Set<Int>?) async throws -> Data)? = nil
    ) {
        self.cookieSession = cookieSession ?? NodeSeekCookieSession()
        self.httpLoad = httpLoad
        self.webRequestOverride = webRequest
        NotificationCenter.default.addObserver(self, selector: #selector(sessionChanged), name: .nodeSeekLoginSessionDidClose, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func sessionChanged() {
        sessionGeneration += 1
        reads.values.forEach { $0.task.cancel() }
        reads.removeAll()
    }

    func load(id: Int) async throws -> NodeSeekVote {
        let generation = sessionGeneration
        let revision = revisions[id, default: 0]
        if let read = reads[id] {
            let vote = try await read.task.value
            guard generation == sessionGeneration else { throw CancellationError() }
            if revision != revisions[id, default: 0] { return try await load(id: id) }
            return vote
        }
        let token = UUID()
        let task = Task { () throws -> NodeSeekVote in
            let data = try await self.request(id: id, ids: nil)
            let response = try JSONDecoder().decode(NodeSeekVoteResponse.self, from: data)
            guard response.success, let vote = response.vote, vote.id == id,
                  !vote.items.isEmpty, Set(vote.items.map(\.vote_item_id)).count == vote.items.count,
                  vote.items.allSatisfy({ $0.vote_item_id > 0 && ($0.count ?? 0) >= 0 }) else {
                throw NodeSeekVoteError(message: "投票数据不完整，请打开网页查看。")
            }
            return vote
        }
        reads[id] = Read(token: token, task: task)
        defer { if reads[id]?.token == token { reads[id] = nil } }
        let vote = try await task.value
        guard generation == sessionGeneration else { throw CancellationError() }
        if revision != revisions[id, default: 0] { return try await load(id: id) }
        return vote
    }

    func submit(id: Int, ids: Set<Int>) async throws {
        guard !submissions.contains(id) else { throw NodeSeekVoteError(message: "正在提交该投票，请稍候。") }
        submissions.insert(id)
        defer {
            submissions.remove(id)
            revisions[id, default: 0] += 1
            reads[id] = nil
            NotificationCenter.default.post(name: .nodeSeekVoteDidChange, object: id)
        }
        // 不重试写请求；成功与失败都由界面重新读取服务端状态。
        _ = try await request(id: id, ids: ids)
    }

    private func request(id: Int, ids: Set<Int>?) async throws -> Data {
        let generation = sessionGeneration
        let startedAt = Date()
        // 读取无需先导航到首页，也不占用串行的网页动作队列。
        // 写入仍走已有网页流程，保留提交前校验和禁止重试的语义。
        if ids == nil {
            await cookieSession.prepareHTTPLoad()
            try Task.checkCancellation()
            guard generation == sessionGeneration else { throw CancellationError() }
            let (data, response) = try await httpLoad(Self.makeReadRequest(id: id))
            try Task.checkCancellation()
            guard generation == sessionGeneration else { throw CancellationError() }
            guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if !Self.needsWebViewFallback(data: data, response: response) {
                guard (200..<300).contains(response.statusCode) else {
                    let message = (try? JSONDecoder().decode(NodeSeekVoteResponse.self, from: data))?.message
                    throw NodeSeekVoteError(message: message ?? (response.statusCode == 401 ? "请先登录后参与投票。" : "无法读取投票，请稍后刷新。"))
                }
                AppLog.info(.service, "投票读取完成: id=\(id), transport=http, elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
                return data
            }
            AppLog.info(.service, "投票读取遇到验证，回退 WebView: id=\(id), status=\(response.statusCode), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
        }
        let data: Data
        if let webRequestOverride {
            data = try await webRequestOverride(id, ids)
        } else {
            data = try await requestInWebView(id: id, ids: ids, generation: generation)
        }
        guard generation == sessionGeneration else { throw CancellationError() }
        AppLog.info(.service, "投票请求完成: id=\(id), transport=webview, elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
        return data
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

    private func requestInWebView(id: Int, ids: Set<Int>?, generation: Int) async throws -> Data {
        let result = try await withHiddenWebViewPageActionLoader(logMessage: "读取或提交投票 #\(id)") { loader in
            guard generation == self.sessionGeneration else { throw CancellationError() }
            return try await loader.runPageAutomationScript(
                pageURL: NodeSeekSite.baseURL,
                source: VoteAutomationScript.source,
                arguments: ["voteID": id, "operation": ids == nil ? "load" : "submit", "ids": ids?.sorted() ?? []],
                timeoutInterval: 20,
                actionName: "投票"
            )
        }
        guard generation == sessionGeneration else { throw CancellationError() }
        guard result["ok"] as? Bool == true,
              let body = result["body"] as? String, let data = body.data(using: .utf8) else {
            throw NodeSeekVoteError(message: result["message"] as? String ?? "无法读取投票，请打开网页检查登录或验证状态。")
        }
        return data
    }
}
