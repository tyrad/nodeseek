//
//  UIView+Floating.swift
//  nodeseek
//
//  基于 Good Doctor 的 FloatingViewProtocol 组件裁剪适配。
//

import ObjectiveC
import UIKit

extension UIView {
    private struct AssociatedKeys {
        static var floatingPanGestureKey: UInt8 = 0
        static var floatingDelegateKey: UInt8 = 0
    }

    weak var floatingDelegate: FloatingViewDelegate? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.floatingDelegateKey) as? FloatingViewDelegate
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.floatingDelegateKey, newValue, .OBJC_ASSOCIATION_ASSIGN)
        }
    }

    var floatingPanGesture: UIPanGestureRecognizer? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.floatingPanGestureKey) as? UIPanGestureRecognizer
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.floatingPanGestureKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    func addFloatingPanGestureRecognizer() {
        addFloatingPanGestureRecognizer(to: self)
    }

    func addFloatingPanGestureRecognizer(to targetView: UIView) {
        guard floatingPanGesture == nil else { return }
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleFloatingViewPanGesture(_:)))
        panGesture.cancelsTouchesInView = false
        panGesture.delaysTouchesBegan = false
        panGesture.delaysTouchesEnded = false
        floatingPanGesture = panGesture
        targetView.addGestureRecognizer(panGesture)
    }

    @objc private func handleFloatingViewPanGesture(_ pan: UIPanGestureRecognizer) {
        guard let view = self as? (UIView & FloatingViewProtocol), view.isDraggable else { return }

        switch pan.state {
        case .began:
            floatingDelegate?.floatingViewDidBeginDragging(panGestureRecognizer: pan)
        case .changed:
            defer {
                pan.setTranslation(.zero, in: superview)
            }
            let translation = pan.translation(in: superview)
            modifyOrigin(withTranslation: translation)
            floatingDelegate?.floatingViewDidMove(panGestureRecognizer: pan)
        case .ended, .cancelled:
            animateToAdsorb()
            floatingDelegate?.floatingViewDidEndDragging(panGestureRecognizer: pan)
        default:
            break
        }
    }

    private func modifyOrigin(withTranslation translation: CGPoint) {
        guard let view = self as? FloatingViewProtocol, let superview else { return }

        let minOriginX = view.isAutoAdsorb ? min(view.floatingEdgeInsets.left, 0) : view.floatingEdgeInsets.left
        let minOriginY = view.floatingEdgeInsets.top
        let maxOriginX = view.isAutoAdsorb
            ? max(superview.bounds.width - bounds.width - view.floatingEdgeInsets.right, superview.bounds.width - bounds.width)
            : superview.bounds.width - bounds.width - view.floatingEdgeInsets.right
        let maxOriginY = superview.bounds.height - bounds.height - view.floatingEdgeInsets.bottom
        let nextOriginX = frame.origin.x + translation.x
        let nextOriginY = frame.origin.y + translation.y

        if (nextOriginX <= maxOriginX && translation.x > 0) || (nextOriginX >= minOriginX && translation.x < 0) {
            frame.origin.x = nextOriginX
        }
        if (nextOriginY <= maxOriginY && translation.y > 0) || (nextOriginY >= minOriginY && translation.y < 0) {
            frame.origin.y = nextOriginY
        }
    }

    private func animateToAdsorb() {
        guard let view = self as? FloatingViewProtocol,
              let superview,
              view.isAutoAdsorb,
              view.floatingEdgeInsets.left + view.floatingEdgeInsets.right + frame.width * 2 <= superview.frame.width,
              view.floatingEdgeInsets.top + view.floatingEdgeInsets.bottom + frame.height * 2 <= superview.frame.height else {
            return
        }

        let accessibleCenterX = (superview.frame.width + view.floatingEdgeInsets.left - view.floatingEdgeInsets.right) / 2
        let accessibleCenterY = (superview.frame.height + view.floatingEdgeInsets.top - view.floatingEdgeInsets.bottom) / 2
        let accessibleMinX = view.floatingEdgeInsets.left
        let accessibleMinY = view.floatingEdgeInsets.top
        let accessibleMaxX = superview.bounds.width - view.floatingEdgeInsets.right
        let accessibleMaxY = superview.bounds.height - view.floatingEdgeInsets.bottom
        var destinationOrigin = frame.origin
        var adsorbedEdges: [FloatingAdsorbableEdges] = []

        if view.adsorbableEdges.contains(.top), center.y < accessibleCenterY, frame.minY < view.minAdsorbableSpacings.top + accessibleMinY {
            destinationOrigin.y = max(accessibleMinY, 0)
            adsorbedEdges.append(.top)
        } else if view.adsorbableEdges.contains(.bottom), center.y >= accessibleCenterY, frame.maxY > accessibleMaxY - view.minAdsorbableSpacings.bottom {
            destinationOrigin.y = min(accessibleMaxY - frame.height, superview.frame.height - frame.height)
            adsorbedEdges.append(.bottom)
        }

        if view.adsorbableEdges.contains(.left), center.x < accessibleCenterX, frame.minX < view.minAdsorbableSpacings.left + accessibleMinX {
            destinationOrigin.x = max(accessibleMinX, 0)
            adsorbedEdges.append(.left)
        } else if view.adsorbableEdges.contains(.right), center.x >= accessibleCenterX, frame.maxX > accessibleMaxX - view.minAdsorbableSpacings.right {
            destinationOrigin.x = accessibleMaxX - frame.width
            adsorbedEdges.append(.right)
        }

        switch view.adsorbPriority {
        case .horizontalHigher:
            guard adsorbedEdges.count == 2 else { break }
            if adsorbedEdges.contains(.top) {
                destinationOrigin.y = max(frame.origin.y, accessibleMinY, 0)
            } else if adsorbedEdges.contains(.bottom) {
                destinationOrigin.y = min(frame.origin.y, accessibleMaxY - bounds.height, superview.frame.height - bounds.height)
            }
            adsorbedEdges = adsorbedEdges.filter { $0 == .left || $0 == .right }
        case .verticalHigher:
            guard adsorbedEdges.count == 2 else { break }
            if adsorbedEdges.contains(.left) {
                destinationOrigin.x = max(frame.origin.x, accessibleMinX, 0)
            } else if adsorbedEdges.contains(.right) {
                destinationOrigin.x = min(frame.origin.x, accessibleMaxX - bounds.width)
            }
            adsorbedEdges = adsorbedEdges.filter { $0 == .top || $0 == .bottom }
        case .equal:
            break
        }

        guard destinationOrigin != frame.origin else { return }
        UIView.animate(withDuration: view.adsorbAnimationDuration, animations: {
            self.frame.origin = destinationOrigin
        }) { _ in
            self.animatePartiallyHideView(atEdges: adsorbedEdges)
        }
    }

    private func animatePartiallyHideView(atEdges edges: [FloatingAdsorbableEdges]) {
        guard let view = self as? (UIView & FloatingViewProtocol), view.isAutoPartiallyHide else { return }

        var destinationOrigin = frame.origin
        for edge in edges {
            if edge == .top {
                destinationOrigin.y -= frame.height * view.partiallyHidePercent
            }
            if edge == .left {
                destinationOrigin.x -= frame.width * view.partiallyHidePercent
            }
            if edge == .bottom {
                destinationOrigin.y += frame.height * view.partiallyHidePercent
            }
            if edge == .right {
                destinationOrigin.x += frame.width * view.partiallyHidePercent
            }
        }

        guard destinationOrigin != frame.origin else { return }
        UIView.animate(withDuration: view.partiallyHideAnimationDuration, animations: {
            self.frame.origin = destinationOrigin
        }) { _ in
            self.floatingDelegate?.floatingViewFinishedPartiallyHideAnimation()
        }
    }

    func applyFloatingDockedCorners(for edge: FloatingAdsorbableEdges) {
        switch edge {
        case .left:
            layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        case .right:
            layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        default:
            layer.maskedCorners = [
                .layerMinXMinYCorner,
                .layerMinXMaxYCorner,
                .layerMaxXMinYCorner,
                .layerMaxXMaxYCorner
            ]
        }
    }
}
