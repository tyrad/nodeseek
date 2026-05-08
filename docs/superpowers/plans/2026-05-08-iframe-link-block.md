# Iframe Link Block Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render iframe embeds in post and comment HTML as full-width tappable link blocks.

**Architecture:** Add a `RenderedIFrameLinkBlock` model and `.iframeLink` content block. Extend the DTCoreText renderer to split iframe tags out of HTML fragments, preserving raw `src` while resolving an openable URL, then add an AsyncDisplayKit node that displays the domain and source and forwards taps to the existing link handler.

**Tech Stack:** Swift, Kanna, AsyncDisplayKit, Swift Testing, SFSafariViewController via existing post detail link flow.

---

### Task 1: Renderer Block Model And Parser

**Files:**
- Modify: `nodeseek/AppRuntime/Rendering/RenderedContentBlock.swift`
- Modify: `nodeseek/AppRuntime/Rendering/DTCoreTextHTMLContentRenderer.swift`
- Modify: `nodeseek/AppRuntime/Rendering/DTCoreTextHTMLContentRenderer+ContentBlocks.swift`
- Test: `nodeseekTests/AppRuntime/DTCoreTextHTMLContentRendererTests.swift`

- [ ] **Step 1: Write failing renderer tests**

Add tests that assert iframe tags produce `.iframeLink` blocks in order and preserve protocol-relative raw sources while resolving an `https` open URL.

- [ ] **Step 2: Run renderer tests and verify failure**

Run: `swift test --filter DTCoreTextHTMLContentRendererTests`

Expected: compile failure or test failure because `.iframeLink` and `RenderedIFrameLinkBlock` do not exist yet.

- [ ] **Step 3: Implement renderer support**

Add `RenderedIFrameLinkBlock`, add `.iframeLink`, add iframe regexes, split iframe tags from fragments, parse `src`, compute `displayDomain`, and compute `openURL`.

- [ ] **Step 4: Run renderer tests and verify pass**

Run: `swift test --filter DTCoreTextHTMLContentRendererTests`

Expected: pass.

### Task 2: Detail UI Node

**Files:**
- Modify: `nodeseek/Features/PostDetail/Nodes/DetailTableNode.swift`
- Test: `nodeseekTests/Features/PostDetailViewControllerTests.swift`

- [ ] **Step 1: Write failing node factory test**

Add a test that a `.iframeLink` block creates a node that measures to the full constrained width.

- [ ] **Step 2: Run feature test and verify failure**

Run: `swift test --filter PostDetailViewControllerTests`

Expected: compile failure or test failure because iframe node support does not exist.

- [ ] **Step 3: Implement full-width iframe link node**

Add a `DetailIFrameLinkNode`/view in the existing detail node file, render domain and raw source, add tap handling, and wire `.iframeLink` in `DetailContentBlockNodeFactory`.

- [ ] **Step 4: Run feature tests and verify pass**

Run: `swift test --filter PostDetailViewControllerTests`

Expected: pass.

### Task 3: Final Verification

**Files:**
- No additional files.

- [ ] **Step 1: Run focused test suite**

Run: `swift test --filter DTCoreTextHTMLContentRendererTests && swift test --filter PostDetailViewControllerTests`

Expected: pass.

- [ ] **Step 2: Review git diff**

Run: `git diff --check && git status --short`

Expected: no whitespace errors; only planned files changed.
