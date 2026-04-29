# NodeSeek WebView Login Design

Date: 2026-04-29
Status: Draft for review
Scope: visible WebView login flow for NodeSeek iOS

## 1. Goal

Add a minimal login flow that lets users sign in through the real NodeSeek web page:

```text
https://www.nodeseek.com/signIn.html
```

The app must not parse credentials, submit the login form itself, or bypass site verification. Login happens inside a visible `WKWebView`. After the user signs in, they close the page, and the app syncs NodeSeek cookies back into native networking.

## 2. Existing Context

The project already has the pieces needed for this flow:

- `CookieBridge` can sync cookies between `WKWebsiteDataStore.default().httpCookieStore` and `HTTPCookieStorage.shared`.
- `HiddenWebViewHTMLClient` uses `WKWebsiteDataStore.default()` and already syncs cookies before and after hidden WebView HTML loading.
- Native image and HTML request paths use shared cookie storage where needed.
- `Account` exists as a VIPER module, currently showing a guest-only state.
- `PostDetailViewController` already has a local cookie-shared WebView fallback for NodeSeek pages.
- `PostDetailInteractor` reports `.loginRequired` to the view when restricted post content requires a logged-in user.

The login feature should reuse these patterns instead of adding a separate authentication system.

## 3. User Experience

### 3.1 Entry Points

Initial implementation should support:

- Account page: show the current guest state and provide a login button.
- Login-required post detail state: show a login action when restricted content is encountered.

Future entry points such as reply and check-in can reuse the same login route.

### 3.2 Login Page

The login screen is a normal app page containing a `WKWebView`.

It loads:

```text
https://www.nodeseek.com/signIn.html
```

The screen must show a clear hint:

```text
登录成功后关闭当前页面即可
```

The screen should also provide a visible close action. The user is responsible for completing login in the web page and closing the screen afterward.

### 3.3 Closing Behavior

When the user closes the login page:

1. Sync WebView cookies to `HTTPCookieStorage.shared`.
2. Dismiss or pop the login screen.
3. Notify the source page that login may have changed.
4. Refresh the source page if it has a natural refresh action.

If the user closes before logging in, the app should not show an error. The next native request will determine whether the session is authenticated.

## 4. Architecture

### 4.1 Login WebView Controller

Add a reusable visible login controller, for example `LoginWebViewController`.

Responsibilities:

- Create a `WKWebView` with `WKWebsiteDataStore.default()`.
- Set the same web user agent as existing WebView requests where practical.
- Load `https://www.nodeseek.com/signIn.html`.
- Display the fixed hint text.
- Expose a close action.
- On close, call `CookieBridge.syncWebViewCookiesToURLSession()`.
- Notify completion through a simple closure or delegate.

It should stay UI-focused. It should not parse account state or own any NodeSeek business logic.

### 4.2 Router Integration

Account routing should present or push the login controller from `AccountRouter`.

Post detail routing should be extended enough to present or push the same login controller when the view asks to log in.

The preferred navigation style is:

- Push when a navigation controller exists.
- Present a `UINavigationController` wrapper only when there is no navigation stack.

This matches the existing NodeSeek page WebView fallback behavior.

### 4.3 Refresh After Login

The login controller reports completion without claiming success.

Consumers decide what to refresh:

- Account page can reload its account state.
- Post detail can call its existing reload path.

This keeps login state validation in normal app flows and avoids adding brittle HTML checks to the login screen.

## 5. Cookie and Session Rules

The login controller must use `WKWebsiteDataStore.default()`.

Before loading the login page, it can sync `HTTPCookieStorage.shared` to WebView so any existing session is visible to the web page.

After close, it must sync WebView cookies back to `HTTPCookieStorage.shared`.

Only NodeSeek-domain cookies should be bridged, using the existing `CookieBridge` filtering.

## 6. Error Handling

WebView load failures should stop the loading indicator and show a lightweight error message with retry available through reload or closing and reopening.

Closing the page is always allowed.

Closing without a valid login is not an error. Login success is inferred by subsequent app requests.

## 7. Testing

Unit-level coverage:

- `CookieBridge` already covers cookie sync in both directions.
- Add small tests only if new login routing or completion objects introduce testable logic.

Manual verification:

1. Open account page and tap login.
2. Confirm `https://www.nodeseek.com/signIn.html` loads in a visible WebView.
3. Confirm the hint `登录成功后关闭当前页面即可` is visible.
4. Complete login on the web page.
5. Close the page.
6. Confirm a restricted post can reload with authenticated cookies.
7. Confirm closing without login does not show an error.

## 8. Non-Goals

This implementation does not include:

- Native username/password fields.
- Automatic form submission.
- Login success parsing inside the login controller.
- Full account profile parsing.
- Logout flow.
- Cloudflare bypass behavior.

## 9. Open Decisions

No open product decisions remain for the first implementation.

The agreed behavior is:

- Use the NodeSeek sign-in WebView.
- Show `登录成功后关闭当前页面即可`.
- Sync cookies when the page closes.
- Refresh the source page afterward when applicable.
