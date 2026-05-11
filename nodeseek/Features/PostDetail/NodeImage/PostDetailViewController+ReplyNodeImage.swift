//
//  PostDetailViewController+ReplyNodeImage.swift
//  nodeseek
//
//  Created by Codex on 2026/5/9.
//

import PhotosUI
import UIKit
import UniformTypeIdentifiers

enum ReplyImageSourceOption: Equatable {
    case camera
    case photoLibrary

    static func available(isCameraAvailable: Bool) -> [ReplyImageSourceOption] {
        isCameraAvailable ? [.camera, .photoLibrary] : [.photoLibrary]
    }

    var title: String {
        switch self {
        case .camera:
            return "拍照"
        case .photoLibrary:
            return "从相册选择"
        }
    }
}

extension PostDetailViewController {
    @objc
    func uploadImageTapped() {
        ensureNodeSeekLoggedIn { [weak self] in
            self?.continueImageUploadAfterNodeSeekLogin()
        }
    }

    func continueImageUploadAfterNodeSeekLogin() {
        if nodeImageAPIKeyStore.apiKey()?.isEmpty == false {
            presentImagePicker()
            return
        }

        let authViewController = NodeImageAuthViewController { [weak self] apiKey in
            guard let self else { return }
            nodeImageAPIKeyStore.save(apiKey: apiKey)
            dismiss(animated: true) { [weak self] in
                self?.showToast(message: "NodeImage 已授权")
                self?.presentImagePicker()
            }
        }
        present(UINavigationController(rootViewController: authViewController), animated: true)
    }

    func presentImagePicker() {
        let options = ReplyImageSourceOption.available(
            isCameraAvailable: UIImagePickerController.isSourceTypeAvailable(.camera)
        )
        guard options.contains(.camera) else {
            presentPhotoLibraryPicker()
            return
        }

        let alertController = UIAlertController(title: "上传图片", message: nil, preferredStyle: .actionSheet)
        for option in options {
            alertController.addAction(UIAlertAction(title: option.title, style: .default) { [weak self] _ in
                switch option {
                case .camera:
                    self?.presentCameraPicker()
                case .photoLibrary:
                    self?.presentPhotoLibraryPicker()
                }
            })
        }
        alertController.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = replyImageUploadButton
            popover.sourceRect = replyImageUploadButton.bounds
        }
        present(alertController, animated: true)
    }

    func presentPhotoLibraryPicker() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    func presentCameraPicker() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            presentPhotoLibraryPicker()
            return
        }

        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = self
        present(picker, animated: true)
    }

    func uploadPickedImage(data: Data, fileName: String, mimeType: String) {
        guard let apiKey = nodeImageAPIKeyStore.apiKey(), apiKey.isEmpty == false else {
            showError(message: "请先完成 NodeImage 授权。")
            return
        }
        setReplyImageUploadSubmitting(true)
        imageUploadTask?.cancel()
        let uploadClient = nodeImageUploadClient
        imageUploadTask = Task { [weak self] in
            do {
                let payload = await Task.detached(priority: .userInitiated) {
                    NodeImageUploadImageCompressor.compressedPayload(
                        data: data,
                        fileName: fileName,
                        mimeType: mimeType
                    )
                }.value
                let result = try await uploadClient.uploadImage(
                    data: payload.data,
                    fileName: payload.fileName,
                    mimeType: payload.mimeType,
                    apiKey: apiKey
                )
                await MainActor.run { [weak self] in
                    self?.insertReplyText(result.markdownText)
                    self?.showToast(message: "图片已上传")
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.showError(message: error.localizedDescription)
                }
            }
            await MainActor.run { [weak self] in
                self?.setReplyImageUploadSubmitting(false)
            }
        }
    }

    func setReplyImageUploadSubmitting(_ isSubmitting: Bool) {
        replyImageUploadButton.isEnabled = !isSubmitting
        var configuration = replyImageUploadButton.configuration ?? UIButton.Configuration.plain()
        configuration.showsActivityIndicator = isSubmitting
        configuration.image = isSubmitting ? nil : UIImage(systemName: "photo")
        replyImageUploadButton.configuration = configuration
        replyImageUploadButton.accessibilityLabel = isSubmitting ? "正在上传图片" : "上传图片"
    }

    func insertReplyText(_ insertedText: String) {
        let currentText = replyTextView.text ?? ""
        let range = replyTextView.selectedRange
        guard let textRange = Range(range, in: currentText) else {
            replyTextView.text = currentText + insertedText
            replyTextView.selectedRange = NSRange(location: replyTextView.text.count, length: 0)
            return
        }

        let prefix = currentText[..<textRange.lowerBound]
        let suffix = currentText[textRange.upperBound...]
        let needsLeadingNewline = prefix.isEmpty == false && prefix.last?.isNewline == false
        let needsTrailingNewline = suffix.isEmpty == false && suffix.first?.isNewline == false
        let replacement = [
            needsLeadingNewline ? "\n" : "",
            insertedText,
            needsTrailingNewline ? "\n" : ""
        ].joined()
        replyTextView.text = String(prefix) + replacement + String(suffix)
        replyTextView.selectedRange = NSRange(location: String(prefix).count + replacement.count, length: 0)
    }
}

extension PostDetailViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            showError(message: "请选择图片文件。")
            return
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.showError(message: error.localizedDescription)
                    return
                }
                guard let data else {
                    self.showError(message: "读取图片失败。")
                    return
                }
                let typeIdentifier = provider.registeredTypeIdentifiers.first ?? UTType.jpeg.identifier
                let uniformType = UTType(typeIdentifier)
                let extensionName = uniformType?.preferredFilenameExtension ?? "jpg"
                let mimeType = uniformType?.preferredMIMEType ?? "image/jpeg"
                self.uploadPickedImage(
                    data: data,
                    fileName: "nodeseek-\(Int(Date().timeIntervalSince1970)).\(extensionName)",
                    mimeType: mimeType
                )
            }
        }
    }
}

extension PostDetailViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else {
            showError(message: "读取照片失败。")
            return
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            showError(message: "照片编码失败。")
            return
        }
        uploadPickedImage(
            data: data,
            fileName: "nodeseek-\(Int(Date().timeIntervalSince1970)).jpg",
            mimeType: "image/jpeg"
        )
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
