//
//  NoBounceWebView.swift
//  nodeseek
//

import WebKit

final class NoBounceWebView: WKWebView {
    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        disableScrollBounce()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        disableScrollBounce()
    }

    private func disableScrollBounce() {
        scrollView.bounces = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
    }
}
