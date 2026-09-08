#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import WebKit

// 独立验证 WKWebView 的离线渲染和异步截图，不修改 App 的加载链路。
@MainActor
final class SnapshotProbe: NSObject, WKNavigationDelegate {
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1100, height: 900))
    #if canImport(UIKit)
    let window = UIWindow(frame: UIScreen.main.bounds)
    #else
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 900),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    #endif
    let outputURL: URL
    let appearance: String
    let started = Date()
    var finished = false

    init(inputURL: URL, outputURL: URL, appearance: String = "light") {
        self.outputURL = outputURL
        self.appearance = appearance
        super.init()
        webView.navigationDelegate = self
        #if canImport(UIKit)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentInset = .zero
        webView.scrollView.isScrollEnabled = false
        let controller = UIViewController()
        controller.overrideUserInterfaceStyle = appearance == "dark" ? .dark : .light
        window.rootViewController = controller
        controller.view.addSubview(webView)
        window.makeKeyAndVisible()
        #else
        window.contentView = webView
        // 保持实际渲染宿主，既不激活窗口，也不使用隐藏/零尺寸 WebView。
        window.orderBack(nil)
        #endif
        webView.loadFileURL(inputURL, allowingReadAccessTo: inputURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.fail("等待渲染或截图超时（30 秒）")
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        poll()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(error.localizedDescription)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        fail("WebKit 内容进程退出")
    }

    func poll() {
        guard !finished else { return }
        webView.evaluateJavaScript("window.snapshotResult || null") { [weak self] value, error in
            guard let self, !self.finished else { return }
            if let error { self.fail(error.localizedDescription); return }
            guard let result = value as? [String: Any] else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.poll() }
                return
            }
            if let error = result["error"] as? String { self.fail(error); return }
            guard let width = result["width"] as? Double, let height = result["height"] as? Double,
                  width > 0, height > 0, width * height * 4 <= 24_000_000 else {
                self.fail("无效截图尺寸"); return
            }
            self.capture(result: result, size: CGSize(width: width, height: height))
        }
    }

    func capture(result: [String: Any], size: CGSize) {
        #if !canImport(UIKit)
        window.setContentSize(size)
        #endif
        webView.frame = CGRect(origin: .zero, size: size)
        // 尺寸调整后等待 WebKit 下一帧，再由公开的 snapshot API 捕获整个 bounds。
        webView.callAsyncJavaScript(
            "await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))); return true;",
            arguments: [:], in: nil, in: .page
        ) { [weak self] update in
            guard let self, !self.finished else { return }
            if case .failure(let error) = update { self.fail(error.localizedDescription); return }
            let config = WKSnapshotConfiguration()
            config.rect = CGRect(origin: .zero, size: size)
            #if canImport(UIKit)
            let displayScale = self.window.screen.scale
            #else
            let displayScale = self.window.backingScaleFactor
            #endif
            config.snapshotWidth = NSNumber(value: size.width * 2 / displayScale)
            config.afterScreenUpdates = true
            self.webView.takeSnapshot(with: config) { [weak self] image, error in
                guard let self, !self.finished else { return }
                #if canImport(UIKit)
                guard let image, let bitmap = image.cgImage, let png = image.pngData() else {
                    self.fail(error?.localizedDescription ?? "截图为空"); return
                }
                let pixelWidth = bitmap.width, pixelHeight = bitmap.height
                #else
                guard let image, let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    self.fail(error?.localizedDescription ?? "截图为空"); return
                }
                let pixelWidth = bitmap.pixelsWide, pixelHeight = bitmap.pixelsHigh
                #endif
                do {
                    try png.write(to: self.outputURL)
                    var metadata = result
                    metadata["appearance"] = self.appearance
                    metadata["pixelWidth"] = pixelWidth
                    metadata["pixelHeight"] = pixelHeight
                    metadata["pngBytes"] = png.count
                    metadata["totalMilliseconds"] = Int(Date().timeIntervalSince(self.started) * 1000)
                    let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                    try data.write(to: self.outputURL.deletingPathExtension().appendingPathExtension("json"))
                    print("Saved \(self.outputURL.path): \(pixelWidth)×\(pixelHeight)")
                    self.finished = true
                    #if !canImport(UIKit)
                    self.window.orderOut(nil)
                    NSApplication.shared.terminate(nil)
                    #endif
                } catch { self.fail(error.localizedDescription) }
            }
        }
    }

    func fail(_ message: String) {
        guard !finished else { return }
        finished = true
        try? Data(message.utf8).write(to: outputURL.deletingPathExtension().appendingPathExtension("error.txt"))
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}

#if canImport(UIKit)
@MainActor
final class ProbeAppDelegate: UIResponder, UIApplicationDelegate {
    var probe: SnapshotProbe?
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
        let name = arguments.first ?? "basic"
        guard let input = Bundle.main.url(forResource: name, withExtension: "html") else { return false }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(arguments.count > 1 ? arguments[1] : UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        probe = SnapshotProbe(inputURL: input, outputURL: documents.appendingPathComponent(name + ".png"),
                              appearance: arguments.count > 2 ? arguments[2] : "light")
        window = probe?.window
        return true
    }
}

@main
struct Main {
    @MainActor static func main() {
        UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(ProbeAppDelegate.self))
    }
}
#else
@main
struct Main {
    @MainActor static func main() {
        guard CommandLine.arguments.count == 3 else {
            print("Usage: snapshot input.html output.png")
            exit(2)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let probe = SnapshotProbe(
            inputURL: URL(fileURLWithPath: CommandLine.arguments[1]),
            outputURL: URL(fileURLWithPath: CommandLine.arguments[2])
        )
        withExtendedLifetime(probe) { app.run() }
    }
}
#endif
