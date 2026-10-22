#if canImport(UIKit)
import UIKit
import XCTest
@testable import FramePlay

@MainActor
final class UIKitTests: XCTestCase {
    func testWindowVisibilityReuseAndManualPause() async throws {
        let env = environment(FakeDecoder())
        let imageView = AnimatedImageView(environment: env)
        imageView.load(AnimatedImageSource(data: Data([1])))
        try await eventually { imageView.state == .ready }
        let window = makeTestWindow()
        defer { window.isHidden = true; window.rootViewController = nil }
        window.rootViewController?.view.addSubview(imageView)
        imageView.frame = CGRect(x: 20, y: 100, width: 160, height: 160)
        window.makeKeyAndVisible()
        try await eventually { imageView.state == .playing }
        imageView.setPlaybackVisible(false)
        XCTAssertEqual(imageView.state, .paused)
        imageView.setPlaybackVisible(true)
        XCTAssertEqual(imageView.state, .playing)
        imageView.pause()
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(imageView.state, .paused, "用户主动暂停不能被前台通知覆盖")
        imageView.prepareForReuse()
        XCTAssertEqual(imageView.state, .idle)
        XCTAssertNil(imageView.displayedImage)
        XCTAssertEqual(env.statistics.resourceCount, 0)
    }

    func testBackgroundPurgesFramesAndForegroundResumesOnlyVisibleView() async throws {
        let env = environment(FakeDecoder())
        let imageView = AnimatedImageView(environment: env)
        let window = makeTestWindow()
        defer { imageView.prepareForReuse(); window.isHidden = true; window.rootViewController = nil }
        window.rootViewController?.view.addSubview(imageView)
        window.makeKeyAndVisible()
        imageView.load(AnimatedImageSource(data: Data([1])))
        try await eventually { imageView.state == .playing && env.statistics.pendingOperations == 0 }
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertEqual(imageView.state, .paused)
        XCTAssertEqual(env.statistics.bufferedBytes, 0)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(imageView.state, .playing)
        imageView.removeFromSuperview()
        XCTAssertEqual(imageView.state, .paused)
    }

    func testUIKitFallbackPreservesCallerImageOrientation() async throws {
        let view = AnimatedImageView(environment: PlaybackEnvironment())
        let fallback = UIImage(cgImage: TestFixtures.frame(), scale: 2, orientation: .right)
        view.load(AnimatedImageSource(data: Data([1])), fallbackImage: fallback)
        try await eventually { view.state == .staticFallback(.invalidImageData) }
        XCTAssertTrue(view.displayedImage === fallback)
        view.prepareForReuse()
        XCTAssertNil(view.displayedImage)
    }
}

@MainActor
func makeTestWindow() -> UIWindow {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = UIViewController()
    window.windowLevel = .normal + 1
    window.rootViewController?.view.backgroundColor = .systemBackground
    return window
}
#endif
