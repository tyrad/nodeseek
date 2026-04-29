# NodeSeek WebView Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a visible NodeSeek login WebView that loads `https://www.nodeseek.com/signIn.html`, tells users to close the page after login, syncs cookies on close, and refreshes the source screen.

**Architecture:** Add one reusable `LoginWebViewController` under `Core/Networking` because it is shared authentication infrastructure rather than an Account-only screen. Route to it from Account and Post Detail through existing VIPER routers; presenters only request navigation and reload after the login page closes.

**Tech Stack:** Swift 5, UIKit, WebKit, Swift Testing, existing `CookieBridge`, existing VIPER modules.

---

## File Structure

- Create `nodeseek/Core/Networking/LoginWebViewController.swift`
  - Owns the visible `WKWebView`, fixed hint bar, close action, loading indicator, and cookie sync on close.
  - Defines `LoginCookieSynchronizing` so close behavior is testable without live WebKit cookie storage.
  - Makes `CookieBridge` conform to `LoginCookieSynchronizing`.
- Create `nodeseekTests/Core/LoginWebViewControllerTests.swift`
  - Verifies hint UI and close completion behavior.
- Modify `nodeseek/Features/Account/AccountContract.swift`
  - Add `didTapLogin()` to the presenter protocol.
  - Add `navigateToLogin(onClose:)` to the router protocol.
- Modify `nodeseek/Features/Account/AccountPresenter.swift`
  - Route login taps to the router.
  - Reload account state after login page closes.
- Modify `nodeseek/Features/Account/AccountViewController.swift`
  - Add a login button below the existing status label.
- Modify `nodeseek/Features/Account/AccountRouter.swift`
  - Push or present `LoginWebViewController`.
- Create `nodeseekTests/Features/AccountViewControllerTests.swift`
  - Verifies login button exists and calls the presenter.
- Create `nodeseekTests/Features/AccountPresenterTests.swift`
  - Verifies login close callback reloads account state.
- Modify `nodeseek/Features/PostDetail/PostDetailContract.swift`
  - Add `didTapLogin()` to the presenter protocol.
  - Add `navigateToLogin(onClose:)` to the router protocol.
- Modify `nodeseek/Features/PostDetail/PostDetailPresenter.swift`
  - Route login taps to the router.
  - Reload detail after login page closes.
- Modify `nodeseek/Features/PostDetail/PostDetailViewController.swift`
  - Add a login button in the login-required state.
  - Remove the button again when normal detail renders.
- Modify `nodeseek/Features/PostDetail/PostDetailRouter.swift`
  - Push or present `LoginWebViewController`.
- Modify `nodeseekTests/Features/PostDetailViewControllerTests.swift`
  - Update the spy presenter for the new protocol method.
  - Add a login-required button interaction test.
- Create `nodeseekTests/Features/PostDetailPresenterTests.swift`
  - Verifies login close callback reloads detail.

---

## Task 1: Reusable Login WebView Controller

**Files:**
- Create: `nodeseek/Core/Networking/LoginWebViewController.swift`
- Test: `nodeseekTests/Core/LoginWebViewControllerTests.swift`

- [ ] **Step 1: Write failing tests for hint UI and close completion**

Create `nodeseekTests/Core/LoginWebViewControllerTests.swift`:

```swift
//
//  LoginWebViewControllerTests.swift
//  nodeseekTests
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct LoginWebViewControllerTests {
    @Test func showsHintAndCloseButton() throws {
        let synchronizer = SpyLoginCookieSynchronizer()
        let viewController = LoginWebViewController(cookieSynchronizer: synchronizer)

        viewController.loadViewIfNeeded()

        let hintLabel = try #require(viewController.view.firstLabel(text: "登录成功后关闭当前页面即可"))
        #expect(hintLabel.numberOfLines == 0)
        #expect(viewController.navigationItem.rightBarButtonItem?.accessibilityLabel == "关闭登录页")
    }

    @Test func closeSyncsCookiesAndCallsCompletion() async throws {
        let synchronizer = SpyLoginCookieSynchronizer()
        var closeCount = 0
        let viewController = LoginWebViewController(cookieSynchronizer: synchronizer) {
            closeCount += 1
        }
        viewController.loadViewIfNeeded()

        let closeButton = try #require(viewController.navigationItem.rightBarButtonItem)
        let action = try #require(closeButton.action)
        _ = (closeButton.target as AnyObject).perform(action)
        try await Task.sleep(nanoseconds: 120_000_000)

        #expect(synchronizer.syncWebToURLSessionCount == 1)
        #expect(closeCount == 1)
    }
}

@MainActor
private final class SpyLoginCookieSynchronizer: LoginCookieSynchronizing {
    private(set) var syncURLSessionToWebCount = 0
    private(set) var syncWebToURLSessionCount = 0

    func syncURLSessionCookiesToWebView() async {
        syncURLSessionToWebCount += 1
    }

    func syncWebViewCookiesToURLSession() async {
        syncWebToURLSessionCount += 1
    }
}

private extension UIView {
    func firstLabel(text: String) -> UILabel? {
        if let label = self as? UILabel, label.text == text {
            return label
        }

        for subview in subviews {
            if let matched = subview.firstLabel(text: text) {
                return matched
            }
        }

        return nil
    }
}
```

- [ ] **Step 2: Run the new tests and verify they fail**

Run:

```bash
xcodebuild test \
  -project nodeseek.xcodeproj \
  -scheme nodeseek \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:nodeseekTests/LoginWebViewControllerTests \
  -derivedDataPath /tmp/nodeseek-derived \
  -clonedSourcePackagesDirPath /tmp/nodeseek-spm
```

Expected: build fails because `LoginWebViewController` and `LoginCookieSynchronizing` do not exist.

- [ ] **Step 3: Implement the login WebView controller**

Create `nodeseek/Core/Networking/LoginWebViewController.swift`:

```swift
//
//  LoginWebViewController.swift
//  nodeseek
//

import UIKit
import WebKit

@MainActor
protocol LoginCookieSynchronizing: AnyObject {
    func syncURLSessionCookiesToWebView() async
    func syncWebViewCookiesToURLSession() async
}

extension CookieBridge: LoginCookieSynchronizing {}

final class LoginWebViewController: UIViewController, WKNavigationDelegate {
    private static let loginURL = URL(string: "https://www.nodeseek.com/signIn.html")!

    private let cookieSynchronizer: LoginCookieSynchronizing
    private let onClose: @MainActor () -> Void
    private let webView: WKWebView
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    private let hintLabel: UILabel = {
        let label = UILabel()
        label.text = "登录成功后关闭当前页面即可"
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.textAlignment = .center
        label.backgroundColor = .secondarySystemBackground
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    init(
        cookieSynchronizer: LoginCookieSynchronizing? = nil,
        onClose: @escaping @MainActor () -> Void = {}
    ) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.cookieSynchronizer = cookieSynchronizer ?? CookieBridge(
            webCookieStore: WKWebCookieStoreAdapter(
                store: configuration.websiteDataStore.httpCookieStore
            )
        )
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "登录"
        view.backgroundColor = .systemBackground
        configureNavigationItems()
        configureWebView()
        loadLoginPage()
    }

    private func configureNavigationItems() {
        let closeButton = UIBarButtonItem(
            title: "关闭",
            style: .done,
            target: self,
            action: #selector(closeTapped)
        )
        closeButton.accessibilityLabel = "关闭登录页"
        navigationItem.rightBarButtonItem = closeButton
    }

    private func configureWebView() {
        webView.navigationDelegate = self
        webView.customUserAgent = WebRequestFingerprint.userAgent
        webView.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(hintLabel)
        view.addSubview(webView)
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hintLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),

            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: hintLabel.bottomAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func loadLoginPage() {
        loadingIndicator.startAnimating()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await cookieSynchronizer.syncURLSessionCookiesToWebView()
            var request = URLRequest(url: Self.loginURL)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadRevalidatingCacheData
            WebRequestFingerprint.applyHTMLHeaders(to: &request)
            webView.load(request)
        }
    }

    @objc private func closeTapped() {
        navigationItem.rightBarButtonItem?.isEnabled = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            await cookieSynchronizer.syncWebViewCookiesToURLSession()
            onClose()
            closeSelf()
        }
    }

    private func closeSelf() {
        if let navigationController, navigationController.viewControllers.first !== self {
            navigationController.popViewController(animated: true)
            return
        }

        dismiss(animated: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingIndicator.stopAnimating()
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
}
```

- [ ] **Step 4: Run the login WebView tests and verify they pass**

Run the same command from Step 2.

Expected: `LoginWebViewControllerTests` passes.

- [ ] **Step 5: Commit Task 1**

```bash
git add nodeseek/Core/Networking/LoginWebViewController.swift nodeseekTests/Core/LoginWebViewControllerTests.swift
git commit -m "Add NodeSeek login WebView"
```

---

## Task 2: Account Login Entry

**Files:**
- Modify: `nodeseek/Features/Account/AccountContract.swift`
- Modify: `nodeseek/Features/Account/AccountPresenter.swift`
- Modify: `nodeseek/Features/Account/AccountViewController.swift`
- Modify: `nodeseek/Features/Account/AccountRouter.swift`
- Test: `nodeseekTests/Features/AccountPresenterTests.swift`
- Test: `nodeseekTests/Features/AccountViewControllerTests.swift`

- [ ] **Step 1: Write failing Account presenter and view tests**

Create `nodeseekTests/Features/AccountPresenterTests.swift`:

```swift
//
//  AccountPresenterTests.swift
//  nodeseekTests
//

import Testing
@testable import nodeseek

@MainActor
struct AccountPresenterTests {
    @Test func loginCloseReloadsAccount() {
        let interactor = SpyAccountInteractor()
        let router = SpyAccountRouter()
        let presenter = AccountPresenter(interactor: interactor, router: router)

        presenter.didTapLogin()

        #expect(router.navigateToLoginCount == 1)
        #expect(interactor.loadAccountCount == 0)

        router.capturedOnClose?()

        #expect(interactor.loadAccountCount == 1)
    }
}

private final class SpyAccountInteractor: AccountInteractorInput {
    private(set) var loadAccountCount = 0

    func loadAccount() {
        loadAccountCount += 1
    }
}

private final class SpyAccountRouter: AccountRouterProtocol {
    private(set) var navigateToLoginCount = 0
    private(set) var capturedOnClose: (@MainActor () -> Void)?

    func navigateToLogin(onClose: @escaping @MainActor () -> Void) {
        navigateToLoginCount += 1
        capturedOnClose = onClose
    }
}
```

Create `nodeseekTests/Features/AccountViewControllerTests.swift`:

```swift
//
//  AccountViewControllerTests.swift
//  nodeseekTests
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct AccountViewControllerTests {
    @Test func showsLoginButtonAndSendsTapToPresenter() throws {
        let presenter = SpyAccountPresenter()
        let viewController = AccountViewController(presenter: presenter)

        viewController.loadViewIfNeeded()
        viewController.render(displayName: "游客", isLoggedIn: false)

        let button = try #require(viewController.view.firstButton(accessibilityIdentifier: "account-login-button"))
        #expect(button.configuration?.title == "登录")

        button.sendActions(for: .touchUpInside)

        #expect(presenter.didTapLoginCount == 1)
    }
}

private final class SpyAccountPresenter: AccountPresenterProtocol {
    private(set) var viewDidLoadCount = 0
    private(set) var didTapLoginCount = 0

    func viewDidLoad() {
        viewDidLoadCount += 1
    }

    func didTapLogin() {
        didTapLoginCount += 1
    }
}

private extension UIView {
    func firstButton(accessibilityIdentifier: String) -> UIButton? {
        if let button = self as? UIButton, button.accessibilityIdentifier == accessibilityIdentifier {
            return button
        }

        for subview in subviews {
            if let matched = subview.firstButton(accessibilityIdentifier: accessibilityIdentifier) {
                return matched
            }
        }

        return nil
    }
}
```

- [ ] **Step 2: Run the Account tests and verify they fail**

Run:

```bash
xcodebuild test \
  -project nodeseek.xcodeproj \
  -scheme nodeseek \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:nodeseekTests/AccountPresenterTests \
  -only-testing:nodeseekTests/AccountViewControllerTests \
  -derivedDataPath /tmp/nodeseek-derived \
  -clonedSourcePackagesDirPath /tmp/nodeseek-spm
```

Expected: build fails because `didTapLogin()` and `navigateToLogin(onClose:)` are not in the Account protocols.

- [ ] **Step 3: Update Account contracts**

In `nodeseek/Features/Account/AccountContract.swift`, replace the presenter and router protocol definitions with:

```swift
// MARK: - Presenter Protocol (View -> Presenter)
protocol AccountPresenterProtocol: AnyObject {
    func viewDidLoad()
    func didTapLogin()
}

// MARK: - Router Protocol (Presenter -> Router)
protocol AccountRouterProtocol: AnyObject {
    func navigateToLogin(onClose: @escaping @MainActor () -> Void)
}
```

Keep the existing view, interactor input, and interactor output protocols unchanged.

- [ ] **Step 4: Update Account presenter**

In `nodeseek/Features/Account/AccountPresenter.swift`, add this method inside `AccountPresenter`:

```swift
func didTapLogin() {
    router.navigateToLogin { [weak self] in
        self?.view?.showLoading()
        self?.interactor.loadAccount()
    }
}
```

The complete public methods in `AccountPresenter` should be:

```swift
func viewDidLoad() {
    view?.showLoading()
    interactor.loadAccount()
}

func didTapLogin() {
    router.navigateToLogin { [weak self] in
        self?.view?.showLoading()
        self?.interactor.loadAccount()
    }
}
```

- [ ] **Step 5: Add Account login button UI**

In `nodeseek/Features/Account/AccountViewController.swift`, add a button property below `loadingIndicator`:

```swift
private let loginButton: UIButton = {
    let button = UIButton(type: .system)
    var configuration = UIButton.Configuration.filled()
    configuration.title = "登录"
    configuration.image = UIImage(systemName: "person.crop.circle.badge.plus")
    configuration.imagePadding = 8
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
    button.configuration = configuration
    button.accessibilityIdentifier = "account-login-button"
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()
```

In `setupUI()`, after adding the loading indicator, wire and layout the button:

```swift
loginButton.addTarget(self, action: #selector(loginButtonTapped), for: .touchUpInside)
view.addSubview(loginButton)

NSLayoutConstraint.activate([
    statusLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
    statusLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
    statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -28),

    loginButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 24),
    loginButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

    loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
    loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
])
```

Add the tap handler inside `AccountViewController`:

```swift
@objc private func loginButtonTapped() {
    presenter.didTapLogin()
}
```

Update `render(displayName:isLoggedIn:)` so the button hides after a future account implementation reports a logged-in state:

```swift
func render(displayName: String, isLoggedIn: Bool) {
    let state = isLoggedIn ? "已登录" : "未登录"
    statusLabel.text = "\(displayName) · \(state)"
    loginButton.isHidden = isLoggedIn
}
```

- [ ] **Step 6: Add Account router navigation**

In `nodeseek/Features/Account/AccountRouter.swift`, add:

```swift
func navigateToLogin(onClose: @escaping @MainActor () -> Void) {
    let loginViewController = LoginWebViewController(onClose: onClose)
    if let navigationController = viewController?.navigationController {
        navigationController.pushViewController(loginViewController, animated: true)
        return
    }

    let navigationWrapper = UINavigationController(rootViewController: loginViewController)
    viewController?.present(navigationWrapper, animated: true)
}
```

- [ ] **Step 7: Run Account tests and verify they pass**

Run the same command from Step 2.

Expected: `AccountPresenterTests` and `AccountViewControllerTests` pass.

- [ ] **Step 8: Commit Task 2**

```bash
git add \
  nodeseek/Features/Account/AccountContract.swift \
  nodeseek/Features/Account/AccountPresenter.swift \
  nodeseek/Features/Account/AccountViewController.swift \
  nodeseek/Features/Account/AccountRouter.swift \
  nodeseekTests/Features/AccountPresenterTests.swift \
  nodeseekTests/Features/AccountViewControllerTests.swift
git commit -m "Add account login entry"
```

---

## Task 3: Post Detail Login-Required Entry

**Files:**
- Modify: `nodeseek/Features/PostDetail/PostDetailContract.swift`
- Modify: `nodeseek/Features/PostDetail/PostDetailPresenter.swift`
- Modify: `nodeseek/Features/PostDetail/PostDetailViewController.swift`
- Modify: `nodeseek/Features/PostDetail/PostDetailRouter.swift`
- Modify: `nodeseekTests/Features/PostDetailViewControllerTests.swift`
- Test: `nodeseekTests/Features/PostDetailPresenterTests.swift`

- [ ] **Step 1: Write failing Post Detail presenter test**

Create `nodeseekTests/Features/PostDetailPresenterTests.swift`:

```swift
//
//  PostDetailPresenterTests.swift
//  nodeseekTests
//

import Testing
@testable import nodeseek

@MainActor
struct PostDetailPresenterTests {
    @Test func loginCloseReloadsPostDetail() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router)

        presenter.didTapLogin()

        #expect(router.navigateToLoginCount == 1)
        #expect(interactor.loadPostDetailCount == 0)

        router.capturedOnClose?()

        #expect(interactor.loadPostDetailCount == 1)
    }
}

private final class SpyPostDetailInteractor: PostDetailInteractorInput {
    private(set) var loadPostDetailCount = 0

    func loadPostDetail() {
        loadPostDetailCount += 1
    }
}

private final class SpyPostDetailRouter: PostDetailRouterProtocol {
    private(set) var navigateToLoginCount = 0
    private(set) var capturedOnClose: (@MainActor () -> Void)?

    func navigateToLogin(onClose: @escaping @MainActor () -> Void) {
        navigateToLoginCount += 1
        capturedOnClose = onClose
    }
}
```

- [ ] **Step 2: Add failing Post Detail login-required button test**

Append this test inside `PostDetailViewControllerTests`:

```swift
@Test func loginRequiredStateShowsLoginButtonAndSendsTapToPresenter() throws {
    let presenter = SpyPostDetailPresenter()
    let viewController = PostDetailViewController(presenter: presenter)

    viewController.loadViewIfNeeded()
    viewController.renderLoginRequired(message: "本帖需要注册用户才能查看😭")

    let button = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-detail-login-button"))
    #expect(button.configuration?.title == "登录查看")

    button.sendActions(for: .touchUpInside)

    #expect(presenter.didTapLoginCount == 1)
}
```

Update the existing `SpyPostDetailPresenter` in `PostDetailViewControllerTests` to include:

```swift
private(set) var didTapLoginCount = 0

func didTapLogin() {
    didTapLoginCount += 1
}
```

Add this helper to the private `UIView` extension in `PostDetailViewControllerTests`:

```swift
func firstButton(accessibilityIdentifier: String) -> UIButton? {
    if let button = self as? UIButton, button.accessibilityIdentifier == accessibilityIdentifier {
        return button
    }

    for subview in subviews {
        if let matched = subview.firstButton(accessibilityIdentifier: accessibilityIdentifier) {
            return matched
        }
    }

    return nil
}
```

- [ ] **Step 3: Run Post Detail tests and verify they fail**

Run:

```bash
xcodebuild test \
  -project nodeseek.xcodeproj \
  -scheme nodeseek \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:nodeseekTests/PostDetailPresenterTests \
  -only-testing:nodeseekTests/PostDetailViewControllerTests/loginRequiredStateShowsLoginButtonAndSendsTapToPresenter \
  -derivedDataPath /tmp/nodeseek-derived \
  -clonedSourcePackagesDirPath /tmp/nodeseek-spm
```

Expected: build fails because `didTapLogin()` and `navigateToLogin(onClose:)` are not in the Post Detail protocols.

- [ ] **Step 4: Update Post Detail contracts**

In `nodeseek/Features/PostDetail/PostDetailContract.swift`, replace the presenter and router protocol definitions with:

```swift
// MARK: - Presenter Protocol (View -> Presenter)
protocol PostDetailPresenterProtocol: AnyObject {
    func viewDidLoad()
    func didTapLogin()
}

// MARK: - Router Protocol (Presenter -> Router)
protocol PostDetailRouterProtocol: AnyObject {
    func navigateToLogin(onClose: @escaping @MainActor () -> Void)
}
```

Keep the existing view and interactor protocols unchanged.

- [ ] **Step 5: Update Post Detail presenter**

In `nodeseek/Features/PostDetail/PostDetailPresenter.swift`, add:

```swift
func didTapLogin() {
    router.navigateToLogin { [weak self] in
        self?.view?.showLoading()
        self?.interactor.loadPostDetail()
    }
}
```

The complete public methods in `PostDetailPresenter` should be:

```swift
func viewDidLoad() {
    view?.showLoading()
    interactor.loadPostDetail()
}

func didTapLogin() {
    router.navigateToLogin { [weak self] in
        self?.view?.showLoading()
        self?.interactor.loadPostDetail()
    }
}
```

- [ ] **Step 6: Add login-required button UI**

In `nodeseek/Features/PostDetail/PostDetailViewController.swift`, add this property near `loadingIndicator`:

```swift
private let loginButton: UIButton = {
    let button = UIButton(type: .system)
    var configuration = UIButton.Configuration.filled()
    configuration.title = "登录查看"
    configuration.image = UIImage(systemName: "person.crop.circle.badge.plus")
    configuration.imagePadding = 8
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
    button.configuration = configuration
    button.accessibilityIdentifier = "post-detail-login-button"
    button.isHidden = true
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()
```

In `setupUI()`, after adding `loadingIndicator`, add:

```swift
loginButton.addTarget(self, action: #selector(loginButtonTapped), for: .touchUpInside)
view.addSubview(loginButton)
```

Add these constraints to the existing `NSLayoutConstraint.activate` call:

```swift
loginButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
loginButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28)
```

Add the tap handler:

```swift
@objc private func loginButtonTapped() {
    presenter.didTapLogin()
}
```

In `render(detail:)`, hide the button:

```swift
loginButton.isHidden = true
```

Place it after `title = "详情"`.

In `renderLoginRequired(message:)`, show the button:

```swift
loginButton.isHidden = false
```

Place it after `title = "详情"`.

- [ ] **Step 7: Add Post Detail router navigation**

In `nodeseek/Features/PostDetail/PostDetailRouter.swift`, add:

```swift
func navigateToLogin(onClose: @escaping @MainActor () -> Void) {
    let loginViewController = LoginWebViewController(onClose: onClose)
    if let navigationController = viewController?.navigationController {
        navigationController.pushViewController(loginViewController, animated: true)
        return
    }

    let navigationWrapper = UINavigationController(rootViewController: loginViewController)
    viewController?.present(navigationWrapper, animated: true)
}
```

- [ ] **Step 8: Run Post Detail tests and verify they pass**

Run the same command from Step 3.

Expected: `PostDetailPresenterTests` and the new login-required view test pass.

- [ ] **Step 9: Commit Task 3**

```bash
git add \
  nodeseek/Features/PostDetail/PostDetailContract.swift \
  nodeseek/Features/PostDetail/PostDetailPresenter.swift \
  nodeseek/Features/PostDetail/PostDetailViewController.swift \
  nodeseek/Features/PostDetail/PostDetailRouter.swift \
  nodeseekTests/Features/PostDetailPresenterTests.swift \
  nodeseekTests/Features/PostDetailViewControllerTests.swift
git commit -m "Add post detail login entry"
```

---

## Task 4: Full Verification and Manual Smoke

**Files:**
- No planned source edits.

- [ ] **Step 1: Run focused login-related tests**

Run:

```bash
xcodebuild test \
  -project nodeseek.xcodeproj \
  -scheme nodeseek \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:nodeseekTests/LoginWebViewControllerTests \
  -only-testing:nodeseekTests/AccountPresenterTests \
  -only-testing:nodeseekTests/AccountViewControllerTests \
  -only-testing:nodeseekTests/PostDetailPresenterTests \
  -only-testing:nodeseekTests/PostDetailViewControllerTests/loginRequiredStateShowsLoginButtonAndSendsTapToPresenter \
  -derivedDataPath /tmp/nodeseek-derived \
  -clonedSourcePackagesDirPath /tmp/nodeseek-spm
```

Expected: all focused tests pass.

- [ ] **Step 2: Run the full test target**

Run:

```bash
xcodebuild test \
  -project nodeseek.xcodeproj \
  -scheme nodeseek \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/nodeseek-derived \
  -clonedSourcePackagesDirPath /tmp/nodeseek-spm
```

Expected: full `nodeseekTests` target passes.

- [ ] **Step 3: Build and launch on simulator**

Run through XcodeBuildMCP or command line:

```bash
xcodebuild build \
  -project nodeseek.xcodeproj \
  -scheme nodeseek \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/nodeseek-derived \
  -clonedSourcePackagesDirPath /tmp/nodeseek-spm
```

Expected: app build succeeds.

- [ ] **Step 4: Manual smoke test**

Use the simulator:

1. Open the app.
2. Open the Account page if a reachable entry exists in the current shell.
3. Tap `登录`.
4. Confirm the login page shows `登录成功后关闭当前页面即可`.
5. Confirm the close button is visible.
6. Close without logging in and confirm the app returns without an error.
7. Open a restricted post flow if available.
8. Tap `登录查看`.
9. Confirm the same login page appears.

If the current UI has no stable Account entry from the post list yet, record that as a remaining manual verification gap and rely on the route/unit tests for Account.

- [ ] **Step 5: Final status check**

Run:

```bash
git status --short
git log --oneline -4
```

Expected: only intended changes are present, and implementation commits are visible.

---

## Self-Review

Spec coverage:

- WebView loads `https://www.nodeseek.com/signIn.html`: Task 1.
- Fixed hint `登录成功后关闭当前页面即可`: Task 1.
- Close action syncs WebView cookies to native storage: Task 1.
- Account entry point: Task 2.
- Login-required detail entry point: Task 3.
- Refresh source screen after close: Tasks 2 and 3.
- Closing without login is not an error: Task 1 close path never validates login.
- No native credentials or automatic form submission: Task 1 only loads a URL and syncs cookies.

Open-item scan:

- No unresolved open items are intentionally left in this plan.

Type consistency:

- `LoginCookieSynchronizing` methods match existing `CookieBridge` method names.
- `didTapLogin()` is added to both presenter protocols and implemented by test spies.
- `navigateToLogin(onClose:)` is added to both router protocols and implemented by real routers and test spies.
