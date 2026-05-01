//
//  DetailImageConfig.swift
//  nodeseek
//
//  Created by Codex on 2026/5/1.
//

import CoreGraphics
import Foundation

enum DetailImageOptimizationMode: Equatable {
    case disabled
    case enabled(maxPixelSide: CGFloat, maxThumbnailBytes: Int, loggingEnabled: Bool)
}

enum DetailImageConfig {
    static var optimizationMode: DetailImageOptimizationMode = .enabled(
        maxPixelSide: 900,
        maxThumbnailBytes: 300 * 1024,
        loggingEnabled: false
    )
}
