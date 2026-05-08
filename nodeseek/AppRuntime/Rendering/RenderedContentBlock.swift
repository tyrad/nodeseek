//
//  RenderedContentBlock.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

struct RenderedTableBlock: Equatable {
    struct Row: Equatable {
        let cells: [Cell]
        let isHeader: Bool
    }

    struct Cell: Equatable {
        struct Link: Equatable {
            let location: Int
            let length: Int
            let url: URL

            var nsRange: NSRange {
                NSRange(location: location, length: length)
            }
        }

        let text: String
        let links: [Link]
        let imageURL: URL?
        let isHeader: Bool

        init(text: String, links: [Link] = [], imageURL: URL? = nil, isHeader: Bool) {
            self.text = text
            self.links = links
            self.imageURL = imageURL
            self.isHeader = isHeader
        }
    }

    let rows: [Row]
}

struct RenderedCodeBlock: Equatable {
    let text: String
}

struct RenderedImageBlock: Equatable {
    let url: URL
    let altText: String?
}

struct RenderedIFrameLinkBlock: Equatable {
    let source: String
    let displayDomain: String
    let openURL: URL
}

struct HTMLContainerShell: Equatable {
    let openingTag: String
    let innerHTML: String
    let closingTag: String
}

enum RenderedContentBlock {
    case text(NSAttributedString)
    case table(RenderedTableBlock)
    case codeBlock(RenderedCodeBlock)
    case image(RenderedImageBlock)
    case iframeLink(RenderedIFrameLinkBlock)
    case imagePlaceholder(URL?)
    case unsupported(reason: String)
}
