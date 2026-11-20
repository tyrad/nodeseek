import AsyncDisplayKit
import Kingfisher
import UIKit
import XCTest
@testable import nodeseek

private struct ReplayPage: Decodable {
    struct Item: Decodable {
        let id: String
        let floor: Int
        let main: Bool
        let hot: Bool
        let html: String
        let markdown: String?
    }

    let path: String
    let title: String?
    let items: [Item]
    let previous: Int?
    let next: Int?

    var page: Int { Int(path.split(separator: "-").last ?? "1") ?? 1 }

    func detail(using media: [String: String]) -> PostDetail {
        func body(_ item: Item) -> String {
            media.reduce(item.html) { html, entry in
                html.replacingOccurrences(of: "src=\"\(entry.key)\"", with: "src=\"\(entry.value)\"")
            }
        }
        let comments = items.filter { !$0.main }.map { item in
            Comment(id: item.id, anchorID: String(item.floor), authorName: "NodeSeek", avatarURL: nil,
                    floorText: "#\(item.floor)", createdAtText: nil, contentHTML: body(item),
                    isHot: item.hot, markdown: item.markdown)
        }
        return PostDetail(id: String(path.split(separator: "-")[1]), title: title ?? path,
                          authorName: "NodeSeek", avatarURL: nil, metadataText: nil,
                          contentHTML: items.first(where: \.main).map(body) ?? "", comments: comments,
                          page: page, pagination: .init(currentPage: page, items: [], previousPage: previous, nextPage: next))
    }
}

// 占位截图冻结离线媒体请求。投票服务仍走正常的读取和解码流程。
private final class ReplayURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "detail-baseline.invalid" ||
            (request.httpMethod == "GET" && request.url?.host == NodeSeekSite.baseURL.host &&
             request.url?.path == "/api/vote/info/3108")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, url.host != "detail-baseline.invalid" else { return }
        do {
            let data = try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: "detail-replay-vote", withExtension: "json")))
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

@MainActor
private final class RefreshClock: NSObject {
    private var link: CADisplayLink?
    private var continuation: CheckedContinuation<Double, Never>?
    private(set) var times: [Double] = []

    private func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    private(set) var peakBytes: UInt64 = 0
    func resetPeak() { peakBytes = footprint() }

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }
    func stop() { link?.invalidate() }
    func next() async -> Double {
        await withCheckedContinuation { continuation = $0 }
    }
    @objc private func tick() {
        let now = CACurrentMediaTime()
        times.append(now)
        peakBytes = max(peakBytes, footprint())
        continuation?.resume(returning: now)
        continuation = nil
    }
}

@MainActor
final class DetailBaselineTests: XCTestCase {
    private func fixture<T: Decodable>(_ name: String, as: T.Type) throws -> T {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    private func mediaMap(directory: URL, placeholders: Bool) throws -> [String: String] {
        let files = try fixture("detail-replay-media", as: [String: String].self)
        var urls = [String: String]()
        for (original, file) in files {
            let kind = original.contains("/sticker/") ? "sticker" : "image"
            let path = "\(kind)/\(file)"
            if placeholders {
                urls[original] = "https://detail-baseline.invalid/" + path
                continue
            }
            let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: file, withExtension: nil))
            let local = directory.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: local)
            urls[original] = local.absoluteString
        }
        return urls
    }

    private func window(style: UIUserInterfaceStyle) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = style
        window.windowLevel = .normal + 1
        return window
    }

    private func host(page: ReplayPage, anchor: Int?, in window: UIWindow) -> PostDetailViewController {
        let vc = PostDetailViewController(presenter: SpyPostDetailPresenter(), currentPage: page.page,
                                          initialAnchorID: anchor.map(String.init))
        window.rootViewController = UINavigationController(rootViewController: vc)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return vc
    }

    private func descendants(_ root: UIView) -> [UIView] {
        [root] + root.subviews.flatMap(descendants)
    }

    private func bodyViews(_ cell: ASCellNode) -> [UIView] {
        descendants(cell.view).filter { view in
            if let rich = view as? DetailRichTextView { return (rich.debugAttributedString?.length ?? 0) > 0 }
            return view is DetailImageBlockView || view is DetailVoteView || view is DetailCodeBlockView ||
                view is DetailTerminalView || view.accessibilityIdentifier == "detail-magic-tab-content" ||
                String(describing: type(of: view)) == "DetailTableScrollView"
        }
    }

    private func cell(for item: ReplayPage.Item, in vc: PostDetailViewController) -> (IndexPath, ASCellNode)? {
        guard (item.main ? vc.headerRenderedContent != nil : vc.renderedCommentIDs.contains(item.id)),
              let index = vc.indexPathForCurrentPageAnchor(String(item.floor)),
              let node = vc.tableNode.nodeForRow(at: index), node.bounds.height > 0 else { return nil }
        return (index, node)
    }

    private func wait(_ label: String, timeout: Double = 12, until ready: () -> Bool) async throws {
        let deadline = CACurrentMediaTime() + timeout
        while !ready() {
            guard CACurrentMediaTime() < deadline else { throw NSError(domain: "DetailBaseline", code: 1, userInfo: [NSLocalizedDescriptionKey: "等待超时 " + label]) }
            try await Task.sleep(nanoseconds: 16_000_000)
        }
    }

    private func save(_ data: Data, name: String, type: String) throws {
        #if targetEnvironment(simulator)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/detail-baseline/results")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: root.appendingPathComponent(name), options: .atomic)
        #else
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: type)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        #endif
    }

    func testFloorSnapshots() async throws {
        let pages = try fixture("post-markdown-pages", as: [ReplayPage].self)
        let votePage = try XCTUnwrap(try fixture("detail-replay-pages", as: [ReplayPage].self).last)
        let oldSize = AppTextSizeSettings.shared.pointOffset
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        // 这张报告以裸链接发表，旧渲染器会将它提升为图片块。保留链接和真实识别路径。
        let reportURL = try XCTUnwrap(URL(string: "https://report.check.place/ip/2BZVMSUHF.svg"))
        let originals = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Images/originals")
        let cache = ImageDiskCache(directory: originals)
        let previousData = cache.data(for: reportURL)
        let svg = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "baseline-check-place-svg", withExtension: "txt"))
        try cache.store(Data(contentsOf: svg), for: reportURL)
        defer {
            if let previousData { try? cache.store(previousData, for: reportURL) }
            else { try? FileManager.default.removeItem(at: cache.cacheURL(for: reportURL)) }
        }
        let loaded = try mediaMap(directory: directory, placeholders: false)
        let waiting = try mediaMap(directory: directory, placeholders: true)
        URLProtocol.registerClass(ReplayURLProtocol.self)
        let oldConfig = ImageDownloader.default.sessionConfiguration
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReplayURLProtocol.self]
        ImageDownloader.default.sessionConfiguration = config
        defer {
            AppTextSizeSettings.shared.setPointOffset(oldSize)
            ImageDownloader.default.sessionConfiguration = oldConfig
            URLProtocol.unregisterClass(ReplayURLProtocol.self)
            try? FileManager.default.removeItem(at: directory)
        }

        var heights = [String: CGFloat]()
        for style in [UIUserInterfaceStyle.light, .dark] {
            let window = try window(style: style)
            defer { window.isHidden = true; window.rootViewController = nil }
            for size in [0, 8] {
                AppTextSizeSettings.shared.setPointOffset(CGFloat(size))
                for placeholder in [true, false] {
                    for page in pages + [votePage] {
                        let targets = page.items.filter { item in
                            (!placeholder || loaded.keys.contains(where: item.html.contains)) &&
                                (page.path != votePage.path || item.main)
                        }
                        guard !targets.isEmpty else { continue }
                        let vc = host(page: page, anchor: nil, in: window)
                        vc.render(detail: page.detail(using: placeholder ? waiting : loaded))
                        for item in targets {
                            let name = "\(page.path.dropFirst())-\(item.floor)-\(style == .dark ? "dark" : "light")-\(size)-\(placeholder ? "placeholder" : "body")"
                            try await wait(name) { self.cell(for: item, in: vc) != nil }
                            let (index, _) = try XCTUnwrap(cell(for: item, in: vc))
                            vc.tableNode.scrollToRow(at: index, at: .top, animated: false)
                            try await wait(name + "-visible") {
                                guard let (_, cell) = self.cell(for: item, in: vc), cell.view.window === window else { return false }
                                return !self.bodyViews(cell).isEmpty
                            }
                            if page.path == votePage.path {
                                try await wait(name + "-vote", timeout: 60) {
                                    guard let (_, cell) = self.cell(for: item, in: vc) else { return false }
                                    return self.descendants(cell.view).compactMap { $0 as? DetailVoteView }.first?.model.vote?.id == 3108
                                }
                            }
                            if !placeholder && page.path == "/post-1067722-1" && item.main {
                                try await wait(name + "-terminal", timeout: 45) {
                                    guard let (_, cell) = self.cell(for: item, in: vc) else { return false }
                                    return self.descendants(cell.view).contains { ($0 as? DetailTerminalView)?.snapshot != nil }
                                }
                            }
                            let promotedReport = item.html.contains(reportURL.absoluteString)
                            if !placeholder, promotedReport || loaded.keys.contains(where: item.html.contains) {
                                try await wait(name + "-media") {
                                    guard let (_, cell) = self.cell(for: item, in: vc) else { return false }
                                    let placeholders = self.descendants(cell.view).compactMap { $0 as? DetailImagePlaceholderView }
                                    if promotedReport && placeholders.isEmpty { return false }
                                    return placeholders.allSatisfy(\.isHidden)
                                }
                            }
                            // 同一楼可能因附件回调被替换，等节流后的行高连续稳定再截图。
                            var lastHeight: CGFloat?
                            var lastChange = CACurrentMediaTime()
                            try await wait(name + "-height") {
                                guard let (_, current) = self.cell(for: item, in: vc) else { return false }
                                if lastHeight != current.bounds.height {
                                    lastHeight = current.bounds.height
                                    lastChange = CACurrentMediaTime()
                                }
                                return CACurrentMediaTime() - lastChange >= 0.20
                            }
                            let (_, cell) = try XCTUnwrap(self.cell(for: item, in: vc))
                            let format = UIGraphicsImageRendererFormat()
                            format.scale = 1
                            let image = UIGraphicsImageRenderer(bounds: cell.view.bounds, format: format).image { _ in
                                XCTAssertTrue(cell.view.drawHierarchy(in: cell.view.bounds, afterScreenUpdates: true), name)
                            }
                            try save(XCTUnwrap(image.pngData()), name: name + ".png", type: "public.png")
                            heights[name] = cell.bounds.height
                        }
                    }
                }
            }
        }
        try save(JSONEncoder().encode(heights), name: "floor-heights.json", type: "public.json")
    }
}

extension DetailBaselineTests {
    private struct Run: Encodable {
        let iteration: Int
        let scenario: String
        let layoutMS: Double
        let visibleMS: Double
        let complexVisibleMS: Double?
        let longestFrameMS: Double
        let peakSampledBytes: UInt64
        let width: CGFloat
    }

    private func isVisible(_ view: UIView, within viewport: UIView) -> Bool {
        guard let window = viewport.window, view.window === window, !view.isHidden, view.alpha > 0,
              !view.bounds.isEmpty else { return false }
        let viewportRect = viewport.convert(viewport.bounds, to: window).intersection(window.bounds)
        return viewportRect.intersects(view.convert(view.bounds, to: window))
    }

    private func observe(vc: PostDetailViewController, item: ReplayPage.Item, clock: RefreshClock,
                         start: Double, iteration: Int, scenario: String, expectsTabs: Bool) async throws -> Run {
        var layout: Double?
        var visible: Double?
        var tabs: Double?
        var firstVisibleRefresh: Double?
        let firstFrame = clock.times.lastIndex(where: { $0 <= start }) ?? 0
        while CACurrentMediaTime() - start < 45 {
            let now = await clock.next()
            guard let (_, cell) = cell(for: item, in: vc) else { continue }
            if layout == nil { layout = now }
            let surfaces = bodyViews(cell).filter { view in
                if view.accessibilityIdentifier == "detail-magic-tab-content" { return false }
                if let terminal = view as? DetailTerminalView, terminal.snapshot == nil { return false }
                return isVisible(view, within: vc.tableNode.view)
            }
            if surfaces.isEmpty {
                firstVisibleRefresh = nil
            } else if firstVisibleRefresh == nil {
                firstVisibleRefresh = now
            } else if visible == nil {
                visible = now
            }
            if expectsTabs && tabs == nil {
                if let tab = descendants(cell.view).first(where: { $0.accessibilityIdentifier == "detail-magic-tab-content" }) {
                    let image = descendants(tab).compactMap { $0 as? DetailTerminalView }.first?.detailPhotoThumbnailView
                    if let image, image.image != nil, isVisible(image, within: vc.tableNode.view) { tabs = now }
                    else if !isVisible(tab, within: vc.tableNode.view) {
                        // 长帖的标签页在首屏以下，两个入口都用相同的定位动作。
                        vc.tableNode.view.scrollRectToVisible(tab.convert(tab.bounds, to: vc.tableNode.view), animated: false)
                    }
                }
            }
            guard let layout, let visible, !expectsTabs || tabs != nil else { continue }
            let samples = clock.times.dropFirst(firstFrame)
            let intervals = zip(samples, samples.dropFirst()).map { ($1 - $0) * 1000 }
            return Run(iteration: iteration, scenario: scenario, layoutMS: (layout-start)*1000,
                       visibleMS: (visible-start)*1000, complexVisibleMS: tabs.map { ($0-start)*1000 },
                       longestFrameMS: intervals.max() ?? 0, peakSampledBytes: clock.peakBytes, width: vc.tableNode.view.bounds.width)
        }
        throw NSError(domain: "目标未显示 \(scenario) #\(item.floor) layout=\(String(describing: layout)) visible=\(String(describing: visible))", code: 1)
    }

    func testPageTiming() async throws {
        let pages = try fixture("detail-replay-pages", as: [ReplayPage].self)
        let second = try XCTUnwrap(pages.first { $0.path == "/post-832584-2" })
        let third = try XCTUnwrap(pages.first { $0.path == "/post-832584-3" })
        let review = try XCTUnwrap(pages.first { $0.path == "/post-1067722-1" })
        let target = try XCTUnwrap(second.items.first { $0.floor == 13 })
        let main = try XCTUnwrap(review.items.first(where: \.main))
        let oldSize = AppTextSizeSettings.shared.pointOffset
        AppTextSizeSettings.shared.setPointOffset(0)
        defer { AppTextSizeSettings.shared.setPointOffset(oldSize) }
        let window = try window(style: .light)
        defer { window.isHidden = true; window.rootViewController = nil }
        let clock = RefreshClock()
        clock.start()
        defer { clock.stop() }
        // 由现有渲染器取得这个样本实际使用的目录，保留原文件，测完恢复。
        let seed = host(page: review, anchor: nil, in: window)
        let blocks = DTCoreTextHTMLContentRenderer().render(fragment: main.html, baseURL: NodeSeekSite.baseURL)
        let sections = blocks.compactMap { block -> RenderedMagicTabsBlock? in
            if case .tabs(let tabs) = block { return tabs }
            return nil
        }
        let ansi = try XCTUnwrap(sections.first?.sections.first?.blocks.compactMap { block -> RenderedTerminalBlock? in
            if case .terminal(let terminal) = block { return terminal }
            return nil
        }.first)
        let snapshot = try await TerminalSnapshotRenderer.shared.render(ansi, in: seed.view)
        let cachedReport = try XCTUnwrap(snapshot.pages.first?.url.deletingLastPathComponent())
        let savedReport = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: cachedReport, to: savedReport)
        defer {
            if FileManager.default.fileExists(atPath: cachedReport.path) { try? FileManager.default.removeItem(at: cachedReport) }
            try? FileManager.default.moveItem(at: savedReport, to: cachedReport)
        }
        var runs = [Run]()
        for iteration in 1...20 {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let media = try mediaMap(directory: directory, placeholders: false)
            defer { try? FileManager.default.removeItem(at: directory) }
            if FileManager.default.fileExists(atPath: cachedReport.path) {
                try FileManager.default.removeItem(at: cachedReport)
            }
            for scenario in ["page2-anchor", "review", "review-cache-hit"] {
                let isReview = scenario != "page2-anchor"
                let page = isReview ? review : second
                let item = isReview ? main : target
                let vc = host(page: page, anchor: isReview ? nil : target.floor, in: window)
                let detail = page.detail(using: media)
                _ = await clock.next()
                clock.resetPeak()
                let start = CACurrentMediaTime()
                vc.render(detail: detail)
                runs.append(try await observe(vc: vc, item: item, clock: clock, start: start, iteration: iteration,
                                              scenario: scenario, expectsTabs: isReview))
                if !isReview {
                    vc.appendCommentPage(detail: third.detail(using: media))
                    let table = vc.tableNode.view
                    try await wait("第 3 页完成布局") {
                        guard let lastItem = third.items.last, let last = self.cell(for: lastItem, in: vc) else { return false }
                        return last.0.row < table.numberOfRows(inSection: 0)
                    }
                    let base = vc.tableNode.contentOffset.y
                    let end = max(base, table.contentSize.height - table.bounds.height + table.adjustedContentInset.bottom)
                    XCTAssertGreaterThan(end, base)
                    _ = await clock.next()
                    clock.resetPeak()
                    let scrollStart = CACurrentMediaTime()
                    for frame in 1...24 {
                        let fraction = CGFloat(frame <= 12 ? frame : 24-frame) / 12
                        vc.tableNode.setContentOffset(CGPoint(x: 0, y: base + fraction * (end-base)), animated: false)
                        _ = await clock.next()
                    }
                    runs.append(try await observe(vc: vc, item: target, clock: clock, start: scrollStart, iteration: iteration,
                                                  scenario: "warm-return", expectsTabs: false))
                }
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try save(encoder.encode(runs), name: "page-timing.json", type: "public.json")
    }
}
