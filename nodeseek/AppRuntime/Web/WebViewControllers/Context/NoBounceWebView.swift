//
//  NoBounceWebView.swift
//  nodeseek
//

import UIKit
import WebKit

final class NoBounceWebView: WKWebView {
    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        disableScrollBounce()
        configurePageBackground()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        disableScrollBounce()
        configurePageBackground()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateUnderPageBackgroundColor()
    }

    @available(iOS, introduced: 2.0, deprecated: 17.0)
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else {
            return
        }
        updateUnderPageBackgroundColor()
    }

    private func disableScrollBounce() {
        scrollView.bounces = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
    }

    private func configurePageBackground() {
        isOpaque = false
        backgroundColor = .clear
        scrollView.backgroundColor = .systemBackground
        updateUnderPageBackgroundColor()
    }

    private func updateUnderPageBackgroundColor() {
        if #available(iOS 15.0, *) {
            underPageBackgroundColor = UIColor.systemBackground.resolvedColor(with: traitCollection)
        }
    }
}
