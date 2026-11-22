import AsyncDisplayKit
import UIKit
import XCTest
@testable import nodeseek

@MainActor
final class DetailUnavailablePostTests: XCTestCase {
    func testNotFoundInBothLists() async throws {
        try await compare(notice: "404 Not Found😭", level: nil, style: .light)
    }

    func testPermissionLevelInBothLists() async throws {
        try await compare(notice: "查看本帖需要Lv2，您的权限不足😑", level: 2, style: .dark)
    }

    private func compare(notice: String, level: Int?, style: UIUserInterfaceStyle) async throws {
        let url = try XCTUnwrap(URL(string: "https://www.nodeseek.com/post-42-1"))
        let detail = try KannaNodeSeekParser(baseURL: url).parsePostDetail(
            html: "<title>NodeSeek</title><div id='nsk-body'><div id='nsk-body-left'><p>\(notice)</p></div></div>",
            url: url
        )
        let expectedTitle = level.map { "受限帖子 🔒 \($0)" } ?? NSLocalizedString("帖子不存在", tableName: "DetailPrototype", comment: "")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = style
        defer { window.isHidden = true; window.rootViewController = nil }
        var referenceHeight: CGFloat?
        var referenceTitle: NSAttributedString?
        let path = IndexPath(row: 0, section: 0)
        for native in [false, true] {
            let vc = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: native)
            window.rootViewController = UINavigationController(rootViewController: vc)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            vc.render(detail: detail)
            func loadedCell() -> UIView? {
                if let list = vc.collectionList {
                    let cell = list.view.cellForItem(at: path) as? DetailFloorListCell
                    guard let cell, cell.isSettled, abs(cell.bounds.height - cell.measuredHeight(width: cell.bounds.width)) < 1 else { return nil }
                    return cell
                }
                guard vc.headerRenderedContent != nil else { return nil }
                return (vc.tableNode.nodeForRow(at: path) as? PostBodyCellNode)?.view
            }
            for _ in 0..<200 {
                window.layoutIfNeeded()
                if let cell = loadedCell(), cell.bounds.height > 0, richText(in: cell) != nil { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            let cell = try XCTUnwrap(loadedCell())
            let rich = try XCTUnwrap(richText(in: cell))
            let body = try XCTUnwrap(rich.debugAttributedString)
            XCTAssertEqual(body.string.trimmingCharacters(in: .whitespacesAndNewlines), notice)
            let bodyColor = body.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
            XCTAssertEqual(bodyColor?.resolvedColor(with: rich.traitCollection), ReadingColors.text.resolvedColor(with: rich.traitCollection))
            XCTAssertTrue(vc.replyButton.isHidden)
            XCTAssertTrue(vc.loadMoreCommentsRefreshButton.isHidden)
            XCTAssertEqual(vc.detailRows.count, 1)
            var screenshot: UIImage?
            cell.traitCollection.performAsCurrent {
                screenshot = UIGraphicsImageRenderer(bounds: cell.bounds).image { _ in
                    cell.drawHierarchy(in: cell.bounds, afterScreenUpdates: true)
                }
            }
            let image = try XCTUnwrap(screenshot)
            if style == .dark {
                // 检查正文开头的汉字，排除末尾的彩色表情。
                let textRect = rich.convert(rich.bounds, to: cell)
                let sample = CGRect(origin: textRect.origin, size: CGSize(width: min(64, textRect.width), height: textRect.height))
                XCTAssertGreaterThan(try brightestPixel(in: sample, image: image), 140)
            }
            let shot = XCTAttachment(image: image)
            shot.name = "\(native ? "TextKit" : "Texture")-\(level == nil ? "404" : "Lv2")"
            shot.lifetime = .keepAlways
            add(shot)
            if let floor = cell as? DetailFloorListCell {
                XCTAssertEqual(floor.heading.text, expectedTitle)
                XCTAssertEqual(floor.copyText, notice)
                let previous = try XCTUnwrap(referenceTitle)
                let actual = try XCTUnwrap(floor.heading.attributedText)
                for index in [0, actual.length - 1] where index < previous.length {
                    let lhs = actual.attributes(at: index, effectiveRange: nil)
                    let rhs = previous.attributes(at: index, effectiveRange: nil)
                    let newFont = try XCTUnwrap(lhs[.font] as? UIFont)
                    let oldFont = try XCTUnwrap(rhs[.font] as? UIFont)
                    XCTAssertEqual(newFont.fontName, oldFont.fontName)
                    XCTAssertEqual(newFont.pointSize, oldFont.pointSize)
                    XCTAssertEqual((lhs[.foregroundColor] as? UIColor)?.resolvedColor(with: floor.traitCollection),
                                   (rhs[.foregroundColor] as? UIColor)?.resolvedColor(with: floor.traitCollection))
                }
                XCTAssertEqual(cell.bounds.height, try XCTUnwrap(referenceHeight), accuracy: 2)
                XCTAssertFalse(floor.contentView.subviews.contains { $0.backgroundColor == .separator && !$0.isHidden })
            } else {
                let node = try XCTUnwrap(vc.tableNode.nodeForRow(at: path) as? PostBodyCellNode)
                referenceTitle = try XCTUnwrap(node.debugTitleAttributedText)
                XCTAssertEqual(referenceTitle?.string, expectedTitle)
                referenceHeight = cell.bounds.height
            }
        }
    }

    private func brightestPixel(in rect: CGRect, image: UIImage) throws -> UInt8 {
        let pixels = rect.applying(CGAffineTransform(scaleX: image.scale, y: image.scale)).integral
        let crop = try XCTUnwrap(image.cgImage?.cropping(to: pixels))
        let context = try XCTUnwrap(CGContext(data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8,
                                              bytesPerRow: crop.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0))
        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return UnsafeBufferPointer(start: data, count: crop.height * crop.width).max() ?? 0
    }

    private func richText(in view: UIView) -> DetailRichTextView? {
        if let rich = view as? DetailRichTextView { return rich }
        return view.subviews.lazy.compactMap { self.richText(in: $0) }.first
    }
}
