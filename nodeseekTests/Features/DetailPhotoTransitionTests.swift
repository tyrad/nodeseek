import JXPhotoBrowser
import UIKit
import XCTest
@testable import nodeseek

@MainActor
final class DetailPhotoTransitionTests: XCTestCase {
    func testPhotoTransitionIsShorterThanLibraryDefault() {
        let browser = DetailPhotoBrowserController()
        browser.transitionType = .zoom
        let present = browser.animationController(forPresented: browser, presenting: browser, source: browser)
        let dismiss = browser.animationController(forDismissed: browser)
        XCTAssertEqual(present?.transitionDuration(using: nil), DetailPhotoTransitionTiming.duration)
        XCTAssertEqual(dismiss?.transitionDuration(using: nil), DetailPhotoTransitionTiming.duration)
        XCTAssertLessThan(DetailPhotoTransitionTiming.duration, 0.25)

        browser.transitionType = .fade
        let fade = browser.animationController(forPresented: browser, presenting: browser, source: browser)
        XCTAssertEqual(fade?.transitionDuration(using: nil), DetailPhotoTransitionTiming.duration)
    }

    func testAnchorIsConsumedOnce() {
        let url = URL(string: "https://www.nodeseek.com/a.png")!
        let view = UIImageView()
        DetailPhotoTransitionAnchor.record(imageView: view, url: url)
        let taken = DetailPhotoTransitionAnchor.take()
        XCTAssertTrue(taken?.imageView === view)
        XCTAssertEqual(taken?.url, url)
        XCTAssertNil(DetailPhotoTransitionAnchor.take())
    }

    func testFinderPrefersTappedViewWhenURLRepeats() {
        let url = URL(string: "https://www.nodeseek.com/a.png")!
        let (window, root) = makeWindow()
        defer { window.isHidden = true }
        let first = fixture(url: url, frame: CGRect(x: 10, y: 10, width: 40, height: 40))
        let tapped = fixture(url: url, frame: CGRect(x: 10, y: 80, width: 40, height: 40))
        root.addSubview(first)
        root.addSubview(tapped)

        let found = DetailPhotoThumbnailFinder.thumbnail(
            matching: url, in: root, anchorView: tapped, anchorURL: url
        )
        XCTAssertTrue(found === tapped)
    }

    func testFinderSkipsAnchorAfterItShowsAnotherImage() {
        let url = URL(string: "https://www.nodeseek.com/a.png")!
        let (window, root) = makeWindow()
        defer { window.isHidden = true }
        let reused = fixture(url: url, frame: CGRect(x: 10, y: 10, width: 40, height: 40))
        let current = fixture(url: url, frame: CGRect(x: 10, y: 80, width: 40, height: 40))
        root.addSubview(reused)
        root.addSubview(current)
        reused.detailPhotoThumbnailURL = URL(string: "https://www.nodeseek.com/other.png")

        let found = DetailPhotoThumbnailFinder.thumbnail(
            matching: url, in: root, anchorView: reused, anchorURL: url
        )
        XCTAssertTrue(found === current)
    }

    func testFinderPrefersImageInTheSameCell() {
        let urlA = URL(string: "https://www.nodeseek.com/a.png")!
        let urlB = URL(string: "https://www.nodeseek.com/b.png")!
        let (window, root) = makeWindow()
        defer { window.isHidden = true }
        let elsewhere = fixture(url: urlB, frame: CGRect(x: 10, y: 10, width: 40, height: 40))
        root.addSubview(elsewhere)

        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.frame = CGRect(x: 0, y: 80, width: 320, height: 160)
        root.addSubview(cell)
        let tapped = fixture(url: urlA, frame: CGRect(x: 8, y: 8, width: 48, height: 48))
        let sibling = fixture(url: urlB, frame: CGRect(x: 8, y: 64, width: 48, height: 48))
        cell.contentView.addSubview(tapped)
        cell.contentView.addSubview(sibling)

        let found = DetailPhotoThumbnailFinder.thumbnail(
            matching: urlB, in: root, anchorView: tapped, anchorURL: urlA
        )
        XCTAssertTrue(found === sibling)
    }

    func testFinderIgnoresImageOutsideTheWindowAndStillFindsHiddenOne() {
        let outsideURL = URL(string: "https://www.nodeseek.com/outside.png")!
        let hiddenURL = URL(string: "https://www.nodeseek.com/hidden.png")!
        let (window, root) = makeWindow()
        defer { window.isHidden = true }
        let outside = fixture(url: outsideURL, frame: CGRect(x: 0, y: 700, width: 40, height: 40))
        let hidden = fixture(url: hiddenURL, frame: CGRect(x: 12, y: 12, width: 40, height: 40))
        hidden.isHidden = true
        root.addSubview(outside)
        root.addSubview(hidden)

        XCTAssertNil(DetailPhotoThumbnailFinder.thumbnail(
            matching: outsideURL, in: root, anchorView: nil, anchorURL: nil
        ))
        XCTAssertTrue(DetailPhotoThumbnailFinder.thumbnail(
            matching: hiddenURL, in: root, anchorView: nil, anchorURL: nil
        ) === hidden)
    }

    func testFinderCanonicalizesImageURLs() {
        let (window, root) = makeWindow()
        defer { window.isHidden = true }
        let http = fixture(
            url: URL(string: "http://www.nodeseek.com/a.png")!,
            frame: CGRect(x: 10, y: 10, width: 40, height: 40)
        )
        let relative = fixture(
            url: URL(string: "/static/b.png")!,
            frame: CGRect(x: 10, y: 70, width: 40, height: 40)
        )
        root.addSubview(http)
        root.addSubview(relative)

        XCTAssertTrue(DetailPhotoThumbnailFinder.thumbnail(
            matching: URL(string: "https://www.nodeseek.com/a.png")!,
            in: root, anchorView: nil, anchorURL: nil
        ) === http)
        XCTAssertTrue(DetailPhotoThumbnailFinder.thumbnail(
            matching: URL(string: "https://www.nodeseek.com/static/b.png")!,
            in: root, anchorView: nil, anchorURL: nil
        ) === relative)
    }

    func testInlineImageAndImageBlockExposeThumbnailSource() throws {
        let url = URL(string: "https://www.nodeseek.com/inline.png")!
        let inline = DetailInlineImageView(
            frame: CGRect(x: 0, y: 0, width: 40, height: 40),
            imageURL: url,
            targetPixelWidth: 40,
            displayScale: 2,
            allowsInlineAnimation: false,
            usesDetailImageOptimization: true,
            onImageLoaded: { _, _ in },
            onImageTapped: { _ in }
        )
        XCTAssertEqual(inline.detailPhotoThumbnailURL, url)
        XCTAssertTrue(inline.detailPhotoThumbnailView === inline)

        let blockURL = URL(string: "https://www.nodeseek.com/block.png")!
        let block = DetailImageBlockView(
            imageBlock: RenderedImageBlock(url: blockURL, altText: nil),
            imageKind: .normal,
            onImageLoaded: { _, _ in },
            onImageTapped: {}
        )
        XCTAssertEqual(block.detailPhotoThumbnailURL, blockURL)
        XCTAssertFalse(block.detailPhotoThumbnailView === block)
    }

    func testPresenterHidesCurrentThumbnailAndRestoresPrevious() {
        let firstURL = URL(string: "https://www.nodeseek.com/a.png")!
        let secondURL = URL(string: "https://www.nodeseek.com/b.png")!
        let (window, root) = makeWindow()
        defer { window.isHidden = true }
        let first = fixture(url: firstURL, frame: CGRect(x: 10, y: 10, width: 40, height: 40))
        let second = fixture(url: secondURL, frame: CGRect(x: 10, y: 70, width: 40, height: 40))
        root.addSubview(first)
        root.addSubview(second)
        let presenter = DetailPhotoBrowserPresenter(imageURLs: [firstURL, secondURL], sourceRoot: root)
        let browser = JXPhotoBrowserViewController()

        presenter.photoBrowser(browser, setThumbnailHidden: true, at: 0)
        XCTAssertTrue(first.isHidden)
        presenter.photoBrowser(browser, setThumbnailHidden: true, at: 1)
        XCTAssertFalse(first.isHidden)
        XCTAssertTrue(second.isHidden)
    }

    func testDismissUsesFadeAndRestoresThumbnailWhenMotionIsReduced() {
        let url = URL(string: "https://www.nodeseek.com/a.png")!
        let (window, root) = makeWindow()
        defer { window.isHidden = true }
        let photo = fixture(url: url, frame: CGRect(x: 10, y: 10, width: 40, height: 40))
        root.addSubview(photo)
        let presenter = DetailPhotoBrowserPresenter(imageURLs: [url], sourceRoot: root)
        let browser = JXPhotoBrowserViewController()
        presenter.photoBrowser(browser, setThumbnailHidden: true, at: 0)

        presenter.applyDismissTransition(on: browser, reduceMotion: true)

        XCTAssertFalse(photo.isHidden)
        guard case .fade = browser.transitionType else {
            return XCTFail("减少动态效果时应淡出")
        }
    }

    func testDismissKeepsZoomWhileSourceStaysOnScreen() {
        let url = URL(string: "https://www.nodeseek.com/a.png")!
        let (window, root) = makeWindow()
        defer { window.isHidden = true }
        let photo = fixture(url: url, frame: CGRect(x: 10, y: 10, width: 40, height: 40))
        root.addSubview(photo)
        let presenter = DetailPhotoBrowserPresenter(imageURLs: [url], sourceRoot: root)
        let browser = JXPhotoBrowserViewController()
        presenter.photoBrowser(browser, setThumbnailHidden: true, at: 0)

        presenter.applyDismissTransition(on: browser, reduceMotion: false)

        XCTAssertTrue(photo.isHidden)
        guard case .zoom = browser.transitionType else {
            return XCTFail("源图仍在屏幕上时应缩放回去")
        }
    }

    private func makeWindow() -> (UIWindow, UIView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let root = UIView(frame: window.bounds)
        window.addSubview(root)
        window.isHidden = false
        return (window, root)
    }

    private func fixture(url: URL, frame: CGRect) -> FixturePhotoView {
        let view = FixturePhotoView(url: url, frame: frame)
        view.image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        return view
    }
}

private final class FixturePhotoView: UIImageView, DetailPhotoThumbnailSource {
    var detailPhotoThumbnailURL: URL?
    var detailPhotoThumbnailView: UIImageView { self }

    init(url: URL, frame: CGRect) {
        detailPhotoThumbnailURL = url
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
