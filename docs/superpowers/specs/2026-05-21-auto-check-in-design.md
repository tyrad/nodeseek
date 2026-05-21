# NodeSeek Auto Check-In Design

Date: 2026-05-21
Status: Draft for review
Scope: optional automatic NodeSeek daily check-in for the iOS app

## Goal

Add an opt-in automatic check-in feature. When enabled, the app checks whether the current account has already checked in for the current local day. If not, it submits the configured check-in action and shows an alert only when that automatic submission succeeds.

The feature must be packaged as an independent module with one clear public entry point. App lifecycle code and Settings code should only call the module facade; they must not contain check-in state, endpoint, parsing, WebView automation, or retry logic.

## Current Context

The app already has the required primitives:

- `NodeSeekSite.boardURL` points to `https://www.nodeseek.com/board`.
- `NodeSeekCookieSession` and `CookieBridge` synchronize cookies between WebView and native requests.
- `HiddenWebViewHTMLClient` and existing post action automations run site actions inside a real `WKWebView` context.
- Settings already uses small `UserDefaults` backed stores for feature preferences.
- `SceneDelegate` is the natural app foreground/active hook.

The existing manual check-in entry opens `/board` in `UserInfoWebViewController`. This design does not remove that path.

## Confirmed Site Behavior

Read-only browser inspection found the current `/board` page has two check-in actions:

- `鸡腿 x 5`
- `试试手气`

The page-specific script contains these calls:

- `POST /api/attendance?random=1` for `鸡腿 x 5`
- `POST /api/attendance?random=0` for `试试手气`
- `GET /api/attendance/board?page=1` for the board state

The board state script reads `memberList`, `record`, `order`, and `pager`. The submit script reads `success`, `message`, and `current`.

Plain `curl` currently receives a Cloudflare challenge. A URLSession path may work only when Cloudflare clearance cookies, NodeSeek cookies, request headers, user agent, and network environment all line up. The reliable primary path should therefore run the submit request inside a hidden WebView page context.

## Module Boundary

Create the independent module at:

```text
nodeseek/Features/AutoCheckIn/
  AutoCheckInModule.swift
  AutoCheckInCoordinator.swift
  AutoCheckInSettingsStore.swift
  AutoCheckInStateStore.swift
  AutoCheckInSettingsViewController.swift
  AutoCheckInModels.swift
```

The module exposes a small facade:

```swift
@MainActor
enum AutoCheckInModule {
    static func runIfNeeded(presentationContext: UIViewController?) async
    static func makeSettingsViewController() -> UIViewController
    static var settingsSummary: String { get }
}
```

Only this facade is called from outside the module:

- `SceneDelegate` calls `runIfNeeded(presentationContext:)`.
- `SettingsViewController` adds one row and pushes `makeSettingsViewController()`.
- Settings row text shows `settingsSummary`, but Settings must not read or mutate auto check-in storage directly.

If the WebView execution needs helper code under `AppRuntime/Web`, keep it generic and infrastructure-shaped. The product flow, user defaults keys, date checks, and alert policy stay in `Features/AutoCheckIn`.

## Configuration

`AutoCheckInSettingsStore` owns persisted user settings:

```swift
struct AutoCheckInSettings: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var mode: AutoCheckInMode
}

enum AutoCheckInMode: String, Codable, CaseIterable, Sendable {
    case fixedChickenLeg
    case random
}
```

Defaults:

- `isEnabled = false`
- `mode = .fixedChickenLeg`

Settings UI:

- A module-owned settings screen titled `自动签到`.
- A switch for enabling automatic check-in.
- A segmented control or single-choice list for `鸡腿 x 5` and `试试手气`.
- Main Settings only hosts an entry row under `功能`.

## Local State

`AutoCheckInStateStore` owns local execution state:

```swift
struct AutoCheckInState: Codable, Equatable, Sendable {
    var completedDayIdentifier: String?
    var lastSuccessfulAt: Date?
}
```

The day identifier uses the device current calendar and time zone, formatted as `yyyy-MM-dd`. This is intentionally local and lightweight. If the server later exposes a canonical check-in date, the module can migrate to that.

The app marks the current day complete when:

- automatic submit returns success, or
- board state says the user already has a record for today.

Only automatic submit success triggers an alert.

## Execution Flow

`runIfNeeded(presentationContext:)` is serial and idempotent:

1. If settings are disabled, return.
2. If today is already locally completed, return.
3. If another auto check-in task is running, join or return without starting a second task.
4. Load `NodeSeekSite.boardURL` in a hidden WebView-capable client.
5. If the page is not logged in, return silently.
6. Fetch board state in page context: `/api/attendance/board?page=1`.
7. If board state has a current user record, mark today complete and return silently.
8. Submit the configured mode:
   - `.fixedChickenLeg` -> `/api/attendance?random=1`
   - `.random` -> `/api/attendance?random=0`
9. If submit returns success, mark today complete and show an alert when a presentation context is available.
10. If submit fails, log the reason and return silently.

The coordinator should not open login UI, not navigate to `/board`, and not interrupt the user except for the success alert.

## Web Execution

Use a WebView-first action path for the submit request:

```javascript
fetch('/api/attendance?random=' + randomValue, {
  method: 'POST',
  credentials: 'include',
  headers: { 'Accept': 'application/json' }
})
```

The script result should normalize to:

```swift
struct AutoCheckInSubmitResult: Equatable, Sendable {
    let ok: Bool
    let statusCode: Int?
    let success: Bool?
    let message: String?
    let current: Int?
    let reason: String
}
```

Suggested `reason` values:

- `submitted`
- `already_checked_in`
- `not_logged_in`
- `challenge`
- `server_error`
- `network_error`
- `submit_timeout`
- `invalid_script_result`
- `javascript_exception`

Board state should normalize to:

```swift
struct AutoCheckInBoardState: Equatable, Sendable {
    let isLoggedIn: Bool
    let isCheckedIn: Bool
    let message: String?
}
```

Login detection should not depend on Vue `data-v-*` attributes. Prefer stable signals:

- `window.__config__.user` if available.
- `/signIn.html` plus `登录后签到` for guest state.
- Board API response shape and current account record for signed-in state.

## Alert Policy

Show an alert only when this automatic run submits successfully.

Title:

```text
自动签到成功
```

Message priority:

1. Server `message`, if non-empty.
2. `已完成今日签到。`

No alert for:

- automatic check-in disabled,
- local state says today is complete,
- site says already checked in,
- not logged in,
- challenge,
- network failure,
- server failure.

These cases should only be logged through `AppLog`.

## Lifecycle Integration

`SceneDelegate` should be thin:

```swift
Task { @MainActor in
    await AutoCheckInModule.runIfNeeded(presentationContext: window?.rootViewController)
}
```

Run on initial activation and foreground re-entry. The module handles all deduplication, local day checks, and in-flight coordination.

Do not put endpoint strings, settings keys, login checks, or WebView scripts in `SceneDelegate`.

## Error Handling

Errors are intentionally non-blocking:

- Network and challenge errors are logged and ignored.
- Not logged in is logged at debug/info level and ignored.
- Malformed responses are logged with status and reason.
- A failed attempt does not mark the day complete, so a later foreground can retry.

To avoid request loops after repeated failures, the coordinator keeps a 10-minute in-memory cooldown for the current process. This cooldown is not persisted.

## Testing

Unit-level coverage:

- Settings defaults are disabled and fixed chicken-leg mode.
- Settings mutations persist and publish summary changes.
- State store recognizes the same local day and next local day.
- Coordinator skips when disabled.
- Coordinator skips when local day is completed.
- Coordinator marks completion without alert when board state says already checked in.
- Coordinator submits `random=1` for `鸡腿 x 5`.
- Coordinator submits `random=0` for `试试手气`.
- Coordinator shows alert only on submit success.
- Coordinator logs/returns silently for not logged in and failed submit.

Web automation coverage:

- Script source contains `/api/attendance?random=`.
- Script uses `method: "POST"` and `credentials: "include"`.
- Response parsing handles `success`, `message`, and `current`.

Manual verification:

1. Fresh install or cleared defaults: auto check-in is off.
2. Enable auto check-in and choose `鸡腿 x 5`.
3. Relaunch or foreground the app while logged in and not yet checked in.
4. Confirm success alert appears after the automatic submit.
5. Background and foreground again on the same day; no second alert and no second submit.
6. Log out and enable auto check-in; foreground app; no alert and no login page opens.
7. Switch to `试试手气`; verify the next eligible day uses the random path.

## Non-Goals

This design does not add:

- background fetch or scheduled check-in while the app is not opened,
- automatic login,
- push notification,
- visible `/board` navigation for automatic runs,
- user-facing failure alerts,
- a generic task scheduler.

## Acceptance Criteria

- Auto check-in is off by default.
- The configured mode is persisted.
- App foreground can trigger auto check-in through one module facade call.
- Existing manual `/board` check-in route still works.
- The app does not submit twice after a same-day success or already-checked-in board state.
- Only automatic submit success shows an alert.
- Settings and app lifecycle code do not contain check-in endpoint or WebView automation logic.
