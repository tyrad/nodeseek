//
//  PostPageContainerViewController+Paging.swift
//  nodeseek
//

import UIKit

extension PostPageContainerViewController: UIPageViewControllerDataSource {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let host = viewController as? PostTextureListHostViewController,
              let index = categories.firstIndex(of: host.category),
              index > 0 else {
            return nil
        }
        return hostViewControllers[categories[index - 1]]
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let host = viewController as? PostTextureListHostViewController,
              let index = categories.firstIndex(of: host.category),
              index < categories.count - 1 else {
            return nil
        }
        return hostViewControllers[categories[index + 1]]
    }
}

extension PostPageContainerViewController: UIPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard finished, completed,
              let current = pageViewController.viewControllers?.first as? PostTextureListHostViewController else {
            return
        }
        updateCurrentCategoryAfterPaging(current.category)
        eventDelegate?.postPageContainerViewController(self, didScrollTo: current.category)
    }
}
