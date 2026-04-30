//
//  NodeSeekDebugConfig.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit

struct NodeSeekDebugConfig {
    #if DEBUG
    static let enablePostDetailTestEntry = true
    static let enableWebViewDebugOverlay = false
    static let enableDetailRenderDiagnostics = false
    #else
    static let enablePostDetailTestEntry = false
    static let enableWebViewDebugOverlay = false
    static let enableDetailRenderDiagnostics = false
    #endif

    static let webViewDebugOverlaySize = CGSize(width: 180, height: 120)
    static let webViewDebugOverlayBottomInset: CGFloat = 8
    static let webViewDebugOverlayLeadingInset: CGFloat = 8
}
