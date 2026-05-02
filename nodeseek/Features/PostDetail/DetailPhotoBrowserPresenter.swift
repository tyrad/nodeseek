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
        browser.isLoopingEnabled = false
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
        DetailImageLoader.shared.loadOriginalImagePayload(for: imageURL) { [weak self, weak browser, weak sourceView] result in
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
        DetailImageLoader.shared.loadOriginalImagePayload(for: imageURL) { [weak self, weak browser] result in
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

    private static func writeTemporaryShareFile(payload: DetailOriginalImagePayload, index: Int) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NodeSeekSharedImages", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("nodeseek-image-\(index).\(payload.suggestedFileExtension)")
        try payload.data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    private func saveToPhotoLibrary(payload: DetailOriginalImagePayload, browser: JXPhotoBrowserViewController) {
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
