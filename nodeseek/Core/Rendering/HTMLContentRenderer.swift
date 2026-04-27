//
//  HTMLContentRenderer.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import UIKit

struct HTMLContentRenderer {
    private enum Layout {
        static let defaultMaxImageWidth: CGFloat = 320
    }

    func render(fragment: String, baseURL: URL) -> [RenderedContentBlock] {
        render(fragment: fragment, baseURL: baseURL, maxImageWidth: Layout.defaultMaxImageWidth)
    }

    func render(fragment: String, baseURL: URL, maxImageWidth: CGFloat) -> [RenderedContentBlock] {
        guard fragment.isEmpty == false else { return [] }

        let html = """
        <html>
        <head>
        <base href="\(baseURL.absoluteString)">
        <style>
        body { font: -apple-system-body; color: #111; }
        img { max-width: 100%; height: auto; }
        blockquote { border-left: 3px solid #d0d0d0; margin-left: 0; padding-left: 10px; color: #555; }
        </style>
        </head>
        <body>\(fragment)</body>
        </html>
        """

        guard let data = html.data(using: .utf8) else {
            return [.text(NSAttributedString(string: fragment))]
        }

        let attributed = try? NSMutableAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        )

        guard let attributed, attributed.length > 0 else {
            return [.text(NSAttributedString(string: fragment))]
        }

        scaleImageAttachments(in: attributed, maxImageWidth: maxImageWidth)
        attributed.addAttributes(
            [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.label
            ],
            range: NSRange(location: 0, length: attributed.length)
        )

        return [.text(attributed)]
    }

    func scaleImageAttachments(in attributed: NSMutableAttributedString, maxImageWidth: CGFloat) {
        guard maxImageWidth > 0 else { return }

        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, _ in
            guard let attachment = value as? NSTextAttachment else { return }

            let originalSize = attachment.image?.size ?? attachment.bounds.size
            guard originalSize.width > maxImageWidth, originalSize.width > 0 else { return }

            let scale = maxImageWidth / originalSize.width
            attachment.bounds = CGRect(
                x: 0,
                y: 0,
                width: maxImageWidth,
                height: originalSize.height * scale
            )
        }
    }
}
