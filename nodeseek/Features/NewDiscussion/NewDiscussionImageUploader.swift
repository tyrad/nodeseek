//
//  NewDiscussionImageUploader.swift
//  nodeseek
//

import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// 发帖页插图：NodeImage 授权、选图、压缩、按顺序逐张上传。
/// 只负责任务本身，正文里的占位由页面根据回调处理。
final class NewDiscussionImageUploader: NSObject {
    struct Job {
        let id: String
        let data: Data
        let fileName: String
        let mimeType: String
    }

    /// 一次最多选 9 张，和站点单帖插图习惯一致，也避免排队过长。
    static let selectionLimit = 9

    /// 新任务入队：页面在光标处插入占位。
    var onEnqueue: ((Job) -> Void)?
    /// 上传成功，返回图片 Markdown。
    var onSuccess: ((Job, String) -> Void)?
    /// 上传失败：页面去掉占位，任务保留在失败列表里可重试。
    var onFailure: ((Job, Error) -> Void)?
    /// 排队和进行中的任务数变化。
    var onCountChange: ((Int) -> Void)?
    /// 用户选择直接粘贴已有的图片地址，不走图床。
    var onRequestImageLink: (() -> Void)?

    weak var presentingViewController: UIViewController?
    weak var sourceView: UIView?

    private let apiKeyStore: NodeImageAPIKeyStoring
    private let uploadClient: NodeImageUploading
    private var queue: [Job] = []
    private var currentTask: Task<Void, Never>?
    private(set) var failedJobs: [Job] = []
    /// 已选但还在从相册读取的张数，也算进上传中，避免这段时间里能发布。
    private var loadingCount = 0
    /// 关闭页面后递增，让还在读取的相册任务作废。
    private var generation = 0

    init(
        apiKeyStore: NodeImageAPIKeyStoring = KeychainNodeImageAPIKeyStore(),
        uploadClient: NodeImageUploading = NodeImageUploadClient()
    ) {
        self.apiKeyStore = apiKeyStore
        self.uploadClient = uploadClient
    }

    var activeCount: Int {
        loadingCount + queue.count + (currentTask == nil ? 0 : 1)
    }

    // MARK: - 选图

    func start() {
        if apiKeyStore.apiKey()?.isEmpty == false {
            presentSourceOptions()
            return
        }
        presentAuthorizationIntro()
    }

    /// 第一次插图先说明为什么要授权，而不是直接跳出网页。
    private func presentAuthorizationIntro() {
        let alert = UIAlertController(
            title: "插图需要授权 NodeImage",
            message: "图片通过 NodeImage 图床上传，和网页发帖用的是同一个服务。授权一次后就能直接传图。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "去授权", style: .default) { [weak self] _ in
            self?.presentAuthorization()
        })
        alert.addAction(UIAlertAction(title: "手动填写 API Key", style: .default) { [weak self] _ in
            self?.presentManualAPIKeyInput()
        })
        alert.addAction(UIAlertAction(title: "粘贴图片链接", style: .default) { [weak self] _ in
            self?.onRequestImageLink?()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.view.tintColor = .label
        presentingViewController?.present(alert, animated: true)
    }

    private func presentManualAPIKeyInput() {
        let alert = UIAlertController(
            title: "填写 NodeImage API Key",
            message: "在 NodeImage 网站的 API 页面复制后粘贴到这里。",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "X-API-Key"
            field.textContentType = .password
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let apiKey = NodeImageAPIKeyNormalizer.normalized(alert?.textFields?.first?.text ?? "")
            guard !apiKey.isEmpty else { return }
            apiKeyStore.save(apiKey: apiKey)
            presentSourceOptions()
        })
        alert.view.tintColor = .label
        presentingViewController?.present(alert, animated: true)
    }

    private func presentAuthorization() {
        let authViewController = NodeImageAuthViewController { [weak self] apiKey in
            guard let self else { return }
            apiKeyStore.save(apiKey: apiKey)
            presentingViewController?.dismiss(animated: true) { [weak self] in
                self?.presentSourceOptions()
            }
        }
        presentingViewController?.present(UINavigationController(rootViewController: authViewController), animated: true)
    }

    private func presentSourceOptions() {
        let options = ReplyImageSourceOption.available(
            isCameraAvailable: UIImagePickerController.isSourceTypeAvailable(.camera)
        )
        guard options.contains(.camera) else {
            presentPhotoLibraryPicker()
            return
        }

        let sheet = UIAlertController(title: "插入图片", message: nil, preferredStyle: .actionSheet)
        for option in options {
            sheet.addAction(UIAlertAction(title: option.title, style: .default) { [weak self] _ in
                switch option {
                case .camera: self?.presentCameraPicker()
                case .photoLibrary: self?.presentPhotoLibraryPicker()
                }
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = sheet.popoverPresentationController, let sourceView {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }
        presentingViewController?.present(sheet, animated: true)
    }

    private func presentPhotoLibraryPicker() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = Self.selectionLimit
        configuration.selection = .ordered
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        presentingViewController?.present(picker, animated: true)
    }

    private func presentCameraPicker() {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = self
        presentingViewController?.present(picker, animated: true)
    }

    // MARK: - 队列

    func retryFailed() {
        let jobs = failedJobs
        failedJobs.removeAll()
        jobs.forEach(enqueue)
    }

    func discardFailed() {
        failedJobs.removeAll()
    }

    /// 关闭页面时调用：停掉进行中和排队的任务。
    func cancelAll() {
        queue.removeAll()
        currentTask?.cancel()
        currentTask = nil
        failedJobs.removeAll()
        loadingCount = 0
        generation += 1
        onCountChange?(0)
    }

    private func enqueue(data: Data, fileName: String, mimeType: String) {
        enqueue(Job(id: String(UUID().uuidString.prefix(8)).lowercased(), data: data, fileName: fileName, mimeType: mimeType))
    }

    private func enqueue(_ job: Job) {
        queue.append(job)
        onEnqueue?(job)
        onCountChange?(activeCount)
        startNextIfIdle()
    }

    private func startNextIfIdle() {
        guard currentTask == nil, !queue.isEmpty else { return }
        let job = queue.removeFirst()
        guard let apiKey = apiKeyStore.apiKey(), !apiKey.isEmpty else {
            finish(job, result: .failure(NodeImageUploadError.uploadFailed("请先完成 NodeImage 授权。")))
            return
        }
        let uploadClient = uploadClient
        currentTask = Task { [weak self] in
            let result: Result<String, Error>
            do {
                let payload = await Task.detached(priority: .userInitiated) {
                    NodeImageUploadImageCompressor.compressedPayload(
                        data: job.data,
                        fileName: job.fileName,
                        mimeType: job.mimeType
                    )
                }.value
                let uploaded = try await uploadClient.uploadImage(
                    data: payload.data,
                    fileName: payload.fileName,
                    mimeType: payload.mimeType,
                    apiKey: apiKey
                )
                result = .success("![图片](\(uploaded.imageURL.absoluteString))")
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled else { return }
            self?.currentTask = nil
            self?.finish(job, result: result)
        }
    }

    private func finish(_ job: Job, result: Result<String, Error>) {
        switch result {
        case .success(let markdown):
            onSuccess?(job, markdown)
        case .failure(let error):
            AppLog.warning(.postList, "发帖页图片上传失败: error=\(error.localizedDescription)")
            failedJobs.append(job)
            onFailure?(job, error)
        }
        onCountChange?(activeCount)
        startNextIfIdle()
    }

    private static func fileName(extension ext: String, index: Int) -> String {
        "nodeseek-\(Int(Date().timeIntervalSince1970))-\(index).\(ext)"
    }
}

extension NewDiscussionImageUploader: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        let providers = results.map(\.itemProvider).filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        guard !providers.isEmpty else { return }

        // 按选择顺序读取后再统一入队，保证正文里的图片顺序和选择顺序一致。
        loadingCount += providers.count
        onCountChange?(activeCount)
        let generation = generation
        Task { [weak self] in
            var loaded: [(Data, String, String)] = []
            for (index, provider) in providers.enumerated() {
                guard let data = await Self.loadImageData(from: provider) else { continue }
                let uniformType = UTType(provider.registeredTypeIdentifiers.first ?? UTType.jpeg.identifier)
                loaded.append((
                    data,
                    Self.fileName(extension: uniformType?.preferredFilenameExtension ?? "jpg", index: index),
                    uniformType?.preferredMIMEType ?? "image/jpeg"
                ))
            }
            guard let self, generation == self.generation else { return }
            loadingCount -= providers.count
            if loaded.count < providers.count, let presentingViewController {
                let alert = UIAlertController(title: nil, message: "有 \(providers.count - loaded.count) 张图片读取失败，已跳过", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "好", style: .cancel))
                presentingViewController.present(alert, animated: true)
            }
            loaded.forEach { self.enqueue(data: $0.0, fileName: $0.1, mimeType: $0.2) }
            if loaded.isEmpty {
                onCountChange?(activeCount)
            }
        }
    }

    private static func loadImageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

extension NewDiscussionImageUploader: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage,
              let data = image.jpegData(compressionQuality: 0.9) else { return }
        enqueue(data: data, fileName: Self.fileName(extension: "jpg", index: 0), mimeType: "image/jpeg")
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
