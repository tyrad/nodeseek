import UIKit
import XCTest
@testable import nodeseek

@MainActor
final class DetailImageDimmingTests: XCTestCase {
    func testPreferenceAndThemeChangesUpdateExistingImageWithoutReplacingPixels() async throws {
        let suiteName = "image-dimming-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = DetailImageDimmingSettings(userDefaults: defaults)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.overrideUserInterfaceStyle = .dark
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        let imageView = UIImageView(image: image)
        imageView.frame = CGRect(x: 0, y: 100, width: 200, height: 200)
        controller.view.addSubview(imageView)
        let overlay = DetailImageDimmingView.install(on: imageView, settings: settings)
        XCTAssertEqual(opacity(of: overlay, traits: window.traitCollection), 0)

        settings.setEnabled(true)
        XCTAssertEqual(opacity(of: overlay, traits: imageView.traitCollection), 0.35, accuracy: 0.001)
        XCTAssertTrue(imageView.image === image, "遮罩不能修改供缓存或导出使用的原图")
        window.overrideUserInterfaceStyle = .light
        controller.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(opacity(of: overlay, traits: window.traitCollection), 0)
        window.overrideUserInterfaceStyle = .dark
        controller.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(opacity(of: overlay, traits: imageView.traitCollection), 0.35, accuracy: 0.001)

        settings.setEnabled(false)
        XCTAssertEqual(opacity(of: overlay, traits: window.traitCollection), 0)
    }

    func testInstallationIsIdempotentAndTracksBoundsWithoutBlockingGestures() throws {
        let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 160, height: 80))
        let badge = UILabel()
        imageView.addSubview(badge)
        let overlay = DetailImageDimmingView.install(on: imageView)
        XCTAssertTrue(DetailImageDimmingView.install(on: imageView) === overlay)
        XCTAssertEqual(imageView.subviews.filter { $0 is DetailImageDimmingView }.count, 1)
        XCTAssertTrue(imageView.subviews.last === badge)
        XCTAssertFalse(overlay.isUserInteractionEnabled)
        XCTAssertTrue(overlay.accessibilityElementsHidden)
        imageView.bounds.size = CGSize(width: 320, height: 500)
        imageView.layoutIfNeeded()
        XCTAssertEqual(overlay.frame, imageView.bounds)
    }

    func testEnabledPreferenceAppliesBeforeFirstImageAndSurvivesFrameReplacement() throws {
        let suiteName = "image-dimming-first-frame-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = DetailImageDimmingSettings(userDefaults: defaults)
        settings.setEnabled(true)
        // 未挂到窗口的视图不保证合并 override 主题，直接用深色 trait 解析动态颜色。
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)
        let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let overlay = DetailImageDimmingView.install(on: imageView, settings: settings)
        XCTAssertEqual(opacity(of: overlay, traits: darkTraits), 0.35, accuracy: 0.001)
        for _ in 0..<3 {
            imageView.image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { _ in }
            XCTAssertEqual(opacity(of: overlay, traits: darkTraits), 0.35, accuracy: 0.001)
        }
        imageView.image = nil
        XCTAssertTrue(DetailImageDimmingView.install(on: imageView, settings: settings) === overlay)
    }

    func testSettingsAndImageAppearanceInBothThemes() async throws {
        let suiteName = "image-dimming-appearance-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = DetailImageDimmingSettings(userDefaults: defaults)
        settings.setEnabled(true)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let controller = SettingsViewController(imageDimmingSettings: settings)
        window.rootViewController = UINavigationController(rootViewController: controller)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        for style in [UIUserInterfaceStyle.light, .dark] {
            window.overrideUserInterfaceStyle = style
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 350_000_000)
            attach(window, name: "image-dimming-settings-\(style.rawValue)")
        }

        let preview = UIViewController()
        window.rootViewController = preview
        preview.view.backgroundColor = .systemBackground
        let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 180)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
            ("白底图片 · 35%\n文字清晰度与色彩对比" as NSString).draw(
                in: CGRect(x: 24, y: 24, width: 280, height: 80),
                withAttributes: [.foregroundColor: UIColor.black, .font: UIFont.systemFont(ofSize: 22)]
            )
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 24, y: 120, width: 272, height: 28))
        }
        let original = UIImageView(image: image)
        let adjusted = UIImageView(image: image)
        for (index, view) in [original, adjusted].enumerated() {
            view.frame = CGRect(x: 24, y: 160 + index * 220, width: 320, height: 180)
            preview.view.addSubview(view)
        }
        DetailImageDimmingView.install(on: adjusted, settings: settings)
        for style in [UIUserInterfaceStyle.light, .dark] {
            window.overrideUserInterfaceStyle = style
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 350_000_000)
            attach(window, name: "image-dimming-comparison-\(style.rawValue)")
        }
    }

    private func opacity(of view: UIView, traits: UITraitCollection) -> CGFloat {
        view.backgroundColor?.resolvedColor(with: traits).cgColor.alpha ?? -1
    }

    private func attach(_ view: UIView, name: String) {
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
