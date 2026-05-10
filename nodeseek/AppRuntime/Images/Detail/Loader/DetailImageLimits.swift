//
//  DetailImageLimits.swift
//  nodeseek
//
//  Created by Codex on 2026/5/10.
//

import CoreGraphics

enum DetailImageLimits {
    static let maxPixelSide: CGFloat = 16384
    static let fallbackSize = CGSize(width: 8, height: 8)
    static let thumbnailInitialQuality: CGFloat = 0.82
    static let thumbnailMinimumQuality: CGFloat = 0.55
    static let thumbnailMinimumPixelSide: CGFloat = 64
}
