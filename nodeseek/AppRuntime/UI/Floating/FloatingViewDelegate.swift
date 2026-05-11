//
//  FloatingViewDelegate.swift
//  nodeseek
//
//  基于 Good Doctor 的 FloatingViewProtocol 组件裁剪适配。
//

import UIKit

protocol FloatingViewDelegate: AnyObject {
    func floatingViewDidBeginDragging(panGestureRecognizer: UIPanGestureRecognizer)
    func floatingViewDidEndDragging(panGestureRecognizer: UIPanGestureRecognizer)
    func floatingViewDidMove(panGestureRecognizer: UIPanGestureRecognizer)
    func floatingViewFinishedPartiallyHideAnimation()
}

extension FloatingViewDelegate {
    func floatingViewDidBeginDragging(panGestureRecognizer: UIPanGestureRecognizer) {}
    func floatingViewDidEndDragging(panGestureRecognizer: UIPanGestureRecognizer) {}
    func floatingViewDidMove(panGestureRecognizer: UIPanGestureRecognizer) {}
    func floatingViewFinishedPartiallyHideAnimation() {}
}
