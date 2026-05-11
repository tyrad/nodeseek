//
//  FloatingControlContainerView.swift
//  nodeseek
//
//  Created by Codex on 2026/5/11.
//

import UIKit

final class FloatingControlContainerView: UIView, FloatingViewProtocol, FloatingViewDelegate {
    let component = FloatingViewProtocolComponent()

    var onAdsorbedEdgeChanged: ((FloatingAdsorbableEdges) -> Void)?

    private let positionStorageKey: String?
    private let positionStore: FloatingControlPositionStoring
    private var usesCustomPosition = false
    private var currentHorizontalEdge: FloatingAdsorbableEdges = .right

    init(
        accessibilityIdentifier: String,
        positionStorageKey: String? = nil,
        positionStore: FloatingControlPositionStoring = UserDefaultsFloatingControlPositionStore()
    ) {
        self.positionStorageKey = positionStorageKey
        self.positionStore = positionStore
        super.init(frame: .zero)
        self.accessibilityIdentifier = accessibilityIdentifier
        backgroundColor = .clear
        isAutoAdsorb = true
        adsorbableEdges = [.left, .right]
        adsorbPriority = .horizontalHigher
        isAutoPartiallyHide = false
        floatingDelegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func hostControl(_ control: UIView) {
        addSubview(control)
        control.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: leadingAnchor),
            control.trailingAnchor.constraint(equalTo: trailingAnchor),
            control.topAnchor.constraint(equalTo: topAnchor),
            control.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        addFloatingPanGestureRecognizer(to: control)
    }

    func syncFrame(with anchorView: UIView) {
        let anchorFrame = anchorView.frame
        guard usesCustomPosition else {
            frame = anchorFrame
            if applyStoredPositionIfAvailable() {
                usesCustomPosition = true
            }
            clampInsideFloatingBounds()
            notifyCurrentHorizontalEdge()
            return
        }

        let previousMinX = frame.minX
        let previousMidY = frame.midY
        frame.size = anchorView.bounds.size
        if currentHorizontalEdge == .left {
            frame.origin.x = previousMinX
        } else {
            frame.origin.x = anchorFrame.maxX - frame.width
        }
        frame.origin.y = previousMidY - frame.height / 2
        clampInsideFloatingBounds()
        notifyCurrentHorizontalEdge()
    }

    func updateFloatingEdgeInsets(
        in superview: UIView,
        topBoundary: CGFloat? = nil,
        horizontalAnchorView: UIView? = nil
    ) {
        let safeFrame = superview.safeAreaLayoutGuide.layoutFrame
        let baseRightInset = max(superview.bounds.maxX - safeFrame.maxX, 0)
        let anchorRightOutset = horizontalAnchorView.map { max($0.frame.maxX - safeFrame.maxX, 0) } ?? 0
        floatingEdgeInsets = UIEdgeInsets(
            top: max(topBoundary ?? safeFrame.minY, safeFrame.minY),
            left: 0,
            bottom: max(superview.bounds.maxY - safeFrame.maxY, 0),
            right: baseRightInset - anchorRightOutset
        )
        clampInsideFloatingBounds()
    }

    func floatingViewDidBeginDragging(panGestureRecognizer: UIPanGestureRecognizer) {
        usesCustomPosition = true
    }

    func floatingViewDidEndDragging(panGestureRecognizer: UIPanGestureRecognizer) {
        notifyCurrentHorizontalEdge()
        saveCurrentPosition()
    }

    func floatingViewDidMove(panGestureRecognizer: UIPanGestureRecognizer) {
        notifyCurrentHorizontalEdge()
    }

    private func clampInsideFloatingBounds() {
        guard let superview, bounds.isEmpty == false else { return }

        let minX = floatingEdgeInsets.left
        let maxX = superview.bounds.width - floatingEdgeInsets.right - bounds.width
        if maxX >= minX {
            frame.origin.x = min(max(frame.origin.x, minX), maxX)
        }

        let minY = floatingEdgeInsets.top
        let maxY = superview.bounds.height - floatingEdgeInsets.bottom - bounds.height
        if maxY >= minY {
            frame.origin.y = min(max(frame.origin.y, minY), maxY)
        }
    }

    private func notifyCurrentHorizontalEdge() {
        guard let superview else { return }
        let edge: FloatingAdsorbableEdges = center.x < superview.bounds.midX ? .left : .right
        currentHorizontalEdge = edge
        onAdsorbedEdgeChanged?(edge)
    }

    private func applyStoredPositionIfAvailable() -> Bool {
        guard let positionStorageKey,
              let storedPosition = positionStore.position(forKey: positionStorageKey),
              let restoredEdge = horizontalEdge(rawValue: storedPosition.edgeRawValue),
              let superview,
              bounds.isEmpty == false else {
            return false
        }

        currentHorizontalEdge = restoredEdge
        switch restoredEdge {
        case .left:
            frame.origin.x = floatingEdgeInsets.left
        case .right:
            frame.origin.x = superview.bounds.width - floatingEdgeInsets.right - bounds.width
        default:
            break
        }

        let minY = floatingEdgeInsets.top
        let maxY = superview.bounds.height - floatingEdgeInsets.bottom - bounds.height
        if maxY > minY {
            let ratio = min(max(storedPosition.verticalOriginRatio, 0), 1)
            frame.origin.y = minY + (maxY - minY) * ratio
        }
        return true
    }

    private func saveCurrentPosition() {
        guard let positionStorageKey,
              let superview,
              bounds.isEmpty == false else {
            return
        }

        let minY = floatingEdgeInsets.top
        let maxY = superview.bounds.height - floatingEdgeInsets.bottom - bounds.height
        let ratio: CGFloat
        if maxY > minY {
            ratio = min(max((frame.origin.y - minY) / (maxY - minY), 0), 1)
        } else {
            ratio = 0
        }
        positionStore.save(
            FloatingControlPosition(
                edgeRawValue: currentHorizontalEdge.rawValue,
                verticalOriginRatio: ratio
            ),
            forKey: positionStorageKey
        )
    }

    private func horizontalEdge(rawValue: UInt) -> FloatingAdsorbableEdges? {
        let edge = FloatingAdsorbableEdges(rawValue: rawValue)
        if edge == .left || edge == .right {
            return edge
        }
        return nil
    }
}
