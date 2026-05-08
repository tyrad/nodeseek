//
//  NodeSeekWebViewContextTests.swift
//  nodeseekTests
//

import Testing
import UIKit
import WebKit
@testable import nodeseek

@MainActor
struct NodeSeekWebViewContextTests {
    @Test func disablesScrollBounceForSharedWebView() {
        let context = NodeSeekWebViewContext()

        #expect(context.webView.scrollView.bounces == false)
        #expect(context.webView.scrollView.alwaysBounceVertical == false)
        #expect(context.webView.scrollView.alwaysBounceHorizontal == false)
    }

    @Test func sharedWebViewUsesSystemBackgroundBehindPageContent() {
        let context = NodeSeekWebViewContext()

        #expect(context.webView.isOpaque == false)
        #expect(context.webView.backgroundColor == .clear)
        #expect(context.webView.scrollView.backgroundColor == .systemBackground)

        if #available(iOS 15.0, *) {
            #expect(
                colorsMatch(
                    context.webView.underPageBackgroundColor,
                    .systemBackground,
                    traits: context.webView.traitCollection
                )
            )
        }
    }

    @Test func sharedWebViewUpdatesUnderPageBackgroundForDarkInterfaceStyle() {
        let context = NodeSeekWebViewContext()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.overrideUserInterfaceStyle = .dark
        window.addSubview(context.webView)
        window.makeKeyAndVisible()

        defer {
            context.webView.removeFromSuperview()
            window.isHidden = true
        }

        if #available(iOS 15.0, *) {
            #expect(context.webView.traitCollection.userInterfaceStyle == .dark)
            #expect(
                colorsMatch(
                    context.webView.underPageBackgroundColor,
                    .systemBackground,
                    traits: context.webView.traitCollection
                )
            )
        }
    }

    private func colorsMatch(_ lhs: UIColor, _ rhs: UIColor, traits: UITraitCollection) -> Bool {
        let lhsComponents = rgbaComponents(lhs.resolvedColor(with: traits))
        let rhsComponents = rgbaComponents(rhs.resolvedColor(with: traits))
        return zip(lhsComponents, rhsComponents).allSatisfy { abs($0 - $1) < 0.001 }
    }

    private func rgbaComponents(_ color: UIColor) -> [CGFloat] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue, alpha]
    }
}
