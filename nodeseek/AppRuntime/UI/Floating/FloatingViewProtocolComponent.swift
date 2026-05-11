//
//  FloatingViewProtocolComponent.swift
//  nodeseek
//
//  基于 Good Doctor 的 FloatingViewProtocol 组件裁剪适配。
//

import UIKit

struct FloatingAdsorbableEdges: OptionSet {
    let rawValue: UInt

    static let top = FloatingAdsorbableEdges(rawValue: 1)
    static let left = FloatingAdsorbableEdges(rawValue: 1 << 1)
    static let bottom = FloatingAdsorbableEdges(rawValue: 1 << 2)
    static let right = FloatingAdsorbableEdges(rawValue: 1 << 3)
}

enum FloatingAdsorbPriority: Int {
    case horizontalHigher
    case equal
    case verticalHigher
}

final class FloatingViewProtocolComponent {
    var isDraggable = true
    var isAutoAdsorb = true
    var adsorbableEdges: FloatingAdsorbableEdges = [.top, .left, .bottom, .right]
    var adsorbPriority: FloatingAdsorbPriority = .verticalHigher
    var adsorbAnimationDuration: TimeInterval = 0.35
    var isAutoPartiallyHide = false
    var partiallyHidePercent: CGFloat = 0.5
    var partiallyHideAnimationDuration: TimeInterval = 0.35
    var floatingEdgeInsets: UIEdgeInsets = .zero
    var minAdsorbableSpacings: UIEdgeInsets?
}
