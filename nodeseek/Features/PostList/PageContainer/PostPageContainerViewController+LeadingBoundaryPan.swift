//
//  PostPageContainerViewController+LeadingBoundaryPan.swift
//  nodeseek
//

import UIKit

extension PostPageContainerViewController {
    func installLeadingBoundaryPanListener(on scrollView: UIScrollView) {
        guard pagingScrollView !== scrollView else { return }
        pagingScrollView?.panGestureRecognizer.removeTarget(self, action: #selector(handleLeadingBoundaryPan(_:)))
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(handleLeadingBoundaryPan(_:)))
        pagingScrollView = scrollView
    }

    @objc private func handleLeadingBoundaryPan(_ gesture: UIPanGestureRecognizer) {
        guard isAtLeadingBoundary else {
            maximumLeadingBoundaryPullDistance = 0
            return
        }

        switch gesture.state {
        case .began:
            maximumLeadingBoundaryPullDistance = leadingBoundaryPullDistance(from: gesture)
        case .changed:
            maximumLeadingBoundaryPullDistance = max(
                maximumLeadingBoundaryPullDistance,
                leadingBoundaryPullDistance(from: gesture)
            )
        case .ended:
            let shouldOpenSideMenu = maximumLeadingBoundaryPullDistance >= LeadingBoundaryPullLayout.triggerDistance
            maximumLeadingBoundaryPullDistance = 0
            if shouldOpenSideMenu {
                eventDelegate?.postPageContainerViewControllerDidRequestLeadingSideMenu(self)
            }
        case .cancelled, .failed:
            maximumLeadingBoundaryPullDistance = 0
        default:
            break
        }
    }

    private func leadingBoundaryPullDistance(from gesture: UIPanGestureRecognizer) -> CGFloat {
        let translation = gesture.translation(in: view)
        guard translation.x > 0 else { return 0 }
        guard abs(translation.x) > abs(translation.y) * LeadingBoundaryPullLayout.horizontalTranslationBias else {
            return 0
        }
        return translation.x
    }

    private var isAtLeadingBoundary: Bool {
        guard let firstCategory = categories.first else { return false }
        return currentCategory == firstCategory
    }
}

private enum LeadingBoundaryPullLayout {
    static let triggerDistance: CGFloat = 72
    static let horizontalTranslationBias: CGFloat = 1.15
}
