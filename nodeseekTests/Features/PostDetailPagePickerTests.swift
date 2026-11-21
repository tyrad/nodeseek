import UIKit
import XCTest
@testable import nodeseek

@MainActor
final class PostDetailPagePickerTests: XCTestCase {
    func testCurrentPageIsLegibleWithoutABrightTileInDarkMode() async throws {
        try await checkCurrentPage(style: .dark)
    }

    func testCurrentPageIsLegibleInLightMode() async throws {
        try await checkCurrentPage(style: .light)
    }

    private func checkCurrentPage(style: UIUserInterfaceStyle) async throws {
        let picker = PostDetailPagePickerViewController(
            totalPages: 89, currentPage: 88, loadedPages: [88, 89], exitsAuthorFilter: false
        ) { _ in }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let presenter = UIViewController()
        window.overrideUserInterfaceStyle = style
        window.rootViewController = presenter
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }
        window.layoutIfNeeded()
        picker.overrideUserInterfaceStyle = style
        await withCheckedContinuation { continuation in
            presenter.present(picker, animated: false) { continuation.resume() }
        }
        window.layoutIfNeeded()
        picker.view.layoutIfNeeded()
        let grid = try XCTUnwrap(picker.view.subviews.compactMap { $0 as? UICollectionView }.first)
        grid.scrollToItem(at: IndexPath(item: 87, section: 0), at: .bottom, animated: false)
        grid.layoutIfNeeded()
        let cell = try XCTUnwrap(grid.cellForItem(at: IndexPath(item: 87, section: 0)))
        let adjacent = try XCTUnwrap(grid.cellForItem(at: IndexPath(item: 88, section: 0)))
        let label = try XCTUnwrap(cell.contentView.subviews.compactMap { $0 as? UILabel }.first)
        XCTAssertEqual(label.text, "88")
        XCTAssertTrue(cell.accessibilityTraits.contains(.selected))

        let snapshot = XCTAttachment(image: UIGraphicsImageRenderer(bounds: cell.bounds).image { context in
            cell.layer.render(in: context.cgContext)
        })
        snapshot.name = "PagePicker-\(style == .dark ? "dark" : "light")"
        snapshot.lifetime = .keepAlways
        add(snapshot)

        let traits = cell.traitCollection
        XCTAssertEqual(traits.userInterfaceStyle, style)
        let fill = try XCTUnwrap(cell.contentView.backgroundColor).resolvedColor(with: traits)
        let adjacentFill = try XCTUnwrap(adjacent.contentView.backgroundColor).resolvedColor(with: traits)
        XCTAssertNotEqual(fill, adjacentFill)
        let dot = try XCTUnwrap(cell.contentView.subviews.first { type(of: $0) == UIView.self })
        XCTAssertFalse(dot.isHidden)
        let dotColor = try XCTUnwrap(dot.backgroundColor).resolvedColor(with: traits)
        let background = luminance(fill)
        XCTAssertGreaterThanOrEqual(contrast(luminance(dotColor), background), 3)
        let foreground = luminance(label.textColor.resolvedColor(with: traits))
        XCTAssertGreaterThanOrEqual(contrast(foreground, background), 4.5)
        if style == .dark {
            XCTAssertLessThan(background, foreground, "深色下，当前页应为深底亮字")
        }
    }

    private func contrast(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private func luminance(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: nil))
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
