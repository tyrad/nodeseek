import CryptoKit
import UIKit
import XCTest
@testable import nodeseek

@MainActor
final class NodeSeekVoteServiceTests: XCTestCase {
    private let payload = Data(#"{"success":true,"vote":{"id":3108,"title":"测试投票","multiple":false,"isPublic":true,"locked":false,"items":[{"vote_item_id":14131,"text":"plus","voted":false}]}}"#.utf8)

    func testReadSignsRequestAfterCookieSyncAndSkipsWebView() async throws {
        let cookies = VoteSpyCookieSession()
        var requests: [URLRequest] = []
        var webCalls = 0
        let service = NodeSeekVoteService(cookieSession: cookies, httpLoad: { request in
            XCTAssertEqual(cookies.preparations, 1)
            requests.append(request)
            return (self.payload, self.response(request))
        }, webRequest: { _, _ in
            webCalls += 1
            return self.payload
        })
        let vote = try await service.load(id: 3108)
        XCTAssertEqual(vote.id, 3108)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(webCalls, 0)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://www.nodeseek.com/api/vote/info/3108")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), WebRequestFingerprint.userAgent)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        let signedText = "GET\n\nhttps://www.nodeseek.com/api/vote/info/3108\n\n\(WebRequestFingerprint.userAgent)\n\n"
        let expected = Insecure.SHA1.hash(data: Data(signedText.utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-dynamic-sign"), expected)
    }

    func testChallengeFallsBackOnceToWebView() async throws {
        for status in [200, 403, 503] {
            var webCalls = 0
            let service = NodeSeekVoteService(cookieSession: VoteSpyCookieSession(), httpLoad: { request in
                (Data("<html>Just a moment...</html>".utf8), self.response(request, status: status, headers: ["cf-mitigated": "challenge"]))
            }, webRequest: { id, ids in
                XCTAssertEqual(id, 3108)
                XCTAssertNil(ids)
                webCalls += 1
                return self.payload
            })
            let vote = try await service.load(id: 3108)
            XCTAssertEqual(vote.id, 3108)
            XCTAssertEqual(webCalls, 1)
        }
    }

    func testConcurrentReadersShareOneHTTPRequestButRefreshReadsAgain() async throws {
        var httpCalls = 0
        let service = NodeSeekVoteService(cookieSession: VoteSpyCookieSession(), httpLoad: { request in
            httpCalls += 1
            try await Task.sleep(nanoseconds: 50_000_000)
            return (self.payload, self.response(request))
        })
        let first = Task { try await service.load(id: 3108) }
        let second = Task { try await service.load(id: 3108) }
        _ = try await first.value
        _ = try await second.value
        XCTAssertEqual(httpCalls, 1)
        _ = try await service.load(id: 3108)
        XCTAssertEqual(httpCalls, 2)
    }

    func testNetworkAndBusinessErrorsDoNotStartAnotherSlowRequest() async throws {
        for status in [401, 429, 500, -1] {
            var webCalls = 0
            let service = NodeSeekVoteService(cookieSession: VoteSpyCookieSession(), httpLoad: { request in
                if status == -1 { throw URLError(.timedOut) }
                return (Data(#"{"success":false,"message":"稍后重试"}"#.utf8), self.response(request, status: status))
            }, webRequest: { _, _ in
                webCalls += 1
                return self.payload
            })
            do {
                _ = try await service.load(id: 3108)
                XCTFail("失败响应不应成功")
            } catch {
                XCTAssertEqual(webCalls, 0)
            }
        }
    }

    func testAccountChangeDuringReadDiscardsOldResponse() async {
        var webCalls = 0
        let service = NodeSeekVoteService(cookieSession: VoteSpyCookieSession(), httpLoad: { request in
            NotificationCenter.default.post(name: .nodeSeekLoginSessionDidClose, object: nil)
            return (self.payload, self.response(request))
        }, webRequest: { _, _ in
            webCalls += 1
            return self.payload
        })
        do {
            _ = try await service.load(id: 3108)
            XCTFail("登录切换后不应显示旧账户结果")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(webCalls, 0)
    }

    func testSubmitKeepsWebFlowAndNeverRetriesTimedOutWrite() async {
        var httpCalls = 0
        var webCalls = 0
        let service = NodeSeekVoteService(cookieSession: VoteSpyCookieSession(), httpLoad: { request in
            httpCalls += 1
            return (self.payload, self.response(request))
        }, webRequest: { id, ids in
            XCTAssertEqual(id, 3108)
            XCTAssertEqual(ids, [14131])
            webCalls += 1
            throw URLError(.timedOut)
        })
        do {
            try await service.submit(id: 3108, ids: [14131])
            XCTFail("超时应返回错误供界面确认结果")
        } catch {}
        XCTAssertEqual(httpCalls, 0)
        XCTAssertEqual(webCalls, 1)
    }

    private func response(_ request: URLRequest, status: Int = 200, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }
}

@MainActor
private final class VoteSpyCookieSession: NodeSeekCookieSessionManaging {
    var preparations = 0
    func prepareHTTPLoad() async { preparations += 1 }
    func prepareWebViewLoad(userInterfaceStyle: UIUserInterfaceStyle?) async {}
    func captureWebViewSession() async {}
    func prepareMediaRequest() async {}
    func clearLoginSession() async {}
}
