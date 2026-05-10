//
//  StickerImageRules.swift
//  nodeseek
//
//  Created by Codex on 2026/5/9.
//

import Foundation

enum StickerImageRules {
    static func isStickerURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        let path = url.path.lowercased()
        return path.contains("/static/image/sticker/")
            || path.contains("/sticker/")
    }
}
