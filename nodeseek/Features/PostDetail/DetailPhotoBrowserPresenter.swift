//
//  DetailPhotoBrowserPresenter.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import JXPhotoBrowser
import UIKit

final class DetailPhotoBrowserPresenter: NSObject, JXPhotoBrowserDelegate {
    private let imageURLs: [URL]

    init(imageURLs: [URL]) {
        self.imageURLs = imageURLs
        super.init()
    }

    func present(from viewController: UIViewController, initialIndex: Int) {
        guard imageURLs.isEmpty == false else { return }

        let browser = JXPhotoBrowserViewController()
        browser.delegate = self
        browser.initialIndex = min(max(initialIndex, 0), imageURLs.count - 1)
        browser.transitionType = .fade
        browser.addOverlay(JXPageIndicatorOverlay())
        browser.present(from: viewController)
    }

    func numberOfItems(in browser: JXPhotoBrowserViewController) -> Int {
        imageURLs.count
    }

    func photoBrowser(
        _ browser: JXPhotoBrowserViewController,
        cellForItemAt index: Int,
        at indexPath: IndexPath
    ) -> JXPhotoBrowserAnyCell {
        browser.dequeueReusableCell(
            withReuseIdentifier: JXZoomImageCell.reuseIdentifier,
            for: indexPath
        ) as! JXZoomImageCell
    }

    func photoBrowser(_ browser: JXPhotoBrowserViewController, willDisplay cell: JXPhotoBrowserAnyCell, at index: Int) {
        guard let photoCell = cell as? JXZoomImageCell else { return }
        let imageURL = imageURLs[index]
        let requestKey = imageURL.absoluteString
        photoCell.imageView.image = nil
        photoCell.imageView.accessibilityIdentifier = requestKey
        DetailImageLoader.shared.loadImageForPreview(imageURL) { [weak photoCell] image in
            DispatchQueue.main.async {
                guard let photoCell else { return }
                guard photoCell.imageView.accessibilityIdentifier == requestKey else { return }
                photoCell.imageView.image = image
                photoCell.setNeedsLayout()
            }
        }
    }

    func photoBrowser(_ browser: JXPhotoBrowserViewController, didEndDisplaying cell: JXPhotoBrowserAnyCell, at index: Int) {
        guard let photoCell = cell as? JXZoomImageCell else { return }
        photoCell.imageView.accessibilityIdentifier = nil
        photoCell.imageView.image = nil
    }
}
