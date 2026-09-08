import CryptoKit
import UIKit
import WebKit

@MainActor
final class TerminalSnapshotRenderer {
    static let shared = TerminalSnapshotRenderer()

    private final class Job {
        var consumers = Set<UUID>()
        var task: Task<TerminalSnapshot, Error>!
    }
    private var jobs: [String: Job] = [:]
    private var tail: Task<Void, Never>?
    private let cache: TerminalSnapshotCache

    init(cache: TerminalSnapshotCache = .shared) { self.cache = cache }

    func render(_ terminal: RenderedTerminalBlock, in host: UIView) async throws -> TerminalSnapshot {
        guard terminal.ansi.utf8.count <= 512_000 else { throw SnapshotError.tooLarge }
        let key = SHA256.hash(data: Data(("xterm-5.5-cols100-font14-line1.25-palette1-scale2-tiles640-merged16mp-v2\n" + terminal.ansi).utf8))
            .map { String(format: "%02x", $0) }.joined()
        let token = UUID()
        let job: Job
        if let existing = jobs[key] {
            job = existing
        } else {
            job = Job()
            let previous = tail
            job.task = Task { [cache, weak host] in
                if let cached = await cache.load(key: key) { return cached }
                await previous?.value
                try Task.checkCancellation()
                guard let host, host.window != nil else { throw CancellationError() }
                let session = TerminalSnapshotSession(cache: cache)
                return try await session.render(terminal.ansi, key: key, host: host)
            }
            jobs[key] = job
            tail = Task { _ = try? await job.task.value }
        }
        job.consumers.insert(token)
        defer { release(token, key: key, job: job) }
        return try await withTaskCancellationHandler {
            let result = try await job.task.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            Task { @MainActor in self.release(token, key: key, job: job) }
        }
    }

    private func release(_ token: UUID, key: String, job: Job) {
        job.consumers.remove(token)
        if job.consumers.isEmpty {
            job.task.cancel()
            if jobs[key] === job { jobs.removeValue(forKey: key) }
        }
    }

    enum SnapshotError: LocalizedError {
        case tooLarge, unavailable, timedOut, invalidOutput
        var errorDescription: String? {
            switch self {
            case .tooLarge: return "报告过长，请前往网页查看"
            case .unavailable: return "渲染资源不可用"
            case .timedOut: return "图片生成超时，请重试"
            case .invalidOutput: return "报告渲染失败，请重试"
            }
        }
    }
}

@MainActor
private final class TerminalSnapshotSession {
    private let cache: TerminalSnapshotCache
    private var webView: WKWebView?
    private var finishPending: ((Error) -> Void)?

    init(cache: TerminalSnapshotCache) { self.cache = cache }

    func render(_ ansi: String, key: String, host: UIView) async throws -> TerminalSnapshot {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1200), configuration: configuration)
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.contentInset = .zero
        web.scrollView.isScrollEnabled = false
        web.isUserInteractionEnabled = false
        web.accessibilityElementsHidden = true
        guard let window = host.window else { throw CancellationError() }
        // 位于正文后方但保持真实尺寸，避免隐藏 WebView 停止绘制。
        window.insertSubview(web, at: 0)
        webView = web
        defer { web.stopLoading(); web.removeFromSuperview(); webView = nil }
        return try await withTaskCancellationHandler {
            web.loadHTMLString(try Self.document(), baseURL: nil)
            let deadline = Date().addingTimeInterval(20)
            while true {
                try Task.checkCancellation()
                if Date() > deadline { throw TerminalSnapshotRenderer.SnapshotError.timedOut }
                if (try? await web.evaluateJavaScript("typeof window.renderTerminalReport === 'function'")) as? Bool == true { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            let result: [String: Any] = try await boundedOperation { complete in
                web.callAsyncJavaScript("return await window.renderTerminalReport(ansi);", arguments: ["ansi": ansi], in: nil, in: .page) {
                    complete($0.flatMap { value in
                        guard let dictionary = value as? [String: Any] else { return .failure(TerminalSnapshotRenderer.SnapshotError.invalidOutput) }
                        return .success(dictionary)
                    })
                }
            }
            guard let width = result["width"] as? Double, let height = result["height"] as? Double,
                  let text = result["text"] as? String, width > 0, width <= 1200, height > 0, height <= 24000 else {
                throw TerminalSnapshotRenderer.SnapshotError.invalidOutput
            }
            web.frame.size = CGSize(width: width, height: height)
            let _: Bool = try await boundedOperation { complete in
                web.callAsyncJavaScript("await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))); return true;", arguments: [:], in: nil, in: .page) { result in
                    complete(result.map { _ in true })
                }
            }
            var pages: [TerminalSnapshot.Page] = []
            var y: Double = 0
            while y < height {
                try Task.checkCancellation()
                let config = WKSnapshotConfiguration()
                config.rect = CGRect(x: 0, y: y, width: width, height: min(640, height - y))
                config.snapshotWidth = NSNumber(value: width * 2 / max(window.screen.scale, 1))
                config.afterScreenUpdates = true
                let image: UIImage = try await boundedOperation { complete in
                    web.takeSnapshot(with: config) { image, error in
                        if let image { complete(.success(image)) }
                        else { complete(.failure(error ?? TerminalSnapshotRenderer.SnapshotError.invalidOutput)) }
                    }
                }
                pages.append(try await cache.save(image: image, key: key, index: pages.count))
                y += 640
            }
            let snapshot = TerminalSnapshot(pages: pages, text: text)
            return try await cache.finish(snapshot, key: key)
        } onCancel: {
            Task { @MainActor in
                self.finishPending?(CancellationError())
                self.webView?.stopLoading()
            }
        }
    }

    private func boundedOperation<T>(_ start: (@escaping (Result<T, Error>) -> Void) -> Void) async throws -> T {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            var completed = false
            let timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { return }
                self?.finishPending?(TerminalSnapshotRenderer.SnapshotError.timedOut)
            }
            let finish: (Result<T, Error>) -> Void = { [weak self] result in
                guard !completed else { return }
                completed = true
                timeout.cancel()
                self?.finishPending = nil
                continuation.resume(with: result)
            }
            finishPending = { finish(.failure($0)) }
            start(finish)
        }
    }

    private static func document() throws -> String {
        func resource(_ name: String, _ ext: String) throws -> String {
            guard let url = Bundle.main.url(forResource: name, withExtension: ext)
                ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Terminal") else {
                throw TerminalSnapshotRenderer.SnapshotError.unavailable
            }
            return try String(contentsOf: url, encoding: .utf8)
        }
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'">
        <style>\(try resource("nodeseek-xterm", "css"))
        html,body{margin:0;padding:0;background:#282c34}#report{display:inline-block;padding:16px;background:#282c34}
        .xterm-viewport{overflow:hidden!important}.xterm-cursor{visibility:hidden}
        </style></head><body><div id="report"><div id="terminal"></div></div>
        <script>\(try resource("nodeseek-xterm", "js"))</script>
        <script>\(try resource("nodeseek-terminal-render", "js"))</script></body></html>
        """
    }
}
