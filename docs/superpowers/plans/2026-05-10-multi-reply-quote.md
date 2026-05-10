# Multi Reply Quote Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow one composer session to target multiple replies or multiple quotes.

**Architecture:** Extend `CommentComposerMode` to hold comment arrays and keep merging logic in `PostDetailViewController+Reply`. Keep final content generation inside `CommentComposerContentBuilder`.

**Tech Stack:** Swift 5.9, Swift Testing, UIKit, existing NodeSeek parser/domain models.

---

### Task 1: Core Composer Content

**Files:**
- Modify: `nodeseekTests/SharedCore/CommentComposerContentBuilderTests.swift`
- Modify: `nodeseek/SharedCore/Composer/CommentComposerContentBuilder.swift`

- [ ] Add a failing test for `.reply([commentA, commentB])` that expects two mention links before user text.
- [ ] Add a failing test for `.quote([commentA, commentB])` that expects two quote blocks before user text.
- [ ] Run `swift test --filter CommentComposerContentBuilderTests` and confirm the new tests fail because the array cases do not exist.
- [ ] Change `CommentComposerMode.reply` and `.quote` to store `[Comment]`.
- [ ] Update the content builder to skip empty arrays, join reply prefixes with spaces, and join quote blocks with blank lines.
- [ ] Run `swift test --filter CommentComposerContentBuilderTests` and confirm the core composer tests pass.

### Task 2: Detail Reply State

**Files:**
- Modify: `nodeseekTests/Features/PostDetailViewControllerTests.swift`
- Modify: `nodeseek/Features/PostDetail/PostDetailViewController+Reply.swift`
- Modify: `nodeseek/Features/PostDetail/PostDetailViewController+ViewProtocol.swift`

- [ ] Add a failing UI-level test that opens reply mode, taps reply for a second comment, expects a multi-target context label, sends, and verifies both mention prefixes.
- [ ] Add a failing UI-level test that opens quote mode, taps quote for a second comment, sends, and verifies both quote blocks.
- [ ] Run a targeted Xcode test for `PostDetailViewControllerTests` and confirm the new tests fail before implementation.
- [ ] Add mode merge helpers in `PostDetailViewController+Reply`: same mode appends unique comment IDs, different mode replaces.
- [ ] Update context label generation to summarize multiple targets in one line.
- [ ] Update testing helper code in `PostDetailViewController+ViewProtocol.swift` to construct array modes.
- [ ] Run the targeted Xcode test again and confirm the new UI behavior passes.

### Task 3: Verification

**Files:**
- Read: `git diff`

- [ ] Run `swift test --filter CommentComposerContentBuilderTests`.
- [ ] Run targeted Xcode tests for `PostDetailViewControllerTests`.
- [ ] Review `git diff --check`.
- [ ] Review changed files for accidental broad refactors or hard-coded UI colors.
