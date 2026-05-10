//
//  DTCoreTextHTMLContentRenderer+HTMLDocument.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import Foundation

extension DTCoreTextHTMLContentRenderer {
    func wrapHTML(fragment: String, baseURL: URL) -> String {
        let bodySize = cssPixelSize(basePointSize: 17)
        let h1Size = cssPixelSize(basePointSize: 24)
        let h2Size = cssPixelSize(basePointSize: 22)
        let h3Size = cssPixelSize(basePointSize: 20)
        let h4Size = cssPixelSize(basePointSize: 19)
        let h5Size = cssPixelSize(basePointSize: 18)
        let h6Size = cssPixelSize(basePointSize: 17)
        let codeSize = cssPixelSize(basePointSize: 13)

        return """
        <html>
        <head>
        <base href="\(baseURL.absoluteString)">
        <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Helvetica, Arial, sans-serif;
            font-size: \(bodySize);
            line-height: 1.42;
            color: #111111;
        }
        article, section, div { margin: 0; padding: 0; }
        p { margin: 0 0 12px 0; }
        h1, h2, h3, h4, h5, h6 {
            margin: 18px 0 8px 0;
            line-height: 1.28;
            font-weight: 700;
            color: #111111;
        }
        h1 { font-size: \(h1Size); }
        h2 { font-size: \(h2Size); color: #2ea44f; }
        h3 { font-size: \(h3Size); }
        h4 { font-size: \(h4Size); }
        h5 { font-size: \(h5Size); }
        h6 { font-size: \(h6Size); }
        strong, b { font-weight: 700; }
        em, i { font-style: italic; }
        s, del, strike { text-decoration: line-through; }
        a { color: #0f8055; text-decoration: none; }
        ul, ol { margin: 0 0 12px 0; padding-left: 22px; }
        li { margin: 0 0 6px 0; }
        img { max-width: 100%; height: auto; margin: 4px 0 12px 0; }
        blockquote {
            background-color: #f6f8fa;
            border-left: 3px solid #d0d7de;
            margin-top: 8px;
            margin-right: 0;
            margin-bottom: 12px;
            margin-left: 0;
            padding-top: 12px;
            padding-right: 10px;
            padding-bottom: 12px;
            padding-left: 8px;
            color: #555555;
        }
        pre {
            font-family: Menlo, Monaco, monospace;
            font-size: \(codeSize);
            line-height: 1.35;
            white-space: pre-wrap;
            margin: 8px 0 12px 0;
        }
        code {
            font-family: Menlo, Monaco, monospace;
            font-size: \(codeSize);
        }
        </style>
        </head>
        <body>\(fragment)</body>
        </html>
        """
    }

    private func cssPixelSize(basePointSize: CGFloat) -> String {
        let size = AppTextSizeSettings.adjustedPointSize(basePointSize: basePointSize)
        return "\(Int(size.rounded()))px"
    }
}
