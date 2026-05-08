//
//  PostTextureListViewTests.swift
//  nodeseekTests
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct PostTextureListViewTests {
    @Test func footerHeightStaysFixedAfterHidingLoadingMore() throws {
        let view = PostTextureListView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        view.layoutIfNeeded()

        view.showLoadingMore()
        view.hideLoadingMore()

        let tableView = try #require(view.firstSubview(of: UITableView.self))
        let footer = try #require(tableView.tableFooterView)
        #expect(footer.frame.height == 56)
    }
}

private extension UIView {
    func firstSubview<T: UIView>(of type: T.Type) -> T? {
        if let matched = self as? T {
            return matched
        }
        for subview in subviews {
            if let matched = subview.firstSubview(of: type) {
                return matched
            }
        }
        return nil
    }
}

