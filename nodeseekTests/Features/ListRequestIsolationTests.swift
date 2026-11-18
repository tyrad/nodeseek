import AsyncDisplayKit
import UIKit
import Testing
@testable import nodeseek

@MainActor
@Suite(.serialized)
struct ListRequestIsolationTests {
    // 通过真实控制器入口发请求，URLProtocol 仅控制返回顺序，不调用私有完成方法。
    @Test func testUserContentIgnoresOldPagination() async throws {
        for kind in ["collections", "discussions", "comments"] {
            for outcome in ["data", "empty", "failure"] {
                IsolationURLProtocol.reset()
                let config = URLSessionConfiguration.ephemeral
                config.protocolClasses = [IsolationURLProtocol.self]
                let session = URLSession(configuration: config)
                let client = NodeSeekUserContentClient(session: session)
                let controller: UIViewController
                switch kind {
                case "collections": controller = UserCollectionsViewController(uid: 1, client: client)
                case "discussions": controller = UserDiscussionsViewController(uid: 1, client: client)
                default: controller = UserCommentsViewController(uid: 1, client: client)
                }
                controller.loadViewIfNeeded()
                try await until { IsolationURLProtocol.count == 1 }
                try IsolationURLProtocol.reply(0, kind: kind, ids: [1])
                try await until { self.value(controller, "isLoadingFirstPage", as: Bool.self) == false }
                let table = ASTableNode()
                func paginate() {
                    let context = ASBatchContext()
                    if let c = controller as? UserCollectionsViewController { c.tableNode(table, willBeginBatchFetchWith: context) }
                    if let c = controller as? UserDiscussionsViewController { c.tableNode(table, willBeginBatchFetchWith: context) }
                    if let c = controller as? UserCommentsViewController { c.tableNode(table, willBeginBatchFetchWith: context) }
                }
                paginate()
                try await until { IsolationURLProtocol.count == 2 }
                controller.perform(NSSelectorFromString("refreshTriggered"))
                try await until { IsolationURLProtocol.count == 3 }
                try IsolationURLProtocol.reply(2, kind: kind, ids: [10, 12])
                try await until { self.value(controller, "isLoadingFirstPage", as: Bool.self) == false }
                // 新批次分页仍在进行，旧回调不能清除它的 loading 状态。
                paginate()
                try await until { IsolationURLProtocol.count == 4 }
                try IsolationURLProtocol.reply(1, kind: kind, ids: outcome == "data" ? [99] : [], failure: outcome == "failure")
                try await Task.sleep(nanoseconds: 100_000_000)
                #expect(value(controller, "isLoadingMore", as: Bool.self) == true)
                #expect(value(controller, "hasMorePages", as: Bool.self) == true)
                #expect(value(controller, "nextPage", as: Int.self) == 2)
                try IsolationURLProtocol.reply(3, kind: kind, ids: [12, 11, 13])
                try await until { self.value(controller, "isLoadingMore", as: Bool.self) == false }
                let records = try #require(Mirror(reflecting: controller).descendant("records"))
                let ids = Mirror(reflecting: records).children.compactMap { Mirror(reflecting: $0.value).descendant("postID") as? Int }
                #expect(ids == [10, 12, 11, 13])
                #expect(IsolationURLProtocol.pages == [1, 2, 1, 2])
                #expect(value(controller, "nextPage", as: Int.self) == 3)
                session.invalidateAndCancel()
            }
        }
    }

    @Test func testSearchRefreshBlocksPaginationAndRepeatedRefresh() async throws {
        let client = IsolationHTMLClient()
        let controller = SearchViewController(service: NodeSeekService(htmlClient: client, parser: IsolationParser()))
        controller.loadViewIfNeeded()
        let field = try #require(views(controller.view).compactMap { $0 as? UITextField }.first)
        let button = try #require(views(controller.view).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "search-submit-button" })
        field.text = "isolation-test"
        button.sendActions(for: .touchUpInside)
        try await until { await client.count == 1 }
        await client.reply(0, html: "old-1,old-2")
        try await until { self.value(controller, "isLoadingFirstPage", as: Bool.self) == false }
        let list = PostTextureListView()
        controller.postTextureListViewDidRequestRefresh(list)
        try await until { await client.count == 2 }
        controller.postTextureListViewDidRequestRefresh(list)
        controller.postTextureListView(list, didApproachBottomAt: 0, totalCount: 1)
        try await Task.sleep(nanoseconds: 100_000_000)
        let count = await client.count
        #expect(count == 2)
        await client.reply(1, html: "new-1,new-2")
        try await until { self.value(controller, "isRefreshing", as: Bool.self) == false }
        controller.postTextureListView(list, didApproachBottomAt: 0, totalCount: 1)
        try await until { await client.count == 3 }
        await client.reply(2, html: "new-2,new-3,new-4")
        try await until { self.value(controller, "isLoadingMore", as: Bool.self) == false }
        let items = try #require(value(controller, "items", as: [PostListItem].self))
        #expect(items.map { $0.post.id } == ["new-1", "new-2", "new-3", "new-4"])
        let results = try #require(value(controller, "listView", as: PostTextureListView.self))
        let table = try #require(views(results).compactMap { $0 as? UITableView }.first)
        table.layoutIfNeeded()
        #expect(table.numberOfRows(inSection: 0) == 4)
        #expect(value(controller, "nextPage", as: Int.self) == 3)
        controller.postTextureListView(list, didApproachBottomAt: 3, totalCount: 4)
        try await until { await client.count == 4 }
        await client.reply(3, html: "")
        try await until { self.value(controller, "isLoadingMore", as: Bool.self) == false }
        #expect(value(controller, "hasMorePages", as: Bool.self) == false)
        let pages = await client.pages
        #expect(pages == [1, 1, 2, 3])
    }

    @Test func testSearchRejectsOldFailureForSameQueryAndCanRetry() async throws {
        let client = IsolationHTMLClient()
        let controller = SearchViewController(service: NodeSeekService(htmlClient: client, parser: IsolationParser()))
        controller.loadViewIfNeeded()
        let field = try #require(views(controller.view).compactMap { $0 as? UITextField }.first)
        let button = try #require(views(controller.view).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "search-submit-button" })
        field.text = "same-query"
        button.sendActions(for: .touchUpInside)
        try await until { await client.count == 1 }
        button.sendActions(for: .touchUpInside)
        try await until { await client.count == 2 }
        // 取消不保证网络以 CancellationError 结束，旧的超时不能结束新请求的加载状态。
        await client.fail(0)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(value(controller, "isLoadingFirstPage", as: Bool.self) == true)
        await client.fail(1)
        try await until { self.value(controller, "isLoadingFirstPage", as: Bool.self) == false }
        controller.postTextureListViewDidRequestFirstPageRetry(PostTextureListView())
        try await until { await client.count == 3 }
        await client.reply(2)
        try await until { self.value(controller, "isLoadingFirstPage", as: Bool.self) == false }
        let items = try #require(value(controller, "items", as: [PostListItem].self))
        #expect(items.map { $0.post.id } == ["post-2"])
    }

    private func value<T>(_ object: Any, _ key: String, as: T.Type) -> T? { Mirror(reflecting: object).descendant(key) as? T }
    private func views(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(views) }
    private func until(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 { if await condition() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        Issue.record("等待请求或控制器状态超时")
        throw NSError(domain: "ListRequestIsolationTests", code: 1)
    }
}

private final class IsolationURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var pending: [IsolationURLProtocol] = []
    static var count: Int { lock.withLock { pending.count } }
    static var pages: [Int] { lock.withLock { pending.compactMap { instance in
        URLComponents(url: instance.request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value.flatMap(Int.init)
    } } }
    static func reset() { lock.withLock { pending = [] } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.lock.withLock { Self.pending.append(self) } }
    override func stopLoading() {}
    static func reply(_ index: Int, kind: String, ids: [Int], failure: Bool = false) throws {
        let instance = lock.withLock { pending[index] }
        if failure { instance.client?.urlProtocol(instance, didFailWithError: URLError(.timedOut)); return }
        let rows = ids.map { ["post_id": $0, "title": "post", "rank": 0, "floor_id": 1, "text": "reply"] as [String: Any] }
        let data = try JSONSerialization.data(withJSONObject: ["success": true, kind: rows])
        instance.client?.urlProtocol(instance, didReceive: HTTPURLResponse(url: instance.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        instance.client?.urlProtocol(instance, didLoad: data)
        instance.client?.urlProtocolDidFinishLoading(instance)
    }
}

private actor IsolationHTMLClient: HTMLClient {
    var pending: [(URL, CheckedContinuation<HTMLResponse, Error>)] = []
    var count: Int { pending.count }
    var pages: [Int] { pending.map { URLComponents(url: $0.0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value.flatMap(Int.init) ?? 1 } }
    func get(_ url: URL) async throws -> HTMLResponse { try await withCheckedThrowingContinuation { pending.append((url, $0)) } }
    func post(_ url: URL, formFields: [String: String]) async throws -> HTMLResponse { try await get(url) }
    func fail(_ index: Int) { pending[index].1.resume(throwing: URLError(.timedOut)) }
    func reply(_ index: Int, html: String? = nil) { let (url, continuation) = pending[index]; continuation.resume(returning: HTMLResponse(statusCode: 200, headers: [:], finalURL: url, html: html ?? "post-\(index)")) }
}

private struct IsolationParser: NodeSeekParser {
    func parsePostList(html: String) throws -> [PostSummary] {
        html.split(separator: ",").map { id in
            PostSummary(id: String(id), title: String(id), url: URL(string: "https://www.nodeseek.com/post-1-1")!, authorName: "test", nodeName: nil, replyCount: 0, lastActivityText: nil)
        }
    }
    func parsePostDetail(html: String, url: URL) throws -> PostDetail { throw URLError(.badServerResponse) }
    func parseCheckInState(html: String, pageURL: URL) throws -> CheckInState { CheckInState(isCheckedIn: false, message: "", actionURL: nil, hiddenFields: [:]) }
    func parseAccount(html: String) throws -> AccountResponse { AccountResponse(displayName: "test", isLoggedIn: false) }
}
