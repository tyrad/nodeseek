//
//  ThemeRefreshableNode.swift
//  nodeseek
//
//  Created by Codex on 2026/5/8.
//

import AsyncDisplayKit
import UIKit

/// 让 ASDisplayNode 子类以统一方式响应 iOS 暗黑模式等 trait 变化。
///
/// 用法：
/// 1) Node conform `ThemeRefreshableNode`，实现 `applyCurrentTheme()`（只做颜色/富文本等与 trait 强相关的东西）
/// 2) 在 `didLoad()` 里 `themeTraitObserver.install(on: self)`
protocol ThemeRefreshableNode: AnyObject {
    /// 将当前 trait 对应的主题样式应用到 node（颜色、富文本、背景等）。
    func applyCurrentTheme()
    @discardableResult
    func refreshAppearanceForCurrentTraits() -> Bool
}

extension ThemeRefreshableNode where Self: ASDisplayNode {
    /// 统一的刷新入口：重新应用主题，并触发布局/绘制刷新。
    ///
    /// 返回值用于单元测试或调用方做进一步判断；默认实现始终返回 true。
    @discardableResult
    func refreshAppearanceForCurrentTraits() -> Bool {
        applyCurrentTheme()
        setNeedsLayout()
        setNeedsDisplay()
        return true
    }
}

/// 监听 view 的 trait 切换并触发 Node 刷新。
final class ThemeTraitObserver {
    private var isInstalled = false
    private weak var fallbackObserverView: ThemeTraitObserverView?

    func install<Node>(on node: Node) where Node: ASDisplayNode, Node: ThemeRefreshableNode {
        guard isInstalled == false else { return }
        guard node.isNodeLoaded else { return }
        isInstalled = true

        let view = node.view
        node.refreshAppearanceForCurrentTraits()

        if #available(iOS 17.0, *) {
            view.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak node] (view: UIView, previousTraitCollection: UITraitCollection) in
                guard let node else { return }
                guard previousTraitCollection.userInterfaceStyle != view.traitCollection.userInterfaceStyle else { return }

                node.refreshAppearanceForCurrentTraits()
            }
        } else {
            let observerView = ThemeTraitObserverView { [weak node] previousTraitCollection, currentTraitCollection in
                guard let node else { return }
                guard previousTraitCollection?.userInterfaceStyle != currentTraitCollection.userInterfaceStyle else { return }

                node.refreshAppearanceForCurrentTraits()
            }
            view.addSubview(observerView)
            fallbackObserverView = observerView
        }
    }
}

private final class ThemeTraitObserverView: UIView {
    private let onTraitCollectionDidChange: (UITraitCollection?, UITraitCollection) -> Void

    init(onTraitCollectionDidChange: @escaping (UITraitCollection?, UITraitCollection) -> Void) {
        self.onTraitCollectionDidChange = onTraitCollectionDidChange
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ThemeTraitObserverView does not support storyboard initialization")
    }

    @available(iOS, introduced: 2.0, deprecated: 17.0)
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        onTraitCollectionDidChange(previousTraitCollection, traitCollection)
    }
}
