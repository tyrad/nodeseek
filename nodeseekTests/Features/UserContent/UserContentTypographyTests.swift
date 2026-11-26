//
//  UserContentTypographyTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/5/11.
//

import Testing
import UIKit
@testable import nodeseek

struct UserContentTypographyTests {
    @MainActor @Test func titleTypographyUsesSameBaselineAsPostList() throws {
        let cell = UserCollectionCell(style: .default, reuseIdentifier: nil)
        cell.configure(UserCollectionRecord(title: "标题", postID: 1, rank: 0))
        func title(in view: UIView) -> UILabel? {
            if let label = view as? UILabel, label.text == "标题" { return label }
            return view.subviews.compactMap { title(in: $0) }.first
        }
        let font = try #require(title(in: cell)?.font)
        #expect(font.pointSize == PostListCellStyle.Typography.titleFont.pointSize)
        #expect(font.pointSize == AppTextSizeSettings.adjustedPointSize(basePointSize: 17))
    }
}
