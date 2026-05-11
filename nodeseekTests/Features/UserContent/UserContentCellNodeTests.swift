//
//  UserContentCellNodeTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/5/11.
//

import Testing
import UIKit
@testable import nodeseek

struct UserContentCellNodeTests {
    @Test func titleTypographyUsesSameBaselineAsPostList() throws {
        let text = UserContentText.title("标题")
        let font = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)

        #expect(font.pointSize == PostListCellStyle.Typography.titleFont.pointSize)
        #expect(font.pointSize == AppTextSizeSettings.adjustedPointSize(basePointSize: 17))
    }
}
