//
//  FloatingViewProtocol.swift
//  nodeseek
//
//  基于 Good Doctor 的 FloatingViewProtocol 组件裁剪适配。
//

import UIKit

protocol FloatingViewProtocol: AnyObject {
    var component: FloatingViewProtocolComponent { get }
    var isDraggable: Bool { get set }
    var isAutoAdsorb: Bool { get set }
    var adsorbableEdges: FloatingAdsorbableEdges { get set }
    var adsorbPriority: FloatingAdsorbPriority { get set }
    var adsorbAnimationDuration: TimeInterval { get set }
    var minAdsorbableSpacings: UIEdgeInsets { get set }
    var isAutoPartiallyHide: Bool { get set }
    var partiallyHidePercent: CGFloat { get set }
    var partiallyHideAnimationDuration: TimeInterval { get set }
    var floatingEdgeInsets: UIEdgeInsets { get set }
}

extension FloatingViewProtocol where Self: UIView {
    var isDraggable: Bool {
        get { component.isDraggable }
        set { component.isDraggable = newValue }
    }

    var isAutoAdsorb: Bool {
        get { component.isAutoAdsorb }
        set { component.isAutoAdsorb = newValue }
    }

    var adsorbableEdges: FloatingAdsorbableEdges {
        get { component.adsorbableEdges }
        set { component.adsorbableEdges = newValue }
    }

    var adsorbPriority: FloatingAdsorbPriority {
        get { component.adsorbPriority }
        set { component.adsorbPriority = newValue }
    }

    var adsorbAnimationDuration: TimeInterval {
        get { component.adsorbAnimationDuration }
        set { component.adsorbAnimationDuration = newValue }
    }

    var isAutoPartiallyHide: Bool {
        get { component.isAutoPartiallyHide }
        set { component.isAutoPartiallyHide = newValue }
    }

    var partiallyHidePercent: CGFloat {
        get { component.partiallyHidePercent }
        set { component.partiallyHidePercent = newValue }
    }

    var partiallyHideAnimationDuration: TimeInterval {
        get { component.partiallyHideAnimationDuration }
        set { component.partiallyHideAnimationDuration = newValue }
    }

    var floatingEdgeInsets: UIEdgeInsets {
        get { component.floatingEdgeInsets }
        set { component.floatingEdgeInsets = newValue }
    }

    var minAdsorbableSpacings: UIEdgeInsets {
        get {
            if let spacings = component.minAdsorbableSpacings {
                return spacings
            }
            guard let superview else { return .zero }
            let halfSuperWidth = superview.frame.width / 2
            return UIEdgeInsets(
                top: floatingEdgeInsets.top > 0 ? 100 : 100 - floatingEdgeInsets.top,
                left: halfSuperWidth - floatingEdgeInsets.left,
                bottom: floatingEdgeInsets.bottom > 0 ? 100 : 100 - floatingEdgeInsets.bottom,
                right: halfSuperWidth - floatingEdgeInsets.right
            )
        }
        set {
            component.minAdsorbableSpacings = newValue
        }
    }
}
