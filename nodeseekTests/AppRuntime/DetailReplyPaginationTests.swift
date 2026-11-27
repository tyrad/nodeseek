import XCTest
@testable import nodeseek

@MainActor
final class DetailReplyPaginationTests: XCTestCase {
    func testInlinePageSelectionInDetail() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let presenter = SpyPostDetailPresenter()
        let page = PostDetailViewController(presenter: presenter)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UINavigationController(rootViewController: page)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }

        func detail(_ number: Int) -> PostDetail {
            let replies = (1...12).map { index in
                Comment(id: "\(number)-\(index)", authorName: "Alice", avatarURL: nil,
                        floorText: "#\(index)", createdAtText: nil, contentHTML: "回复")
            }
            return PostDetail(id: "42", title: "分页", authorName: "Bob", avatarURL: nil,
                              metadataText: nil, contentHTML: "主楼", comments: replies, page: number,
                              pagination: .init(currentPage: number, items: [.init(page: 81, url: nil, isCurrent: number == 81)],
                                                previousPage: number > 1 ? number - 1 : nil, nextPage: number < 81 ? number + 1 : nil))
        }
        func buttons() throws -> [UIButton] {
            let list = page.collectionList.view
            let index = try XCTUnwrap(page.collectionList.rows.firstIndex { if case .replyPagination = $0 { return true }; return false })
            let path = IndexPath(item: index, section: 0)
            window.layoutIfNeeded()
            list.scrollToItem(at: path, at: .top, animated: false)
            list.layoutIfNeeded()
            let cell = try XCTUnwrap(list.cellForItem(at: path) as? DetailReplyPaginationCell)
            cell.layoutIfNeeded()
            let stack = try XCTUnwrap(cell.contentView.subviews.compactMap { $0 as? UIStackView }.first)
            let buttons = stack.arrangedSubviews.compactMap { $0 as? UIButton }
            for button in buttons {
                let frame = button.convert(button.bounds, to: page.view)
                XCTAssertGreaterThanOrEqual(frame.minX, page.view.safeAreaInsets.left)
                XCTAssertLessThanOrEqual(frame.maxX, page.view.bounds.width - page.view.safeAreaInsets.right)
                XCTAssertGreaterThanOrEqual(frame.height, 44)
            }
            return buttons
        }

        page.render(detail: detail(1))
        try await Task.sleep(nanoseconds: 250_000_000)
        let first = try buttons()
        XCTAssertEqual(first.first?.isEnabled, false)
        let next = try XCTUnwrap(first.last)
        next.sendActions(for: .touchUpInside)
        XCTAssertEqual(presenter.selectedCommentPages, [2])
        // 跳页用底部提示代替居中转圈，加载结束后收起
        page.showLoading()
        XCTAssertTrue(page.isPageJumpToastVisible)
        XCTAssertFalse(page.loadingIndicator.isAnimating)
        page.hideLoading()
        XCTAssertFalse(page.isPageJumpToastVisible)
        page.render(detail: detail(2))
        page.appendCommentPage(detail: detail(3))
        let second = try buttons()
        let selected = try XCTUnwrap(second.first { $0.accessibilityTraits.contains(.selected) })
        XCTAssertEqual(selected.currentTitle, "2")
        second.first?.sendActions(for: .touchUpInside)
        XCTAssertEqual(presenter.selectedCommentPages, [2, 1])
        page.render(detail: detail(81))
        XCTAssertEqual(try buttons().last?.isEnabled, false)

        // 设置里关闭后不再显示分页条
        let settings = ReplyPaginationDisplaySettings.shared
        settings.setShowsInlineBar(false)
        defer { settings.setShowsInlineBar(true) }
        XCTAssertFalse(page.collectionList.rows.contains { if case .replyPagination = $0 { return true }; return false })
    }
}
