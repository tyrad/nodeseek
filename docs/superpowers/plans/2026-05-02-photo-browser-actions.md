# Photo Browser Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Disable looping in the detail photo browser and add a right-bottom action menu for sharing or saving the current image in its original format.

**Architecture:** Keep JXPhotoBrowser as the browser host and use its public `isLoopingEnabled` and `JXPhotoBrowserOverlay` APIs. Extend `DetailImageLoader` with a small original-data API, then keep UI orchestration inside `DetailPhotoBrowserPresenter` with a focused overlay view.

**Tech Stack:** UIKit, JXPhotoBrowser, PhotoKit, existing `DetailImageLoader`, Xcode app-hosted tests.

---

## File Map

- Modify: `nodeseek/AppRuntime/Images/DetailImageLoader.swift`  
  Adds `DetailOriginalImagePayload`, original-data loading, and extension inference.
- Modify: `nodeseekTests/AppRuntime/DetailImageLoaderTests.swift`  
  Adds tests for original data preservation, extension inference, and fallback failure.
- Create: `nodeseek/Features/PostDetail/DetailPhotoActionOverlay.swift`  
  Provides the right-bottom more button as a `JXPhotoBrowserOverlay`.
- Modify: `nodeseek/Features/PostDetail/DetailPhotoBrowserPresenter.swift`  
  Disables looping, installs the action overlay, presents the menu, shares temp original files, and saves original data through PhotoKit.
- Modify: `nodeseek/Resources/Info.plist`  
  Adds `NSPhotoLibraryAddUsageDescription`.

## Task 1: Original Image Payload API

**Files:**
- Modify: `nodeseekTests/AppRuntime/DetailImageLoaderTests.swift`
- Modify: `nodeseek/AppRuntime/Images/DetailImageLoader.swift`

- [ ] **Step 1: Write failing tests**

Add tests that expect a public original-data API and deterministic file-extension inference:

```swift
@Test func originalImagePayloadPreservesNetworkDataAndSuggestsExtensionFromURL() async throws {
    let url = try #require(URL(string: "https://images.example.com/photo.webp?token=abc"))
    let sourceData = try Self.makeNoisyJPEGData(width: 80, height: 60, quality: 0.85)
    let cacheDirectory = Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: cacheDirectory) }

    let protocolType = DetailImageURLProtocol.self
    protocolType.reset()
    protocolType.stub(data: sourceData, mimeType: "image/webp", for: url)
    let session = URLSession(configuration: Self.urlSessionConfiguration(protocolType: protocolType))
    let loader = DetailImageLoader(session: session, cacheDirectory: cacheDirectory)

    let payload = try await Self.loadOriginalImagePayload(loader: loader, url: url)

    #expect(payload.data == sourceData)
    #expect(payload.mimeType == "image/webp")
    #expect(payload.suggestedFileExtension == "webp")
    #expect(protocolType.totalRequestCount() == 1)
}

@Test func originalImagePayloadSuggestsExtensionFromMimeTypeWhenURLHasNoExtension() async throws {
    let url = try #require(URL(string: "https://images.example.com/download?id=1"))
    let sourceData = try Self.makeNoisyJPEGData(width: 80, height: 60, quality: 0.85)
    let cacheDirectory = Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: cacheDirectory) }

    let protocolType = DetailImageURLProtocol.self
    protocolType.reset()
    protocolType.stub(data: sourceData, mimeType: "image/png", for: url)
    let session = URLSession(configuration: Self.urlSessionConfiguration(protocolType: protocolType))
    let loader = DetailImageLoader(session: session, cacheDirectory: cacheDirectory)

    let payload = try await Self.loadOriginalImagePayload(loader: loader, url: url)

    #expect(payload.data == sourceData)
    #expect(payload.suggestedFileExtension == "png")
}

@Test func originalImagePayloadFailsForInvalidImageDataInsteadOfReturningFallback() async throws {
    let url = try #require(URL(string: "https://images.example.com/broken.gif"))
    let cacheDirectory = Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: cacheDirectory) }

    let protocolType = DetailImageURLProtocol.self
    protocolType.reset()
    protocolType.stub(data: Data("<html>not an image</html>".utf8), mimeType: "text/html", for: url)
    let session = URLSession(configuration: Self.urlSessionConfiguration(protocolType: protocolType))
    let loader = DetailImageLoader(session: session, cacheDirectory: cacheDirectory)

    await #expect(throws: DetailOriginalImageError.unavailable) {
        try await Self.loadOriginalImagePayload(loader: loader, url: url)
    }
}
```

Add this helper to the test suite:

```swift
private static func loadOriginalImagePayload(
    loader: DetailImageLoader,
    url: URL
) async throws -> DetailOriginalImagePayload {
    try await withCheckedThrowingContinuation { continuation in
        loader.loadOriginalImagePayload(for: url) { result in
            continuation.resume(with: result)
        }
    }
}
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
make xcode-test-class TEST=DetailImageLoaderTests
```

Expected: build/test fails because `DetailOriginalImagePayload`, `DetailOriginalImageError`, and `loadOriginalImagePayload(for:completion:)` do not exist.

- [ ] **Step 3: Implement minimal original-data API**

Add internal payload/error types near the top of `DetailImageLoader.swift`:

```swift
struct DetailOriginalImagePayload: Equatable {
    let data: Data
    let mimeType: String?
    let suggestedFileExtension: String
}

enum DetailOriginalImageError: Error, Equatable {
    case unavailable
}
```

Add an instance method that reuses the existing private original-data loader:

```swift
func loadOriginalImagePayload(
    for imageURL: URL,
    completion: @escaping (Result<DetailOriginalImagePayload, DetailOriginalImageError>) -> Void
) {
    fetchOriginalData(for: imageURL) { payload in
        guard payload.isFallback == false else {
            completion(.failure(.unavailable))
            return
        }

        completion(.success(DetailOriginalImagePayload(
            data: payload.data,
            mimeType: payload.mimeType,
            suggestedFileExtension: Self.suggestedFileExtension(for: imageURL, mimeType: payload.mimeType)
        )))
    }
}
```

Add extension inference:

```swift
static func suggestedFileExtension(for imageURL: URL, mimeType: String?) -> String {
    let extensionFromURL = imageURL.pathExtension
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if extensionFromURL.isEmpty == false {
        return extensionFromURL == "jpeg" ? "jpg" : extensionFromURL
    }

    switch mimeType?.lowercased().split(separator: ";", maxSplits: 1).first.map(String.init) {
    case "image/jpeg", "image/jpg":
        return "jpg"
    case "image/png":
        return "png"
    case "image/gif":
        return "gif"
    case "image/webp":
        return "webp"
    case "image/heic":
        return "heic"
    case "image/heif":
        return "heif"
    case "image/tiff":
        return "tiff"
    case "image/bmp":
        return "bmp"
    default:
        return "jpg"
    }
}
```

- [ ] **Step 4: Run tests and verify pass**

Run:

```bash
make xcode-test-class TEST=DetailImageLoaderTests
```

Expected: `DetailImageLoaderTests` passes.

## Task 2: Browser Action Overlay

**Files:**
- Create: `nodeseek/Features/PostDetail/DetailPhotoActionOverlay.swift`

- [ ] **Step 1: Add focused overlay view**

Create `DetailPhotoActionOverlay.swift`:

```swift
import JXPhotoBrowser
import UIKit

final class DetailPhotoActionOverlay: UIView, JXPhotoBrowserOverlay {
    var onTap: ((JXPhotoBrowserViewController, UIView) -> Void)?

    private weak var browser: JXPhotoBrowserViewController?

    private lazy var button: UIButton = {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "ellipsis")
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.48)
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        button.configuration = configuration
        button.accessibilityLabel = "图片操作"
        button.accessibilityIdentifier = "detail-photo-action-button"
        button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    func setup(with browser: JXPhotoBrowserViewController) {
        self.browser = browser
        guard let container = superview else { return }
        NSLayoutConstraint.activate([
            trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor, constant: -22)
        ])
    }

    func reloadData(numberOfItems: Int, pageIndex: Int) {
        isHidden = numberOfItems == 0
    }

    func didChangedPageIndex(_ index: Int) {}

    private func setupUI() {
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.widthAnchor.constraint(equalToConstant: 48),
            button.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    @objc private func buttonTapped() {
        guard let browser else { return }
        onTap?(browser, button)
    }
}
```

- [ ] **Step 2: Build after adding overlay**

Run:

```bash
make xcode-build-tests
```

Expected: build succeeds.

## Task 3: Presenter Actions and Non-Looping Browser

**Files:**
- Modify: `nodeseek/Features/PostDetail/DetailPhotoBrowserPresenter.swift`
- Modify: `nodeseek/Resources/Info.plist`

- [ ] **Step 1: Wire non-looping and action overlay**

Modify presenter imports and browser setup:

```swift
import JXPhotoBrowser
import Photos
import UIKit
```

Set:

```swift
browser.isLoopingEnabled = false
let actionOverlay = DetailPhotoActionOverlay()
actionOverlay.onTap = { [weak self] browser, sourceView in
    self?.presentActionMenu(from: browser, sourceView: sourceView)
}
browser.addOverlay(actionOverlay)
```

- [ ] **Step 2: Add action menu, sharing, saving, and messages**

Add presenter helpers:

```swift
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
    DetailImageLoader.shared.loadOriginalImagePayload(for: imageURL) { [weak browser, weak sourceView] result in
        DispatchQueue.main.async {
            guard let browser, let sourceView else { return }
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
    DetailImageLoader.shared.loadOriginalImagePayload(for: imageURL) { [weak browser] result in
        DispatchQueue.main.async {
            guard let browser else { return }
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
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak browser] status in
        guard let browser else { return }
        guard status == .authorized || status == .limited else {
            DispatchQueue.main.async {
                self.showMessage("保存失败", in: browser)
            }
            return
        }

        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: payload.data, options: nil)
        } completionHandler: { [weak browser] success, _ in
            DispatchQueue.main.async {
                guard let browser else { return }
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
```

- [ ] **Step 3: Add photo-library add usage description**

Add to `Info.plist`:

```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>保存图片到系统相册</string>
```

- [ ] **Step 4: Build**

Run:

```bash
make xcode-build-tests
```

Expected: build succeeds.

## Task 4: Final Verification

**Files:**
- No new production files beyond Tasks 1-3.

- [ ] **Step 1: Run targeted AppRuntime test**

Run:

```bash
make xcode-test-class TEST=DetailImageLoaderTests
```

Expected: `DetailImageLoaderTests` passes.

- [ ] **Step 2: Run build-for-testing**

Run:

```bash
make xcode-build-tests
```

Expected: build succeeds.

- [ ] **Step 3: Inspect git diff**

Run:

```bash
git diff --stat
git diff --check
```

Expected: changed files match the file map; `git diff --check` reports no whitespace errors.
