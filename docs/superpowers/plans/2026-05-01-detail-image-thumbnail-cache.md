# Detail Image Thumbnail Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve post detail image performance by rendering normal content images from cached thumbnails while keeping original images available for photo browsing.

**Architecture:** Keep UI layout unchanged. Add a focused detail image optimization configuration and make `DetailImageLoader` own original/thumbnail disk caches, cache cleanup, thumbnail byte limits, and optional diagnostics. Exclude sticker/icon images, video resources, avatars, and WebView content.

**Tech Stack:** Swift, UIKit, ImageIO, URLSession, Swift Testing/XCTest.

---

### Task 1: Configuration And Cache Unit Tests

**Files:**
- Create: `nodeseek/AppRuntime/Images/DetailImageConfig.swift`
- Modify: `nodeseek/AppRuntime/Images/DetailImageLoader.swift`
- Test: `nodeseekTests/AppRuntime/DetailImageLoaderTests.swift`

- [ ] Write failing tests for default optimization config, thumbnail byte cap, original cache hit for preview, and cache clearing.
- [ ] Run the new test target and confirm failures are caused by missing APIs.
- [ ] Add the minimal config and injectable cache/session hooks needed by tests.
- [ ] Re-run tests and keep them green.

### Task 2: Thumbnail Generation And Diagnostics

**Files:**
- Modify: `nodeseek/AppRuntime/Images/DetailImageLoader.swift`

- [ ] Generate one universal thumbnail per normal image URL.
- [ ] Keep thumbnail longest side under `maxPixelSide`; do not upscale small images.
- [ ] Compress JPEG thumbnails under `maxThumbnailBytes` by lowering quality to a configured floor.
- [ ] Log original bytes/size, thumbnail bytes/size, cache source, and quality only when config logging is enabled.

### Task 3: Detail UI Integration

**Files:**
- Modify: `nodeseek/Features/PostDetail/DetailInlineImageView.swift`
- Modify: `nodeseek/Features/PostDetail/Nodes/DetailImageBlockNode.swift`
- Modify: `nodeseek/Features/PostDetail/Nodes/DetailTableNode.swift`
- Modify: `nodeseek/Features/PostDetail/DetailPhotoBrowserPresenter.swift`

- [ ] Route normal detail images through thumbnail loading when optimization is enabled.
- [ ] Keep disabled mode on the existing inline image path.
- [ ] Keep sticker/icon/video paths unchanged.
- [ ] Make photo browser load originals from the detail original cache before network.

### Task 4: Verification

**Files:**
- Test: `nodeseekTests/AppRuntime/DetailImageLoaderTests.swift`
- Test: existing post detail and layout tests

- [ ] Run the focused image loader tests.
- [ ] Run post detail rendering/layout tests touched by this change.
- [ ] Report any skipped verification or remaining risk.
