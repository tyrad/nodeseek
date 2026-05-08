//
//  PostDetailViewController+Reply.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import UIKit
import ImageIO
import PhotosUI
import UniformTypeIdentifiers
import WebKit
import Security

extension PostDetailViewController {
    @objc
    func replyButtonTapped() {
        ensureNodeSeekLoggedIn { [weak self] in
            self?.presentReplyEditor(mode: .plain)
        }
    }

    @objc
    func dismissKeyboardFromBackgroundTap(_ recognizer: UITapGestureRecognizer) {
        view.endEditing(true)
    }

    @objc
    func keyboardWillChangeFrame(_ notification: Notification) {
        animateKeyboardTransition(with: notification)
    }

    @objc
    func keyboardWillHide(_ notification: Notification) {
        animateKeyboardTransition(with: notification)
    }

    func animateKeyboardTransition(with notification: Notification) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    func handleReply(to comment: Comment) {
        ensureNodeSeekLoggedIn { [weak self] in
            self?.presentReplyEditor(action: "回复", for: comment)
        }
    }

    func handleReply(toPostHeader header: PostDetailHeaderContent) {
        let comment = Comment(
            id: header.postID,
            anchorID: "0",
            authorName: header.authorName,
            isPoster: true,
            avatarURL: header.avatarURL,
            authorProfileURL: header.authorProfileURL,
            floorText: "#0",
            createdAtText: header.metadataText,
            contentHTML: header.contentHTML
        )
        ensureNodeSeekLoggedIn { [weak self] in
            self?.presentReplyEditor(mode: .reply(comment))
        }
    }

    func handleQuote(_ comment: Comment) {
        ensureNodeSeekLoggedIn { [weak self] in
            self?.presentReplyEditor(action: "引用", for: comment)
        }
    }

    func updateReplyButtonVisibility() {
        replyButton.isHidden = showsReplyEntry == false || displayMode != .content || replyEditorContainer.isHidden == false
    }

    func presentReplyEditor(mode: CommentComposerMode) {
        guard showsReplyEntry, displayMode == .content else { return }
        replyComposerMode = mode
        updateReplyContext(for: mode)
        replyEditorBackdrop.isHidden = false
        replyEditorContainer.isHidden = false
        view.bringSubviewToFront(replyEditorBackdrop)
        view.bringSubviewToFront(replyEditorContainer)
        replyEditorContainer.setNeedsLayout()
        replyEditorContainer.layoutIfNeeded()
        updateReplyButtonVisibility()
        if view.window != nil {
            replyTextView.becomeFirstResponder()
        }
    }

    func presentReplyEditor(action: String, for comment: Comment) {
        presentReplyEditor(mode: action == "引用" ? .quote(comment) : .reply(comment))
    }

    func ensureNodeSeekLoggedIn(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let account = await accountRefresher.refreshIfNeeded(force: false, maxAge: 60)
            if account?.isLoggedIn == true {
                action()
                return
            }

            showToast(message: "请先登录 NodeSeek")
            presentNodeSeekLogin {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let account = await accountRefresher.refreshIfNeeded(force: true, maxAge: 0)
                    if account?.isLoggedIn == true {
                        action()
                    } else {
                        showError(message: "请先登录 NodeSeek 后再继续。")
                    }
                }
            }
        }
    }

    func presentNodeSeekLogin(onClose: @escaping @MainActor () -> Void) {
        let loginViewController = LoginWebViewController(onClose: onClose)
        if let navigationController {
            navigationController.pushViewController(loginViewController, animated: true)
            return
        }
        present(UINavigationController(rootViewController: loginViewController), animated: true)
    }

    nonisolated static func trimmedNonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func updateReplyContext(for mode: CommentComposerMode) {
        let contextText: String?
        switch mode {
        case .plain:
            contextText = nil
        case .reply(let comment):
            contextText = replyContextText(action: "回复", comment: comment)
        case .quote(let comment):
            contextText = replyContextText(action: "引用", comment: comment)
        }

        if let contextText, contextText.isEmpty == false {
            replyContextLabel.text = contextText
            replyContextBar.isHidden = false
            replyContextBarHeightConstraint?.constant = 32
        } else {
            replyContextLabel.text = nil
            replyContextBar.isHidden = true
            replyContextBarHeightConstraint?.constant = 0
        }
    }

    func replyContextText(action: String, comment: Comment) -> String {
        let authorName = AuthorDisplayPolicy.displayName(from: comment.authorName) ?? comment.authorName
        let contextParts = [
            action,
            Self.trimmedNonEmpty(authorName),
            comment.floorText.flatMap(Self.trimmedNonEmpty)
        ]
            .compactMap(\.self)
        return contextParts.joined(separator: " ")
    }

    @objc
    func dismissReplyEditor() {
        replyTextView.resignFirstResponder()
        setStickerPickerVisible(false, animated: false)
        replyEditorBackdrop.isHidden = true
        replyEditorContainer.isHidden = true
        replyComposerMode = .plain
        updateReplyContext(for: .plain)
        updateReplyButtonVisibility()
    }

    @objc
    func clearReplyContext() {
        replyComposerMode = .plain
        updateReplyContext(for: .plain)
    }

    @objc
    func sendReplyTapped() {
        guard let content = Self.trimmedNonEmpty(replyTextView.text) else {
            showError(message: "回复内容不能为空。")
            return
        }

        ensureNodeSeekLoggedIn { [weak self] in
            guard let self else { return }
            presenter.didTapSendReply(content: resolvedReplyContent(from: content))
        }
    }

    func resolvedReplyContent(from text: String) -> String {
        CommentComposerContentBuilder.content(
            text: text,
            mode: replyComposerMode,
            postURL: resolvedDetailURL() ?? baseURL
        )
    }

    @objc
    func toggleStickerPicker() {
        let shouldShow = replyStickerPickerView.isHidden
        if shouldShow {
            replyTextView.resignFirstResponder()
            Task { [weak self] in
                guard let self else { return }
                await stickerCookieBridge.syncWebViewCookiesToURLSession()
                setStickerPickerVisible(true, animated: true)
            }
            return
        }
        setStickerPickerVisible(false, animated: true)
    }

    func insertStickerToken(_ token: String) {
        let result = StickerTokenInsertion.inserting(
            token: token,
            into: replyTextView.text ?? "",
            selectedRange: replyTextView.selectedRange
        )
        replyTextView.text = result.text
        replyTextView.selectedRange = result.selectedRange
    }

    func setStickerPickerVisible(_ isVisible: Bool, animated: Bool) {
        replyStickerPickerView.isHidden = false
        replyStickerPickerHeightConstraint?.constant = isVisible ? 260 : 0
        replyStickerButton.tintColor = isVisible ? .systemBlue : nil

        let animations = {
            self.replyStickerPickerView.alpha = isVisible ? 1 : 0
            self.view.layoutIfNeeded()
        }

        let completion: (Bool) -> Void = { _ in
            self.replyStickerPickerView.isHidden = isVisible == false
        }

        if animated {
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState],
                animations: animations,
                completion: completion
            )
        } else {
            animations()
            completion(true)
        }
    }

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
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
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

protocol NodeImageAPIKeyStoring: AnyObject {
    func apiKey() -> String?
    func save(apiKey: String)
    func clear()
}

enum NodeImageAPIKeyNormalizer {
    static func normalized(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }

        if let headerLine = trimmed
            .components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { $0.lowercased().hasPrefix("x-api-key") }),
           let separatorIndex = headerLine.firstIndex(where: { $0 == ":" || $0 == "=" }) {
            return strippedQuotes(String(headerLine[headerLine.index(after: separatorIndex)...]))
        }

        if trimmed.lowercased().hasPrefix("bearer ") {
            return strippedQuotes(String(trimmed.dropFirst("Bearer ".count)))
        }

        return strippedQuotes(trimmed)
    }

    private static func strippedQuotes(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return trimmed }
        if (trimmed.first == "\"" && trimmed.last == "\"")
            || (trimmed.first == "'" && trimmed.last == "'") {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }
}

final class KeychainNodeImageAPIKeyStore: NodeImageAPIKeyStoring {
    private let service = "com.nodeseek.nodeimage"
    private let account = "api-key"

    func apiKey() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            return nil
        }
        let normalized = NodeImageAPIKeyNormalizer.normalized(apiKey)
        return normalized.isEmpty ? nil : normalized
    }

    func save(apiKey: String) {
        let normalizedAPIKey = NodeImageAPIKeyNormalizer.normalized(apiKey)
        guard normalizedAPIKey.isEmpty == false else {
            clear()
            return
        }

        let data = Data(normalizedAPIKey.utf8)
        var query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            SecItemAdd(query as CFDictionary, nil)
        } else if status != errSecSuccess {
            clear()
            query[kSecValueData as String] = data
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct NodeImageUploadResult: Equatable, Sendable {
    let imageURL: URL
    let markdownText: String
}

nonisolated struct NodeImageUploadPayload: Equatable {
    let data: Data
    let fileName: String
    let mimeType: String
}

nonisolated enum NodeImageUploadImageCompressor {
    static let maxUploadByteCount = 1_000_000

    static func compressedPayload(data: Data, fileName: String, mimeType: String) -> NodeImageUploadPayload {
        guard data.count > maxUploadByteCount,
              let jpegData = compressedJPEGData(from: data) else {
            return NodeImageUploadPayload(data: data, fileName: fileName, mimeType: mimeType)
        }

        return NodeImageUploadPayload(
            data: jpegData,
            fileName: jpegFileName(from: fileName),
            mimeType: "image/jpeg"
        )
    }

    private static func compressedJPEGData(from data: Data) -> Data? {
        var bestData: Data?
        for maxDimension in [2048, 1600, 1280, 1024, 800, 640, 512, 384, 256, 128] {
            guard let workingImage = downsampledImage(from: data, maxPixelSize: maxDimension) else { continue }
            for quality in stride(from: CGFloat(0.82), through: CGFloat(0.30), by: CGFloat(-0.08)) {
                guard let data = workingImage.jpegData(compressionQuality: quality) else { continue }
                if bestData == nil || data.count < bestData!.count {
                    bestData = data
                }
                if data.count <= maxUploadByteCount {
                    return data
                }
            }
        }
        return bestData
    }

    private static func downsampledImage(from data: Data, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    private static func jpegFileName(from fileName: String) -> String {
        let url = URL(fileURLWithPath: fileName)
        let baseName = url.deletingPathExtension().lastPathComponent
        return "\(baseName.isEmpty ? "nodeseek-image" : baseName).jpg"
    }
}

protocol NodeImageUploading: Sendable {
    func uploadImage(data: Data, fileName: String, mimeType: String, apiKey: String) async throws -> NodeImageUploadResult
}

enum NodeImageUploadError: LocalizedError {
    case invalidResponse
    case uploadFailed(String)
    case missingImageURL

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "NodeImage 返回异常。"
        case .uploadFailed(let message):
            return message
        case .missingImageURL:
            return "NodeImage 未返回图片链接。"
        }
    }
}

struct NodeImageUploadClient: NodeImageUploading {
    private let endpoint: URL
    private let session: URLSession

    init(
        endpoint: URL = URL(string: "https://api.nodeimage.com/api/upload")!,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.session = session
    }

    func uploadImage(data: Data, fileName: String, mimeType: String, apiKey: String) async throws -> NodeImageUploadResult {
        let boundary = "NodeSeekBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            data: data,
            name: "image",
            fileName: fileName,
            mimeType: mimeType,
            boundary: boundary
        )

        let (responseData, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NodeImageUploadError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = NodeImageUploadResponseParser.errorMessage(from: responseData)
                ?? "NodeImage 上传失败，状态码 \(httpResponse.statusCode)。"
            throw NodeImageUploadError.uploadFailed(message)
        }

        guard let result = NodeImageUploadResponseParser.uploadResult(from: responseData) else {
            throw NodeImageUploadError.missingImageURL
        }
        return result
    }

    private static func multipartBody(
        data: Data,
        name: String,
        fileName: String,
        mimeType: String,
        boundary: String
    ) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n")
        return body
    }
}

enum NodeImageUploadResponseParser {
    static func uploadResult(from data: Data) -> NodeImageUploadResult? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let markdown = firstStringValue(in: object, matching: ["markdown", "md"]),
           let url = firstURL(in: object) {
            return NodeImageUploadResult(imageURL: url, markdownText: markdown)
        }
        guard let url = firstURL(in: object) else { return nil }
        return NodeImageUploadResult(imageURL: url, markdownText: "![](\(url.absoluteString))")
    }

    static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return firstStringValue(in: object, matching: ["message", "error", "msg"])
    }

    private static func firstURL(in object: Any) -> URL? {
        if let string = object as? String,
           let url = URL(string: string),
           ["http", "https"].contains(url.scheme?.lowercased()) {
            return url
        }

        if let array = object as? [Any] {
            for value in array {
                if let url = firstURL(in: value) {
                    return url
                }
            }
        }

        if let dictionary = object as? [String: Any] {
            let preferredKeys = ["url", "direct", "direct_url", "image_url", "src", "link"]
            for key in preferredKeys {
                if let value = dictionary[key], let url = firstURL(in: value) {
                    return url
                }
            }
            for value in dictionary.values {
                if let url = firstURL(in: value) {
                    return url
                }
            }
        }

        return nil
    }

    private static func firstStringValue(in object: Any, matching keys: Set<String>) -> String? {
        if let dictionary = object as? [String: Any] {
            for key in keys {
                if let value = dictionary[key] as? String, value.isEmpty == false {
                    return value
                }
            }
            for value in dictionary.values {
                if let nested = firstStringValue(in: value, matching: keys) {
                    return nested
                }
            }
        }

        if let array = object as? [Any] {
            for value in array {
                if let nested = firstStringValue(in: value, matching: keys) {
                    return nested
                }
            }
        }

        return nil
    }
}

enum NodeImageAuthorizationMessage {
    static func apiKey(from body: Any) -> String? {
        guard let rawAPIKey = firstAPIKey(in: body) else { return nil }
        let normalized = NodeImageAPIKeyNormalizer.normalized(rawAPIKey)
        return normalized.isEmpty ? nil : normalized
    }

    private static func firstAPIKey(in value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            let preferredKeys = ["api_key", "apiKey", "apikey", "x-api-key", "X-API-Key"]
            for key in preferredKeys {
                if let rawAPIKey = dictionary[key] as? String {
                    return rawAPIKey
                }
            }

            for (key, nestedValue) in dictionary {
                let normalizedKey = key
                    .lowercased()
                    .replacingOccurrences(of: "-", with: "_")
                if normalizedKey.contains("api_key"),
                   let rawAPIKey = nestedValue as? String {
                    return rawAPIKey
                }
            }

            for nestedValue in dictionary.values {
                if let rawAPIKey = firstAPIKey(in: nestedValue) {
                    return rawAPIKey
                }
            }
            return nil
        }

        if let array = value as? [Any] {
            for nestedValue in array {
                if let rawAPIKey = firstAPIKey(in: nestedValue) {
                    return rawAPIKey
                }
            }
            return nil
        }

        if let string = value as? String {
            if let data = string.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data),
               let rawAPIKey = firstAPIKey(in: object) {
                return rawAPIKey
            }

            let lowercased = string.lowercased()
            if lowercased.hasPrefix("bearer ") || lowercased.contains("x-api-key") {
                return string
            }
        }

        return nil
    }
}

private enum NodeImageAuthorizationScripts {
    static let messageHandlerName = "nodeImageAuthorization"

    static let bridge = """
    (() => {
      if (window.__nodeSeekNodeImageBridgeInstalled) return;
      window.__nodeSeekNodeImageBridgeInstalled = true;
      const post = (payload) => {
        try {
          window.webkit?.messageHandlers?.nodeImageAuthorization?.postMessage(payload);
        } catch (_) {}
      };
      const requestAPIKey = (reason) => post({ type: 'request-api-key', reason });
      window.addEventListener('message', (event) => {
        post({ type: 'auth-message', origin: event.origin, data: event.data });
        setTimeout(() => requestAPIKey('message'), 250);
        setTimeout(() => requestAPIKey('message-delayed'), 1200);
      });
      window.addEventListener('focus', () => requestAPIKey('focus'));
      document.addEventListener('visibilitychange', () => {
        if (!document.hidden) requestAPIKey('visible');
      });
    })();
    """

    static let startAuthorization = """
    (() => {
      const startButton = document.getElementById('startAuthBtn');
      if (startButton) {
        startButton.click();
        return 'clicked-startAuthBtn';
      }
      window.location.href = 'https://www.nodeseek.com/connect?target=NodeImage';
      return 'fallback-location';
    })();
    """

    static let extractAPIKey = """
    (() => {
      const post = (payload) => {
        try {
          window.webkit?.messageHandlers?.nodeImageAuthorization?.postMessage(payload);
        } catch (_) {}
      };
      const emitAPIKey = (apiKey) => {
        if (apiKey) post({ type: 'api-key', api_key: apiKey });
        return apiKey || '';
      };
      const showAPI = () => {
        const apiButton = document.getElementById('apiBtn');
        if (apiButton) apiButton.click();
      };
      const readInput = () => {
        const input = document.getElementById('apiKeyInput');
        return input && input.value ? input.value : '';
      };
      const readCurrentPage = () => {
        showAPI();
        return emitAPIKey(readInput());
      };

      const immediate = readCurrentPage();
      if (immediate) return immediate;

      let attempts = 0;
      const interval = setInterval(() => {
        attempts += 1;
        const apiKey = readCurrentPage();
        if (apiKey || attempts >= 20) clearInterval(interval);
      }, 250);

      fetch('/api/user/status', { credentials: 'include' })
        .then((response) => response.ok ? response.json() : null)
        .then((data) => post({ type: 'user-status', data }))
        .catch(() => {});

      return '';
    })();
    """
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

final class NodeImageAuthViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private let onAPIKey: @MainActor (String) -> Void
    private let webView = NoBounceWebView(frame: .zero, configuration: WKWebViewConfiguration())
    private var popupWebView: WKWebView?
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private var didComplete = false
    private var didRequestNodeSeekAuthorization = false
    private var pendingExtractionWorkItem: DispatchWorkItem?

    init(onAPIKey: @escaping @MainActor (String) -> Void) {
        self.onAPIKey = onAPIKey
        super.init(nibName: nil, bundle: nil)
        title = "授权 NodeImage"
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: NodeImageAuthorizationScripts.messageHandlerName
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "填 Key",
            primaryAction: UIAction { [weak self] _ in
                self?.presentManualAPIKeyInput()
            }
        )
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.configuration.userContentController.add(
            WeakScriptMessageHandler(delegate: self),
            name: NodeImageAuthorizationScripts.messageHandlerName
        )
        webView.configuration.userContentController.addUserScript(WKUserScript(
            source: NodeImageAuthorizationScripts.bridge,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView.customUserAgent = WebRequestFingerprint.userAgent
        webView.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        loadAuthorizationPage()
    }

    private func loadAuthorizationPage() {
        loadingIndicator.startAnimating()
        var request = URLRequest(url: URL(string: "https://www.nodeimage.com/")!)
        WebRequestFingerprint.applyHTMLHeaders(to: &request)
        webView.load(request)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingIndicator.stopAnimating()
        if webView === self.webView {
            startNodeImageAuthorizationIfNeeded()
            extractAPIKeyIfPossible()
        } else if webView === popupWebView,
                  webView.url?.host?.lowercased().contains("nodeimage.com") == true {
            popupWebView?.removeFromSuperview()
            popupWebView = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.extractAPIKeyIfPossible()
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingIndicator.stopAnimating()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        loadingIndicator.stopAnimating()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }

        let popup = NoBounceWebView(frame: .zero, configuration: configuration)
        popup.customUserAgent = WebRequestFingerprint.userAgent
        popup.navigationDelegate = self
        popup.uiDelegate = self
        popup.translatesAutoresizingMaskIntoConstraints = false
        popupWebView?.removeFromSuperview()
        popupWebView = popup
        view.addSubview(popup)
        NSLayoutConstraint.activate([
            popup.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            popup.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            popup.topAnchor.constraint(equalTo: view.topAnchor),
            popup.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard webView === popupWebView else { return }
        popupWebView?.removeFromSuperview()
        popupWebView = nil
        extractAPIKeyIfPossible()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == NodeImageAuthorizationScripts.messageHandlerName else { return }
        if let apiKey = NodeImageAuthorizationMessage.apiKey(from: message.body) {
            completeAuthorization(with: apiKey)
            return
        }
        scheduleAPIKeyExtraction(after: 0.25)
    }

    private func startNodeImageAuthorizationIfNeeded() {
        guard didRequestNodeSeekAuthorization == false else { return }
        guard webView.url?.host?.lowercased().contains("nodeimage.com") == true else { return }
        didRequestNodeSeekAuthorization = true
        webView.evaluateJavaScript(NodeImageAuthorizationScripts.startAuthorization)
        scheduleAPIKeyExtraction(after: 0.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.extractAPIKeyIfPossible()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.extractAPIKeyIfPossible()
        }
    }

    private func scheduleAPIKeyExtraction(after delay: TimeInterval) {
        guard didComplete == false else { return }
        pendingExtractionWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.extractAPIKeyIfPossible()
        }
        pendingExtractionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func extractAPIKeyIfPossible() {
        guard didComplete == false else { return }
        guard webView.url?.host?.lowercased().contains("nodeimage.com") == true else { return }
        webView.evaluateJavaScript(NodeImageAuthorizationScripts.extractAPIKey) { [weak self] result, _ in
            Task { @MainActor in
                self?.completeAuthorization(with: (result as? String) ?? "")
            }
        }
    }

    private func completeAuthorization(
        with rawAPIKey: String,
        afterDismissing presentedViewController: UIViewController? = nil
    ) {
        guard didComplete == false else { return }
        let apiKey = NodeImageAPIKeyNormalizer.normalized(rawAPIKey)
        guard apiKey.isEmpty == false else { return }
        didComplete = true

        let notifyAPIKey: @MainActor () -> Void = { [weak self] in
            self?.onAPIKey(apiKey)
        }

        guard let presentedViewController else {
            notifyAPIKey()
            return
        }

        if presentedViewController.isBeingDismissed,
           let transitionCoordinator = presentedViewController.transitionCoordinator {
            transitionCoordinator.animate(alongsideTransition: nil) { _ in
                Task { @MainActor in
                    notifyAPIKey()
                }
            }
            return
        }

        guard presentedViewController.presentingViewController != nil else {
            DispatchQueue.main.async {
                Task { @MainActor in
                    notifyAPIKey()
                }
            }
            return
        }

        presentedViewController.dismiss(animated: true) {
            Task { @MainActor in
                notifyAPIKey()
            }
        }
    }

    private func presentManualAPIKeyInput() {
        let alert = UIAlertController(
            title: "填写 NodeImage API Key",
            message: "如果自动授权没有完成，可在 NodeImage 的 API 页面复制后粘贴。",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "X-API-Key"
            textField.textContentType = .password
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            let alertController = alert
            let rawAPIKey = alertController?.textFields?.first?.text ?? ""
            Task { @MainActor in
                self?.completeAuthorization(
                    with: rawAPIKey,
                    afterDismissing: alertController
                )
            }
        })
        present(alert, animated: true)
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
