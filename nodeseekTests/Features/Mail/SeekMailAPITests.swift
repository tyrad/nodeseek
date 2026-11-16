import Foundation
import Testing
@testable import nodeseek

/// 响应样例取自 2026-11-16 实测，地址、姓名已替换为假值。
@MainActor
struct SeekMailAPITests {
    // MARK: - 请求构造

    @Test func mailListQueryOmitsEmptyParameters() throws {
        let query = SeekMailListQuery(mailboxID: 7, folder: .inbox, search: "  ", limit: 20, offset: 40)
        let request = try SeekMailAPI.mails(query).makeURLRequest(timeoutInterval: 15)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString
            == "https://seek.li/openapi/v1/mails?folder=inbox&limit=20&mailbox_id=7&offset=40")
        #expect(request.httpBody == nil)
    }

    @Test func unreadEmptyCursorIsOmitted() throws {
        let request = try SeekMailAPI.unreadMails(limit: 10, cursor: "", afterID: 99).makeURLRequest(timeoutInterval: 15)
        #expect(request.url?.query == "after_id=99&limit=10")
    }

    @Test func moveToInboxSendsExplicitNull() throws {
        let request = try SeekMailAPI.moveMail(id: 5, folderID: nil).makeURLRequest(timeoutInterval: 15)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/openapi/v1/mails/5/folder")
        #expect(try jsonObject(request.httpBody) as NSDictionary == ["folderId": NSNull()])
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func sendJoinsRecipientsIntoString() throws {
        let draft = SeekMailDraft(
            mailboxID: 3, to: ["a@seek.li", " b@example.com "], subject: "Hi", bodyText: "正文"
        )
        let request = try SeekMailAPI.send(draft).makeURLRequest(timeoutInterval: 15)
        #expect(request.httpMethod == "POST")
        #expect(try jsonObject(request.httpBody) as NSDictionary == [
            "mailboxId": 3, "to": "a@seek.li,b@example.com", "subject": "Hi", "bodyText": "正文"
        ])
    }

    @Test func markReadUsesPutWithBoolBody() throws {
        let request = try SeekMailAPI.markRead(id: 8, read: false).makeURLRequest(timeoutInterval: 15)
        #expect(request.httpMethod == "PUT")
        #expect(try jsonObject(request.httpBody) as NSDictionary == ["read": false])
    }

    @Test func providerAddsBearerKey() async throws {
        let stub = TransportStub(body: #"{"data":[]}"#)
        _ = try await makeProvider(stub, key: " sk_live_test ").mailboxes()
        #expect(stub.request?.value(forHTTPHeaderField: "Authorization") == "Bearer sk_live_test")
    }

    @Test func missingKeyFailsBeforeSending() async {
        let stub = TransportStub(body: #"{"data":[]}"#)
        await #expect(throws: SeekMailError.missingAPIKey) {
            _ = try await makeProvider(stub, key: nil).mailboxes()
        }
        #expect(stub.request == nil)
    }

    // MARK: - 响应解析

    @Test func decodesMailListWithPagination() async throws {
        let stub = TransportStub(body: """
        {"data":[{"id":467841,"mailboxId":43666,"orgId":1,"fromAddress":"noreply@example.com","fromName":"Example",
        "toAddress":"me@nodeseek.org","subject":"Maintenance","bodyText":"摘要","bodyHtml":"","isRead":true,
        "isFlagged":false,"hasAttachments":true,"isPinned":false,"status":"active","pendingAt":null,
        "receivedAt":"2026-11-04T20:48:12Z","size":9579,"tags":null}],
        "pagination":{"limit":1,"offset":0,"total":26}}
        """)
        let list = try await makeProvider(stub).mails(SeekMailListQuery())
        #expect(list.mails.count == 1)
        #expect(list.mails[0].subject == "Maintenance")
        #expect(list.mails[0].hasAttachments)
        #expect(list.mails[0].folderId == nil)
        #expect(list.mails[0].receivedAt == Date(timeIntervalSince1970: 1_793_825_292))
        #expect(list.pagination?.hasMore == true)
    }

    @Test func nullDataBecomesEmpty() async throws {
        let stub = TransportStub(body: #"{"data":null,"pagination":{"limit":20,"offset":0,"total":0}}"#)
        let provider = makeProvider(stub)
        #expect(try await provider.mails(SeekMailListQuery(folder: .trash)).mails.isEmpty)
        stub.body = Data(#"{"data":null}"#.utf8)
        #expect(try await provider.folders().isEmpty)
    }

    @Test func decodesNestedMailDetail() async throws {
        let stub = TransportStub(body: """
        {"data":{"mail":{"id":505995,"mailboxId":43656,"fromAddress":"test@seek.li","fromName":"",
        "subject":"验证码","bodyText":"您的验证码是 482913","bodyHtml":"<p>482913</p>",
        "verificationCode":"482913","isRead":false,"isFlagged":false,"hasAttachments":false,
        "receivedAt":"2026-11-16T01:02:02Z"},"tags":null}}
        """)
        let detail = try await makeProvider(stub).mail(id: 505995)
        #expect(detail.mail.bodyHtml == "<p>482913</p>")
        #expect(detail.mail.fromName == nil)
        #expect(detail.mail.verificationCode == "482913")
        #expect(detail.tags.isEmpty)
    }

    @Test func decodesUnreadPageWithCode() async throws {
        let stub = TransportStub(body: """
        {"data":[{"id":505995,"mailboxId":43656,"mailboxAddress":"me@nodeseek.org","fromAddress":"test@seek.li",
        "fromName":"","subject":"验证码","verificationCode":"482913","receivedAt":"2026-11-16T01:02:02Z"}],
        "page":{"hasMore":false,"limit":50,"nextCursor":""}}
        """)
        let page = try await makeProvider(stub).unreadMails()
        #expect(page.mails.first?.verificationCode == "482913")
        #expect(page.page?.hasMore == false)
        #expect(page.page?.nextCursor == nil)
    }

    @Test func parsesNanosecondDates() {
        let date = SeekMailJSON.date(from: "2026-11-16T01:02:01.785362836Z")
        #expect(date == SeekMailJSON.date(from: "2026-11-16T01:02:01.785Z"))
        #expect(date != nil)
    }

    @Test func decodesUnreadCounts() async throws {
        let stub = TransportStub(body: #"{"data":{"mailboxes":{"43731":8},"total":8}}"#)
        let counts = try await makeProvider(stub).unreadCounts()
        #expect(counts.byMailbox == [43731: 8])
        #expect(counts.total == 8)
    }

    @Test func recordsRateLimitHeaders() async throws {
        let stub = TransportStub(body: #"{"data":[]}"#, headers: [
            "x-ratelimit-limit": "60", "x-ratelimit-remaining": "57", "x-ratelimit-reset": "1794790530"
        ])
        let provider = makeProvider(stub)
        _ = try await provider.mailboxes()
        #expect(provider.rateLimit?.remaining == 57)
        #expect(provider.rateLimit?.resetAt == Date(timeIntervalSince1970: 1_794_790_530))
    }

    // MARK: - 错误

    @Test(arguments: [
        (401, #"{"error":{"code":"UNAUTHORIZED","message":"无效的 API Key"}}"#, SeekMailError.unauthorized(message: "无效的 API Key")),
        (400, #"{"error":"无效的ID"}"#, SeekMailError.badRequest(message: "无效的ID")),
        (500, #"{"error":{"code":"SEND_FAILED","message":"该域名已禁止发信"}}"#, SeekMailError.sendFailed(message: "该域名已禁止发信")),
        (401, #"{"error":{"code":"AUTH_RATE_LIMITED","message":"认证失败次数过多"}}"#, SeekMailError.rateLimited(resetAt: nil)),
        (502, "<html>Bad Gateway</html>", SeekMailError.server(statusCode: 502, code: nil, message: nil))
    ])
    func mapsErrorResponses(status: Int, body: String, expected: SeekMailError) async {
        let stub = TransportStub(body: body, status: status)
        await #expect(throws: expected) {
            _ = try await makeProvider(stub).mailboxes()
        }
    }

    @Test func mapsNetworkFailure() async {
        let stub = TransportStub(body: "")
        stub.error = URLError(.notConnectedToInternet)
        await #expect(throws: SeekMailError.network(URLError(.notConnectedToInternet))) {
            _ = try await makeProvider(stub).mailboxes()
        }
    }

    @Test func nodeseekDomainCannotSend() throws {
        let data = Data(#"[{"id":1,"address":"a@nodeseek.org"},{"id":2,"address":"b@seek.li"}]"#.utf8)
        let mailboxes = try SeekMailJSON.decoder.decode([SeekMailbox].self, from: data)
        #expect(mailboxes.map(\.canSendMail) == [false, true])
    }

    // MARK: - 辅助

    private func makeProvider(_ stub: TransportStub, key: String? = "sk_live_test") -> SeekMailProvider<SeekMailAPI> {
        SeekMailProvider(apiKey: { key }, plugins: [], transport: stub.load)
    }

    private func jsonObject(_ data: Data?) throws -> NSDictionary {
        let data = try #require(data)
        return try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }
}

@MainActor
private final class TransportStub {
    var body: Data
    var status: Int
    var headers: [String: String]
    var error: Error?
    private(set) var request: URLRequest?

    init(body: String, status: Int = 200, headers: [String: String] = [:]) {
        self.body = Data(body.utf8)
        self.status = status
        self.headers = headers
    }

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        if let error { throw error }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        return (body, response)
    }
}
