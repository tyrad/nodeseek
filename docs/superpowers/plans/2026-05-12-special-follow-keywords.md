# Special Follow Keywords Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add local special-follow keyword settings and highlight matching homepage post titles/authors.

**Architecture:** Keep persistence and matching independent from UIKit. Settings owns keyword management UI, while post list cells consume immutable keyword rules from the shared store.

**Tech Stack:** Swift, UIKit, AsyncDisplayKit, Swift Testing, UserDefaults, JSONEncoder/JSONDecoder.

---

### Task 1: Keyword Model, Store, And Highlighter

**Files:**
- Create: `nodeseek/Features/Settings/SpecialFollowKeywords.swift`
- Create: `nodeseekTests/Features/SpecialFollowKeywordsTests.swift`

- [x] Write failing tests for persistence, JSON validation, import overwrite, and attributed-text highlighting.
- [x] Implement `SpecialFollowKeyword`, `SpecialFollowKeywordStore`, `SpecialFollowKeywordHighlighter`, and `UIColor` hex helpers.
- [x] Run `xcodebuild test` for `SpecialFollowKeywordsTests`.

### Task 2: Settings Entry And Keyword List UI

**Files:**
- Modify: `nodeseek/Features/Settings/SettingsViewController.swift`
- Create: `nodeseek/Features/Settings/SpecialFollowKeywordsViewController.swift`
- Modify: `nodeseekTests/Features/SettingsViewControllerTests.swift`

- [x] Write failing tests that settings shows `特别关注` with the keyword count and pushes the list controller.
- [x] Add a settings section between NodeImage and debug.
- [x] Implement list add/edit/delete with default red and `UIColorPickerViewController`.
- [x] Add import/export actions using document picker/share sheet and store validation.

### Task 3: Post List Highlight Integration

**Files:**
- Modify: `nodeseek/Features/PostList/Nodes/PostSummaryCellNode.swift`
- Modify: `nodeseek/Features/PostList/PostTextureList/PostTextureListView.swift`
- Modify: `nodeseekTests/Features/PostSummaryCellNodeTests.swift`

- [x] Write failing tests for title and author-name color changes when rules match.
- [x] Update title and metadata attributed text builders to use highlighter rules.
- [x] Reload visible/content rows when keyword settings change.
- [x] Run focused tests and a simulator build.
