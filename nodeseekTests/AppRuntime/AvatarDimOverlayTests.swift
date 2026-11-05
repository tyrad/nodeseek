import Testing
import UIKit
@testable import nodeseek

@MainActor
struct AvatarDimOverlayTests {
    @Test func reuseAndResizeKeepOneNoninteractiveOverlayAndOriginalImage() throws {
        let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        let original = UIImage(systemName: "person")
        imageView.image = original
        AvatarDimOverlayView.install(on: imageView)
        AvatarDimOverlayView.install(on: imageView)
        let overlays = imageView.subviews.compactMap { $0 as? AvatarDimOverlayView }
        #expect(overlays.count == 1)
        let overlay = try #require(overlays.first)
        imageView.bounds.size = CGSize(width: 64, height: 64)
        imageView.layoutIfNeeded()
        #expect(overlay.frame == imageView.bounds)
        #expect(overlay.isUserInteractionEnabled == false)
        #expect(overlay.isAccessibilityElement == false)
        #expect(imageView.image === original)
    }

    @Test func overlayIsTransparentInLightAndSubtleInDark() throws {
        let imageView = UIImageView()
        AvatarDimOverlayView.install(on: imageView)
        let color = try #require(imageView.subviews.first?.backgroundColor)
        let light = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        #expect(light.cgColor.alpha == 0)
        #expect(abs(dark.cgColor.alpha - 0.12) < 0.001)
    }

    @Test func placeholderSwitchesToDarkGrayInDarkMode() throws {
        let image = AvatarPlaceholderImage.image
        let asset = try #require(image.imageAsset)
        let light = asset.image(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = asset.image(with: UITraitCollection(userInterfaceStyle: .dark))
        #expect(try brightness(of: light) > 0.85)
        #expect(try brightness(of: dark) < 0.2)
    }

    @Test func displayedPlaceholderUpdatesWithoutReloadingImage() async throws {
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        let imageView = UIImageView(frame: controller.view.bounds)
        imageView.image = AvatarPlaceholderImage.image
        controller.view.addSubview(imageView)

        for (style, expectedDark) in [(UIUserInterfaceStyle.light, false), (.dark, true), (.light, false)] {
            window.overrideUserInterfaceStyle = style
            window.layoutIfNeeded()
            await Task.yield()
            let snapshot = UIGraphicsImageRenderer(size: imageView.bounds.size).image { context in
                imageView.layer.render(in: context.cgContext)
            }
            let value = try brightness(of: snapshot)
            #expect(expectedDark ? value < 0.2 : value > 0.85)
        }
    }

    private func brightness(of image: UIImage) throws -> CGFloat {
        let cgImage = try #require(image.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return CGFloat(pixel[0]) / 255
    }
}
