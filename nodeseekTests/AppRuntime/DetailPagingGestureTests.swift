import UIKit
import XCTest
@testable import nodeseek

/// 只替换 HTML 传输。实际解析、请求状态、TextKit 列表和触摸手势贯穿同一次运行。
private actor PagingHTMLClient: HTMLClient {
    private(set) var pages: [Int] = []
    var releaseSecondPage = false
    func releaseResponse() { releaseSecondPage = true }

    func get(_ url: URL) async throws -> HTMLResponse {
        let page = Int(url.lastPathComponent.split(separator: "-").last ?? "") ?? 0
        pages.append(page)
        guard page == 1 || page == 2 else { throw URLError(.badURL) }
        if page == 2, pages.filter({ $0 == 2 }).count <= 2 {
            let deadline = ProcessInfo.processInfo.systemUptime + 30
            while !releaseSecondPage {
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw URLError(.timedOut) }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            releaseSecondPage = false
            if pages.filter({ $0 == 2 }).count == 1 { throw URLError(.timedOut) }
        }
        let floors = page == 1 ? 1...25 : 26...28
        let rows = floors.map { n in
            """
            <li class="content-item" id="\(n)" data-comment-id="\(n)">
            <a class="author-name">读者</a><a class="floor-link">#\(n)</a>
            <article class="post-content"><p>第 \(n) 楼的正文</p></article></li>
            """
        }.joined()
        let sources = floors.filter { $0.isMultiple(of: 2) }.map { n in
            #"{"commentId":\#(n),"blocked":false,"markdown":"第 \#(n) 楼的正文"}"#
        }.joined(separator: ",")
        let html = """
        <script id="nodeseek-captured-config" type="application/json">{"postData":{"comments":[\(sources)]}}</script>
        <title>分页拖动测试</title><div class="nsk-post"><div class="content-item">
        <article class="post-content">主楼</article></div></div>
        <div class="post-top-pager"><a class="pager-pos" href="/post-999-1">1</a>
        <a class="pager-pos" href="/post-999-2">2</a></div><ul class="comments">\(rows)</ul>
        """
        return HTMLResponse(statusCode: 200, headers: [:], finalURL: url, html: html)
    }

    func post(_ url: URL, formFields: [String: String]) async throws -> HTMLResponse { throw URLError(.unsupportedURL) }
}

@MainActor
final class DetailPagingGestureTests: XCTestCase {
    func testSlowNextPageAndRetryDuringBottomBounce() async throws {
        guard let path = ProcessInfo.processInfo.environment["NODESEEK_PAGING_RUN"] else {
            throw XCTSkip("需通过 make e2e-case CASE=textkit-paging-timing 启动模拟器手势驱动")
        }
        let dir = URL(fileURLWithPath: path)
        let transport = PagingHTMLClient()
        let post = PostSummary(id: "999", title: "分页拖动测试", url: NodeSeekSite.postURL(id: "999", page: 1),
                               authorName: "作者", nodeName: nil, replyCount: 28, lastActivityText: nil)
        let service = NodeSeekService(htmlClient: transport, currentAccountStore: nil)
        let interactor = PostDetailInteractor(post: post, service: service)
        let presenter = PostDetailPresenter(interactor: interactor, router: PostDetailRouter())
        let page = PostDetailViewController(presenter: presenter, usesTextKitList: true)
        interactor.presenter = presenter
        presenter.setView(page)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .normal + 1
        window.rootViewController = UINavigationController(rootViewController: page)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let list = try XCTUnwrap(page.collectionList?.view)
        var trace = "time,condition,offset,end,rows,dragging,decelerating\n"
        defer { try? trace.write(to: dir.appendingPathComponent("scroll.csv"), atomically: true, encoding: .utf8) }
        func until(_ message: String, _ condition: () async -> Bool) async throws {
            let deadline = CACurrentMediaTime() + 12
            while !(await condition()) {
                let rows = list.numberOfSections == 0 ? 0 : list.numberOfItems(inSection: 0)
                trace += "\(CACurrentMediaTime()),\(message),\(list.contentOffset.y),\(bottom()),\(rows),\(list.isDragging),\(list.isDecelerating)\n"
                if CACurrentMediaTime() > deadline { throw NSError(domain: "DetailPagingGesture", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
                try await Task.sleep(nanoseconds: 8_000_000)
            }
        }
        func bottom() -> CGFloat { list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom }
        func settleAtEnd() async throws {
            // 将测试起点固定到当前页底；后续越界、松手、重试均由外部触摸完成。
            for _ in 0..<4 {
                window.layoutIfNeeded()
                list.contentOffset.y = bottom()
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        func drag(_ phase: String) throws {
            let rect = list.convert(list.bounds, to: window)
            let command: [String: Any] = ["phase": phase, "x": Int(rect.midX), "from": Int(rect.minY + rect.height * 0.75),
                                          "to": Int(rect.minY + rect.height * 0.35)]
            try JSONSerialization.data(withJSONObject: command).write(to: dir.appendingPathComponent("drag.json"), options: .atomic)
        }
        var evidence = [String: Double]()
        try await until("未加载第一页 25 楼") { page.comments.count == 25 }
        XCTAssertEqual(page.comments.filter(\.hasVisibleMarkdown).count, 12)
        try await settleAtEnd()
        try await until("到页底未请求第二页") { await transport.pages == [1, 2] }
        let oldCount = list.numberOfItems(inSection: 0)
        let initialBottom = bottom()
        try drag("timeout")
        try await until("首次手势没有拉过旧页底") { list.isDragging && list.contentOffset.y > initialBottom + 20 }
        await transport.releaseResponse()
        try await until("超时后仍在加载") { !page.loadMoreCommentsIndicator.isAnimating }
        try await until("第一次回弹没有结束") { !list.isDragging && !list.isDecelerating }
        let failedRequests = await transport.pages
        XCTAssertEqual(failedRequests, [1, 2])
        XCTAssertEqual(list.numberOfItems(inSection: 0), oldCount)

        // 回填视口上方的楼层会同时调整总高度和 offset。核对同一楼层实际停靠位置。
        let lastOldRow = IndexPath(item: oldCount - 1, section: 0)
        func restingAnchorY() throws -> CGFloat {
            let frame = try XCTUnwrap(list.layoutAttributesForItem(at: lastOldRow)).frame
            return list.convert(frame, to: window).minY + list.contentOffset.y - bottom()
        }
        let anchorBeforeRetry = try restingAnchorY()
        try drag("retry")
        try await until("新手势没有重试或没有越界") {
            let pages = await transport.pages
            return pages == [1, 2, 2] && list.isDragging && list.contentOffset.y - bottom() > 20
        }
        let anchorDuringRetry = try restingAnchorY()
        evidence["retryAnchorMovementPt"] = anchorDuringRetry - anchorBeforeRetry
        XCTAssertEqual(anchorDuringRetry, anchorBeforeRetry, accuracy: 1)
        let boundaryAtRetry = bottom()
        evidence["boundaryDeltaBeforeResponsePt"] = boundaryAtRetry - initialBottom
        await transport.releaseResponse()
        try await until("正常响应没有到达详情页") { page.comments.count == 28 }
        window.layoutIfNeeded()
        evidence["overshootAtResponsePt"] = list.contentOffset.y - boundaryAtRetry
        XCTAssertGreaterThan(evidence["overshootAtResponsePt"] ?? 0, 1)
        XCTAssertEqual(list.numberOfItems(inSection: 0), oldCount)
        XCTAssertEqual(bottom(), boundaryAtRetry, accuracy: 1)
        try await until("回弹后没有接上第二页三楼") { list.numberOfItems(inSection: 0) == oldCount + 3 && !list.isDecelerating && !list.isDragging }
        evidence["appendOffsetDeltaPt"] = list.contentOffset.y - boundaryAtRetry
        XCTAssertEqual(list.contentOffset.y, boundaryAtRetry, accuracy: 1)

        try await settleAtEnd()
        let finalBottom = bottom()
        try drag("last")
        try await until("末页未发生系统回弹") { list.isDragging && list.contentOffset.y > finalBottom + 20 }
        try await until("末页未停稳") { !list.isDragging && !list.isDecelerating }
        evidence["lastOffsetDeltaPt"] = list.contentOffset.y - finalBottom
        XCTAssertEqual(list.contentOffset.y, finalBottom, accuracy: 1)
        XCTAssertEqual(list.numberOfItems(inSection: 0), oldCount + 3)
        let requests = await transport.pages
        XCTAssertEqual(requests, [1, 2, 2])
        let button = page.loadMoreCommentsRefreshButton
        let target = button.convert(button.bounds, to: window)
        XCTAssertFalse(button.isHidden)
        let tap: [String: Any] = ["phase": "refresh", "x": Int(target.midX), "y": Int(target.midY)]
        try JSONSerialization.data(withJSONObject: tap).write(to: dir.appendingPathComponent("drag.json"), options: .atomic)
        try await until("手动刷新没有返回原页无新评论") { page.toastLabel.text == "暂无新评论" }
        window.layoutIfNeeded()
        let refreshedRequests = await transport.pages
        XCTAssertEqual(refreshedRequests, [1, 2, 2, 2])
        XCTAssertEqual(list.numberOfItems(inSection: 0), oldCount + 3)
        evidence["refreshOffsetDeltaPt"] = list.contentOffset.y - finalBottom
        XCTAssertEqual(list.contentOffset.y, finalBottom, accuracy: 1)
        let result: [String: Any] = ["requests": refreshedRequests, "measurements": evidence]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            .write(to: dir.appendingPathComponent("measurements.json"), options: .atomic)
    }
}
