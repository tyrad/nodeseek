//
//  HTMLContentRendererTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import Testing
import UIKit
@testable import nodeseek

struct HTMLContentRendererTests {
    @Test func scalesOversizedImageAttachmentsToContentWidth() {
        let renderer = HTMLContentRenderer()
        let attachment = NSTextAttachment()
        attachment.bounds = CGRect(x: 0, y: 0, width: 800, height: 400)
        let attributed = NSMutableAttributedString(attachment: attachment)

        renderer.scaleImageAttachments(in: attributed, maxImageWidth: 320)

        #expect(attachment.bounds.width == 320)
        #expect(attachment.bounds.height == 160)
    }
}
