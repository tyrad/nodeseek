import UIKit
import XCTest
@testable import nodeseek

/// 使用相同的离线页面测量从创建控制器到第一张收藏卡片可见的时间。
@MainActor
final class CollectionMigrationBenchmarkTests: XCTestCase {
    func testRepeatedOpenAndScroll() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BenchmarkProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = NodeSeekUserContentClient(session: session)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let probe = FrameProbe()
        let link = CADisplayLink(target: probe, selector: #selector(FrameProbe.tick(_:)))
        link.add(to: .main, forMode: .common)
        defer { link.invalidate(); window.isHidden = true }
        var opens: [Double] = []
        var afterClose: [Int] = []
        for _ in 0..<12 {
            let start = CACurrentMediaTime()
            let controller = UserCollectionsViewController(uid: 1, client: client)
            window.rootViewController = controller
            window.isHidden = false
            let table = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UITableView }.first)
            while table.numberOfRows(inSection: 0) != 60 || table.visibleCells.isEmpty {
                guard CACurrentMediaTime() - start < 5 else { XCTFail("收藏首屏超时"); return }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            opens.append((CACurrentMediaTime() - start) * 1000)
            for row in stride(from: 3, to: 60, by: 3) {
                table.scrollToRow(at: IndexPath(row: row, section: 0), at: .middle, animated: false)
                try await Task.sleep(nanoseconds: 18_000_000)
            }
            window.rootViewController = nil
            try await Task.sleep(nanoseconds: 25_000_000)
            afterClose.append(FrameProbe.memory())
        }
        opens.sort()
        print("COLLECTION_BENCH opens_ms=\(opens) max_frame_ms=\(probe.maximum * 1000) peak_MiB=\(probe.peak) after_close_MiB=\(afterClose)")
    }
}

@MainActor
private final class FrameProbe: NSObject {
    var maximum = 0.0
    var peak = 0
    private var previous: Double?
    @objc func tick(_ link: CADisplayLink) {
        if let previous { maximum = max(maximum, link.timestamp - previous) }
        previous = link.timestamp
        peak = max(peak, Self.memory())
    }
    static func memory() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint / 1048576) : 0
    }
}

private final class BenchmarkProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let first = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "page", value: "1")) == true
        let rows = first ? (1...60).map { ["post_id": $0, "rank": 0, "title": String(repeating: "收藏列表滚动样例", count: 1 + $0 % 5)] as [String: Any] } : []
        let data = try! JSONSerialization.data(withJSONObject: ["success": true, "collections": rows])
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
