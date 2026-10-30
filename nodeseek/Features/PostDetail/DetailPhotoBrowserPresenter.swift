//
//  DetailPhotoBrowserPresenter.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import JXPhotoBrowser
import Photos
import UIKit

final class DetailPhotoBrowserPresenter: NSObject, JXPhotoBrowserDelegate {
    private let imageURLs: [URL]
    private weak var sourceRoot: UIView?
    private weak var anchorView: UIImageView?
    private var anchorURL: URL?
    private weak var hiddenThumbnail: UIImageView?

    init(
        imageURLs: [URL],
        sourceRoot: UIView? = nil,
        anchorView: UIImageView? = nil,
        anchorURL: URL? = nil
    ) {
        self.imageURLs = imageURLs
        self.sourceRoot = sourceRoot
        self.anchorView = anchorView
        self.anchorURL = anchorURL
        super.init()
    }

    func present(from viewController: UIViewController, initialIndex: Int) {
        guard imageURLs.isEmpty == false else { return }

        sourceRoot = viewController.view
        if let anchor = DetailPhotoTransitionAnchor.take() {
            anchorView = anchor.imageView
            anchorURL = anchor.url
        }

        let browser = DetailPhotoBrowserController()
        browser.delegate = self
        browser.initialIndex = min(max(initialIndex, 0), imageURLs.count - 1)
        // 源图还在屏幕上就从它缩放进出；不在屏幕上或开启减少动态效果时直接淡入淡出。
        browser.transitionType = canZoom(at: browser.initialIndex) ? .zoom : .fade
        browser.isLoopingEnabled = false
        browser.prepareForDismiss = { [weak self, weak browser] in
            guard let self, let browser else { return }
            self.applyDismissTransition(on: browser)
        }
        browser.onDidLeave = { [weak self] in
            self?.restoreHiddenThumbnail()
        }
        browser.addOverlay(JXPageIndicatorOverlay())

        let actionOverlay = DetailPhotoActionOverlay()
        actionOverlay.onTap = { [weak self] browser, sourceView in
            self?.presentActionMenu(from: browser, sourceView: sourceView)
        }
        browser.addOverlay(actionOverlay)

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
        DetailImageDimmingView.install(on: photoCell.imageView)
        let imageURL = imageURLs[index]
        let requestKey = imageURL.absoluteString
        // 先放详情里已经显示的图，缩放结束时目标位置才有内容，清晰图随后替换。
        photoCell.imageView.image = thumbnail(at: index)?.image
        photoCell.imageView.accessibilityIdentifier = requestKey
        photoCell.setNeedsLayout()
        ImageLoad.url(imageURL).toDetailPreview().load { [weak photoCell] image in
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

    func photoBrowser(_ browser: JXPhotoBrowserViewController, thumbnailViewAt index: Int) -> UIView? {
        thumbnail(at: index)
    }

    func photoBrowser(_ browser: JXPhotoBrowserViewController, setThumbnailHidden hidden: Bool, at index: Int) {
        guard let thumbnail = thumbnail(at: index) else {
            if !hidden {
                restoreHiddenThumbnail()
            }
            return
        }
        if hiddenThumbnail !== thumbnail {
            hiddenThumbnail?.isHidden = false
        }
        thumbnail.isHidden = hidden
        hiddenThumbnail = hidden ? thumbnail : nil
    }

    func applyDismissTransition(
        on browser: JXPhotoBrowserViewController,
        reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled
    ) {
        let zoom = canZoom(at: browser.pageIndex, reduceMotion: reduceMotion)
        browser.transitionType = zoom ? .zoom : .fade
        // 淡出不会把源图显示回来，先恢复，避免列表里留下一个空洞。
        if !zoom {
            restoreHiddenThumbnail()
        }
    }

    private func canZoom(at index: Int, reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled) -> Bool {
        !reduceMotion && thumbnail(at: index) != nil
    }

    private func thumbnail(at index: Int) -> UIImageView? {
        guard imageURLs.indices.contains(index) else { return nil }
        return DetailPhotoThumbnailFinder.thumbnail(
            matching: imageURLs[index],
            in: sourceRoot,
            anchorView: anchorView,
            anchorURL: anchorURL
        )
    }

    private func restoreHiddenThumbnail() {
        hiddenThumbnail?.isHidden = false
        hiddenThumbnail = nil
    }

    private func presentActionMenu(from browser: JXPhotoBrowserViewController, sourceView: UIView) {
        guard imageURLs.indices.contains(browser.pageIndex) else {
            showMessage("当前图片无效", in: browser)
            return
        }

        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "分享图片", style: .default) { [weak self, weak browser, weak sourceView] _ in
            guard let self, let browser, let sourceView else { return }
            self.shareCurrentImage(from: browser, sourceView: sourceView)
        })
        alert.addAction(UIAlertAction(title: "保存到相册", style: .default) { [weak self, weak browser] _ in
            guard let self, let browser else { return }
            self.saveCurrentImage(from: browser)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.popoverPresentationController?.sourceView = sourceView
        alert.popoverPresentationController?.sourceRect = sourceView.bounds
        browser.present(alert, animated: true)
    }

    private func shareCurrentImage(from browser: JXPhotoBrowserViewController, sourceView: UIView) {
        guard imageURLs.indices.contains(browser.pageIndex) else {
            showMessage("当前图片无效", in: browser)
            return
        }

        let imageURL = imageURLs[browser.pageIndex]
        ImageLoad.url(imageURL).toOriginalPayload().load { [weak self, weak browser, weak sourceView] result in
            DispatchQueue.main.async {
                guard let self, let browser, let sourceView else { return }
                switch result {
                case .success(let payload):
                    do {
                        let fileURL = try Self.writeTemporaryShareFile(payload: payload, index: browser.pageIndex)
                        let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
                        activity.popoverPresentationController?.sourceView = sourceView
                        activity.popoverPresentationController?.sourceRect = sourceView.bounds
                        browser.present(activity, animated: true)
                    } catch {
                        self.showMessage("分享失败", in: browser)
                    }
                case .failure:
                    self.showMessage("图片加载失败，暂时无法操作", in: browser)
                }
            }
        }
    }

    private func saveCurrentImage(from browser: JXPhotoBrowserViewController) {
        guard imageURLs.indices.contains(browser.pageIndex) else {
            showMessage("当前图片无效", in: browser)
            return
        }

        let imageURL = imageURLs[browser.pageIndex]
        ImageLoad.url(imageURL).toOriginalPayload().load { [weak self, weak browser] result in
            DispatchQueue.main.async {
                guard let self, let browser else { return }
                switch result {
                case .success(let payload):
                    self.saveToPhotoLibrary(payload: payload, browser: browser)
                case .failure:
                    self.showMessage("图片加载失败，暂时无法操作", in: browser)
                }
            }
        }
    }

    private static func writeTemporaryShareFile(payload: DetailOriginalFilePayload, index: Int) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NodeSeekSharedImages", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("nodeseek-image-\(index).\(payload.suggestedFileExtension)")
        try payload.data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    private func saveToPhotoLibrary(payload: DetailOriginalFilePayload, browser: JXPhotoBrowserViewController) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self, weak browser] status in
            guard let self, let browser else { return }
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.showMessage("保存失败", in: browser)
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: payload.data, options: nil)
            } completionHandler: { [weak self, weak browser] success, _ in
                DispatchQueue.main.async {
                    guard let self, let browser else { return }
                    self.showMessage(success ? "已保存到相册" : "保存失败", in: browser)
                }
            }
        }
    }

    private func showMessage(_ message: String, in browser: JXPhotoBrowserViewController) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        browser.present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak alert] in
            alert?.dismiss(animated: true)
        }
    }
}
