//
//  AccountsModule.swift
//  nodeseek
//

import UIKit

/// 多账号功能的唯一对外门面，负责协调启动准备、入口展示、会话切换与自动签到协作。
@MainActor
enum AccountsModule {
    static let vaultStore = AccountVaultStore.shared
    static let coordinator = AccountSwitchCoordinator.shared

    private static var hasConfiguredVerifier = false

    static func registerRootResetHandler(_ handler: @escaping AccountSwitchCoordinator.RootResetHandler) {
        coordinator.registerRootResetHandler(handler)
        configurePostSwitchVerifierIfNeeded()
    }

    static func prepareAtLaunch() async {
        configurePostSwitchVerifierIfNeeded()
        await coordinator.prepareAtLaunch()
    }

    static func adoptCurrentSessionIfNeeded(account: AccountResponse, requestSessionID: UUID?) async {
        await coordinator.adoptCurrentSessionIfNeeded(account: account, requestSessionID: requestSessionID)
    }

    static func adoptAfterDirectLogin(account: AccountResponse) async {
        await coordinator.adoptAfterDirectLogin(account: account)
    }

    static func handleConfirmedLoggedOut(requestSessionID: UUID?) async {
        await coordinator.handleConfirmedLoggedOut(requestSessionID: requestSessionID)
    }

    @discardableResult
    static func logoutCurrentAccount() async -> AccountLogoutOutcome {
        await coordinator.logoutCurrentAccount()
    }

    @discardableResult
    static func switchToAccount(uid: Int, from source: UIViewController?) async -> AccountSwitchResult {
        let result = await coordinator.switchToAccount(uid: uid)
        switch result {
        case .requiresRelogin(let account):
            if let source {
                presentAddAccount(
                    from: source,
                    pageTitle: AccountsL10n.format("重新登录 %@", account.displayName)
                )
            }
        case .failed(let message):
            if let view = source?.view {
                BottomToast.show(message, style: .failure, in: view)
            }
        case .switched, .noop:
            break
        }
        return result
    }

    static func presentAccountSwitcher(from source: UIViewController) {
        let switcher = AccountSwitcherViewController()
        let nav = UINavigationController(rootViewController: switcher)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        source.present(nav, animated: true)
    }

    static func makeManagementViewController() -> UIViewController {
        AccountManagementViewController()
    }

    static func presentAddAccount(
        from source: UIViewController,
        pageTitle: String = AccountsL10n.text("添加账号")
    ) {
        let controller = AddAccountWebViewController(
            pageTitle: pageTitle,
            onComplete: { account, cookies in
                Task { @MainActor in
                    let result = await coordinator.completeAddAccount(account: account, cookies: cookies)
                    if case let .failed(message) = result, let view = source.view {
                        BottomToast.show(message, style: .failure, in: view)
                    }
                }
            }
        )
        let nav = UINavigationController(rootViewController: controller)
        nav.modalPresentationStyle = .fullScreen
        source.present(nav, animated: true)
    }

    static func presentPostLogoutSwitchPrompt(from root: UIViewController) {
        let remaining = vaultStore.accounts.count
        guard remaining > 0 else { return }
        let alert = UIAlertController(
            title: AccountsL10n.text("已退出当前账号"),
            message: AccountsL10n.format("当前为游客模式，本机还有 %d 个已保存账号，是否立即切换？", remaining),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: AccountsL10n.text("切换账号"), style: .default) { _ in
            Task { @MainActor in
                presentAccountSwitcher(from: root)
            }
        })
        alert.addAction(UIAlertAction(title: AccountsL10n.text("保持游客"), style: .cancel))
        root.present(alert, animated: true)
    }

    static var savedAccountsSummary: String {
        let count = vaultStore.accounts.count
        guard count > 0 else { return AccountsL10n.text("未保存") }
        return AccountsL10n.format("%d 个账号", count)
    }

    static var hasSavedAccounts: Bool {
        vaultStore.accounts.isEmpty == false
    }

    static func otherValidAccountsForAutoCheckIn(excluding activeUID: Int?) -> [SavedAccount] {
        vaultStore.otherValidAccounts(excluding: activeUID)
    }

    static func cookiesForAutoCheckIn(uid: Int) -> [HTTPCookie]? {
        coordinator.cookiesForBackgroundAccount(uid: uid)
    }

    static func exportCloudflareCookies() async -> [HTTPCookie] {
        await coordinator.exportCloudflareCookies()
    }

    static func updateCookiesAfterIsolatedCheckIn(_ cookies: [HTTPCookie], forUID uid: Int) {
        coordinator.updateCookiesAfterIsolatedCheckIn(cookies, forUID: uid)
    }

    static func markAccountExpiredFromBackground(uid: Int) {
        coordinator.markAccountExpiredSilently(uid: uid)
    }

    #if DEBUG
    static func cloneActiveAccountForTesting(in viewController: UIViewController) {
        Task { @MainActor in
            switch await coordinator.cloneActiveAccountForTesting() {
            case .success(let clone):
                BottomToast.show("已创建测试分身：\(clone.displayName)", style: .success, in: viewController.view)
            case .failure(let error):
                BottomToast.show(error.localizedDescription, style: .failure, in: viewController.view)
            }
        }
    }
    #endif

    private static func configurePostSwitchVerifierIfNeeded() {
        guard hasConfiguredVerifier == false else { return }
        hasConfiguredVerifier = true
        coordinator.registerPostSwitchVerifier { _, _ in
            Task { @MainActor in
                _ = await CurrentAccountRefresher.shared.refreshIfNeeded(force: true, maxAge: 0)
            }
        }
    }
}
