# Unified Image Loader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move detail image loading to one internal `ImageDataLoader`, while keeping Kingfisher for avatar and existing GIF/sticker animated paths.

**Architecture:** `ImageDataLoader` owns URL resolution, request creation, raw data caching, and in-flight request coalescing for detail images. `ImageRenderer` owns bitmap/SVG rendering for detail processing. `AvatarImageLoader` remains Kingfisher-backed because avatar loading depends on its downloader/cache path and SVG fallback behavior.

**Tech Stack:** Swift, UIKit, URLSession, ImageIO, SVGKit, existing Xcode file-system-synchronized project.

---

### Task 1: Shared Loading and Rendering Types

**Files:**
- Create: `nodeseek/AppRuntime/Images/ImageURLResolver.swift`
- Create: `nodeseek/AppRuntime/Images/Loading/ImageDataLoader.swift`
- Create: `nodeseek/AppRuntime/Images/Loading/ImageRequestFactory.swift`
- Create: `nodeseek/AppRuntime/Images/Loading/ImageDiskCache.swift`
- Create: `nodeseek/AppRuntime/Images/Rendering/ImageRenderer.swift`
- Modify: `nodeseek/AppRuntime/Images/Rendering/SVGImageRenderer.swift`

- [ ] **Step 1: Add common loading result types**

Create `ImageDataPayload`, `ImageDataSource`, and `ImageDataError` in `ImageDataLoader.swift`:

```swift
import Foundation

struct ImageDataPayload: Equatable {
    let data: Data
    let mimeType: String?
    let resolvedURL: URL
    let source: ImageDataSource
}

enum ImageDataSource: String, Equatable {
    case dataURL
    case disk
    case network
}

enum ImageDataError: Error, Equatable {
    case invalidURL
    case unavailable
}
```

- [ ] **Step 2: Add a shared request factory**

Create `ImageRequestFactory.swift`:

```swift
import Foundation

enum ImageRequestFactory {
    static let timeout: TimeInterval = 20

    static func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        return configuration
    }

    static func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = .returnCacheDataElseLoad
        WebRequestFingerprint.applyImageHeaders(to: &request)
        return request
    }
}
```

- [ ] **Step 3: Add shared disk cache**

Create `ImageDiskCache.swift` with SHA256 cache keys, `data(for:)`, `store(_:for:)`, `byteSize()`, and `clear()` methods. The cache should store raw bytes under `Images/originals` so detail original payload and detail display read the same data.

- [ ] **Step 4: Add shared data loader**

Implement `ImageDataLoader` with:
- `static let shared`
- injected `URLSession` and `ImageDiskCache`
- `loadData(for:completion:)`
- data URL support
- `ImageURLResolver` for existing URL normalization
- in-flight coalescing keyed by resolved URL
- HTML challenge detection copied from current loaders
- disk cache read before network
- disk cache write after successful network

- [ ] **Step 5: Add shared renderer**

Create `ImageRenderer.swift` with:
- `image(data:mimeType:maxPixelSize:) -> UIImage?`
- `pixelSize(data:mimeType:) -> CGSize?`
- bitmap downsampling through `CGImageSourceCreateThumbnailAtIndex`
- SVG fallback through `SVGImageRenderer`
- the current max SVG side `2048`

- [ ] **Step 6: Verify build**

Run:

```bash
xcodebuild -project nodeseek.xcodeproj -scheme nodeseek -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected: build succeeds.

---

### Task 2: Migrate DetailImageLoader to Shared Loading

**Files:**
- Modify: `nodeseek/AppRuntime/Images/Detail/DetailImageLoader.swift`
- Modify: `nodeseek/AppRuntime/Images/Detail/DetailImageRequest.swift`
- Modify: `nodeseek/Features/Settings/SettingsManagers.swift`

- [ ] **Step 1: Replace private image data path**

Remove `DetailImageLoader`'s private `URLSession`, original-data callback map, request factory, original cache paths, `decodeDataURL`, `dataLooksLikeHTML`, and `validateImageDataPayload`. Fetch original data through:

```swift
ImageDataLoader.shared.loadData(for: imageURL) { result in
    switch result {
    case .success(let payload):
        // use payload.data, payload.mimeType, payload.source
    case .failure:
        // use fallback image/payload
    }
}
```

- [ ] **Step 2: Keep detail-specific thumbnail behavior**

Keep these in `DetailImageLoader`:
- thumbnail disk cache
- bounded JPEG thumbnail generation
- report-like SVG detection
- `DetailInlineImageResult`
- `DetailOriginalImagePayload`

Use `ImageRenderer` for image decoding/downsampling instead of `DetailImageLoader` private decode helpers.

- [ ] **Step 3: Keep legacy animated GIF path outside shared loader**

Do not change `DetailInlineImageView.loadAnimatedImage`. It remains Kingfisher-based for animated GIFs.

- [ ] **Step 4: Update cache settings**

`DefaultSettingsCacheManager` should sum:
- `DetailImageLoader.shared.detailImageCacheByteSize()` for thumbnails
- `ImageDataLoader.shared.cacheByteSize()` for raw image data
- Kingfisher disk size for avatar/GIF/sticker paths

Clearing cache should clear all three.

- [ ] **Step 5: Verify detail tests/build**

Run:

```bash
swift test --filter DetailImageLoaderTests
```

If SwiftPM fails before app code because `HTMLResponse` is missing, record that blocker and run the Xcode simulator build instead.

---

### Task 3: Keep AvatarImageLoader on Kingfisher

**Files:**
- Create: `nodeseek/AppRuntime/Images/Avatar/AvatarImageProcessor.swift`
- Keep: `nodeseek/AppRuntime/Images/Avatar/AvatarImageLoader.swift`
- Keep: `nodeseek/AppRuntime/Images/Avatar/AvatarImageRequest.swift`

- [ ] **Step 1: Preserve Kingfisher avatar loading**

Keep `AvatarImageLoader` backed by Kingfisher:
- `ImageDownloader`
- `loadWithKingfisher`
- `handleKingfisherFailure`
- Kingfisher `CacheType` in `LoadResult`

- [ ] **Step 2: Move avatar rendering into a Kingfisher processor**

Do not route avatar SVG through `ImageDataLoader`. Use `AvatarImageProcessor` so Kingfisher still owns downloading, cancellation, request coalescing, and caching while the processor handles:
- SVG avatar rendering through `SVGImageRenderer`
- bitmap avatar downsampling through `DownsamplingImageProcessor`

- [ ] **Step 3: Keep cancellation semantics**

`cancel(on:)` should remove the request token and call `imageView.kf.cancelDownloadTask()`.

- [ ] **Step 4: Verify build**

Run Xcode simulator build. Expected: build succeeds and `AvatarImageLoader.swift` still imports Kingfisher.

---

### Task 4: Centralize Sticker URL Rules

**Files:**
- Create: `nodeseek/SharedCore/Media/StickerImageRules.swift`
- Modify: `nodeseek/AppRuntime/Rendering/DTCoreTextHTMLContentRenderer+MediaSources.swift`
- Modify: `nodeseek/Features/PostDetail/Views/DetailRichTextView.swift`
- Modify: `nodeseek/Features/PostDetail/Nodes/PostBodyCellNode.swift`
- Modify: `nodeseek/AppRuntime/Images/Detail/DetailImageLoader.swift`
- Test: `nodeseekTests/SharedCore/DetailImageLayoutTests.swift`

- [ ] **Step 1: Add rule helper**

Create:

```swift
import Foundation

enum StickerImageRules {
    static func isStickerURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        let path = url.path.lowercased()
        return path.contains("/static/image/sticker/") || path.contains("/sticker/")
    }
}
```

- [ ] **Step 2: Replace broad contains checks**

Replace `absoluteString.lowercased().contains("sticker")` checks with `StickerImageRules.isStickerURL(url)` except where the code is checking HTML class names.

- [ ] **Step 3: Add tests**

Add tests for:
- `/static/image/sticker/xhj/003.png` is sticker
- URL with query `?label=sticker` is not sticker
- `class="sticker"` still classifies as sticker through existing attachment path

- [ ] **Step 4: Verify**

Run:

```bash
swift test --filter DetailImageLayoutTests
```

If SwiftPM hits the existing `HTMLResponse` blocker, run Xcode simulator build and report the blocker.

---

### Task 5: Final Verification and Cleanup

**Files:**
- Review all files under `nodeseek/AppRuntime/Images/`
- Review `nodeseek/Features/Settings/SettingsManagers.swift`

- [ ] **Step 1: Search for old duplication**

Run:

```bash
rg "URLSession\\(|dataLooksLikeHTML|decodeDataURL|absoluteString\\.lowercased\\(\\)\\.contains\\(\"sticker\"\\)|import Kingfisher" nodeseek/AppRuntime/Images nodeseek/Features/PostDetail nodeseek/AppRuntime/Rendering
```

Expected:
- `URLSession` in `ImageDataLoader` and Avatar's Kingfisher downloader configuration
- `dataLooksLikeHTML` in `ImageDataLoader` and Avatar's cookie retry detection
- `decodeDataURL` only in `ImageDataLoader`
- Kingfisher in avatar plus GIF/sticker paths
- no broad sticker URL checks

- [ ] **Step 2: Run formatting/whitespace check**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 3: Run app build**

Run Xcode simulator build for scheme `nodeseek`.

Expected: build succeeds.
