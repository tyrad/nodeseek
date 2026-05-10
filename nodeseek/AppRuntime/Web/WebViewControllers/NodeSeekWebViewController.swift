//
//  NodeSeekWebViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import UIKit

final class NodeSeekWebViewController: BaseWebViewController {
    override var usesCustomUserAgent: Bool {
        false
    }

    init(url: URL, automaticallyLoadsPage: Bool = true) {
        super.init(
            initialURL: url,
            pageTitle: "网页",
            automaticallyLoadsPage: automaticallyLoadsPage
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

#if DEBUG
extension NodeSeekWebViewController {
    var testInitialURL: URL {
        initialURL
    }

    static func nativePostRoute(for url: URL, baseURL: URL) -> NodeSeekPostRoute? {
        nil
    }
}
#endif
