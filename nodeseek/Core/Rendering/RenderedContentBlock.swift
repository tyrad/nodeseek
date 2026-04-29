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
        let text: String
        let imageURL: URL?
        let isHeader: Bool

        init(text: String, imageURL: URL? = nil, isHeader: Bool) {
            self.text = text
            self.imageURL = imageURL
            self.isHeader = isHeader
        }
    }

    let rows: [Row]
}

enum RenderedContentBlock {
    case text(NSAttributedString)
    case table(RenderedTableBlock)
    case imagePlaceholder(URL?)
    case unsupported(reason: String)
}
