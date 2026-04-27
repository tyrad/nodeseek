//
//  NodeSeekDebugConfig.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit

struct NodeSeekDebugConfig {
    // 打开后会把“实际发请求的隐藏 WebView”浮在页面顶层，便于观察请求过程。
    static let enableWebViewDebugOverlay = true

    static let webViewDebugOverlaySize = CGSize(width: 180, height: 120)
    static let webViewDebugOverlayBottomInset: CGFloat = 8
    static let webViewDebugOverlayLeadingInset: CGFloat = 8
}
