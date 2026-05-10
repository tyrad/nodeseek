//
//  DetailImageConfig.swift
//  nodeseek
//
//  Created by Codex on 2026/5/1.
//

import Foundation

enum DetailImageOptimizationMode: Equatable {
    case disabled
    case enabled(maxThumbnailBytes: Int, loggingEnabled: Bool)
}

enum DetailImageConfig {
    static var optimizationMode: DetailImageOptimizationMode = .enabled(
        maxThumbnailBytes: 300 * 1024,
        loggingEnabled: false
    )
}
