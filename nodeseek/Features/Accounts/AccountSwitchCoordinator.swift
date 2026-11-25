//
//  AccountSwitchCoordinator.swift
//  nodeseek
//

import UIKit

enum AccountSwitchResult: Equatable {
    case switched(SavedAccount)
    case requiresRelogin(SavedAccount)
    case noop
    case failed(String)
}

struct AccountLogoutOutcome: Equatable {
    let remainingAccountCount: Int
}

enum AccountRemoveOutcome: Equatable {
    case removedInactive
    case loggedOutCurrent(remainingAccountCount: Int)
    case noop
}

/// 串行编排多账号采纳、切换、添加、退出、删除与会话失效闭环。
@MainActor
final class AccountSwitchCoordinator {
    typealias RootResetHandler = @MainActor (@escaping @MainActor (UIViewController?) -> Void) -> Void
    typealias SessionCacheCleaner = @MainActor () async -> Void
    typealias HiddenWebViewInvalidator = @MainActor () -> Void
    typealias PostSwitchVerifier = @MainActor (Int, Int?) -> Void

    static let shared = AccountSwitchCoordinator()

    private let vaultStore: AccountVaultStore
    private let cookieVault: AccountCookieVaultStoring
    private let cookieSession: NodeSeekCookieSessionManaging
    private let currentAccountStore: CurrentAccountStore
    private let clearSessionCaches: SessionCacheCleaner
    private let invalidateHiddenWebViews: HiddenWebViewInvalidator
    private let notificationCenter: NotificationCenter
    private let now: () -> Date

    private(set) var isTransitioning = false
    private var rootResetHandler: RootResetHandler?
    private var lastSwitchedFromUID: Int?
    private var lastExpiredPromptUID: Int?
    private var postSwitchVerifier: PostSwitchVerifier?

    init(
        vaultStore: AccountVaultStore = .shared,
        cookieVault: AccountCookieVaultStoring? = nil,
        cookieSession: NodeSeekCookieSessionManaging? = nil,
        currentAccountStore: CurrentAccountStore = .shared,
        clearSessionCaches: @escaping SessionCacheCleaner = {
            await DefaultSettingsCacheManager.clearSessionWebCachesPreservingCookies()
        },
        invalidateHiddenWebViews: @escaping HiddenWebViewInvalidator = {
            HiddenWebViewPostActionPageScheduler.invalidatePreparedPage()
            HiddenWebViewPageActionScheduler.invalidatePreparedPage()
            HiddenWebViewLoader.invalidateAllSessions()
        },
        notificationCenter: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.vaultStore = vaultStore
        self.cookieVault = cookieVault ?? KeychainAccountCookieVault()
        self.cookieSession = cookieSession ?? NodeSeekCookieSession()
        self.currentAccountStore = currentAccountStore
        self.clearSessionCaches = clearSessionCaches
        self.invalidateHiddenWebViews = invalidateHiddenWebViews
        self.notificationCenter = notificationCenter
        self.now = now
    }

    func registerRootResetHandler(_ handler: @escaping RootResetHandler) {
        rootResetHandler = handler
    }

    func registerPostSwitchVerifier(_ verifier: @escaping PostSwitchVerifier) {
        postSwitchVerifier = verifier
    }

    /// 冷启动准备：清理重装孤儿 Keychain、恢复中断的切号，并无感采纳老版本当前账号。
    func prepareAtLaunch() async {
        // 卸载重装会清空 UserDefaults 但保留 Keychain；仅在仓库从未初始化时清一次多账号专用分组。
        if vaultStore.isInitialized == false {
            cookieVault.deleteAll()
            vaultStore.markInitialized()
        }

        if let pendingUID = vaultStore.pendingSwitchTargetUID {
            await recoverInterruptedSwitch(targetUID: pendingUID)
        }

        // 老版本无感采纳：不清理任何活跃 Cookie，仅将已有登录快照收编进多账号仓库。
        if vaultStore.accounts.isEmpty,
           let snapshot = await currentAccountStore.snapshot(),
           let saved = SavedAccount(account: snapshot.account, lastUsedAt: snapshot.updatedAt) {
            let activeCookies = await cookieSession.exportAccountSessionCookies()
            if activeCookies.isEmpty == false {
                _ = cookieVault.saveCookies(activeCookies, forUID: saved.uid)
            }
            vaultStore.upsert(saved, setActive: true)
            AppLog.debug(.account, "accounts: 冷启动采纳老版本账号 uid=\(saved.uid)")
        }
    }

    /// 必须在 CurrentAccountStore.save(account, for: requestSessionID) 校验通过后调用。
    /// 通过三重校验防止切号前的迟到响应把新账号 Cookie 错写进旧账号 Keychain。
    func adoptCurrentSessionIfNeeded(
        account: AccountResponse,
        requestSessionID: UUID?
    ) async {
        guard isTransitioning == false else { return }
        guard let saved = SavedAccount(account: account, lastUsedAt: now(), credentialState: .valid) else { return }
        let currentSessionID = await currentAccountStore.sessionID
        guard let requestSessionID, requestSessionID == currentSessionID else {
            AppLog.debug(.account, "accounts: 忽略过期 sessionID 的采纳 uid=\(saved.uid)")
            return
        }

        let currentActiveUID = vaultStore.activeUID
        let allowsAdopt = (currentActiveUID == saved.uid)
            || (currentActiveUID == nil && vaultStore.account(uid: saved.uid) == nil)
            || vaultStore.accounts.isEmpty
        guard allowsAdopt else {
            AppLog.debug(.account, "accounts: 拒绝跨号采纳 parsedUID=\(saved.uid) activeUID=\(currentActiveUID.map(String.init) ?? "nil")")
            return
        }

        let activeCookies = await cookieSession.exportAccountSessionCookies()
        // 异步导出后再确认一次未发生切号，避免导出期间会话变化。
        guard isTransitioning == false, await currentAccountStore.sessionID == currentSessionID else { return }

        if activeCookies.isEmpty == false {
            _ = cookieVault.saveCookies(activeCookies, forUID: saved.uid)
        }
        vaultStore.upsert(saved, setActive: true)
        if lastExpiredPromptUID == saved.uid {
            lastExpiredPromptUID = nil
        }
    }

    /// 游客页登录成功后同步录入多账号仓库与 Keychain。
    func adoptAfterDirectLogin(account: AccountResponse) async {
        guard let saved = SavedAccount(account: account, lastUsedAt: now(), credentialState: .valid) else { return }
        let cookies = await cookieSession.exportAccountSessionCookies()
        if cookies.isEmpty == false {
            _ = cookieVault.saveCookies(cookies, forUID: saved.uid)
        }
        vaultStore.upsert(saved, setActive: true)
        lastExpiredPromptUID = nil
    }

    /// 仅在主页/账号接口明确返回正常游客态（非 challenge/错误页）时调用。
    /// 遵循保留快照原则：不删除 Keychain 快照，也不主动清空活跃 Cookie。
    func handleConfirmedLoggedOut(requestSessionID: UUID?) async {
        guard isTransitioning == false else { return }
        let currentSessionID = await currentAccountStore.sessionID
        guard let requestSessionID, requestSessionID == currentSessionID else { return }
        guard let activeUID = vaultStore.activeUID,
              let account = vaultStore.account(uid: activeUID) else { return }

        vaultStore.markCredentialState(.expired, for: activeUID)
        AppLog.warning(.account, "accounts: 账号登录态可能已失效 uid=\(activeUID)")

        guard lastExpiredPromptUID != activeUID else { return }
        lastExpiredPromptUID = activeUID
        let fallbackUID = lastSwitchedFromUID.flatMap { candidate -> Int? in
            guard candidate != activeUID,
                  let saved = vaultStore.account(uid: candidate),
                  saved.credentialState == .valid else { return nil }
            return candidate
        }
        presentExpiredAccountAlert(account: account, previousUID: fallbackUID)
    }

    func switchToAccount(uid targetUID: Int) async -> AccountSwitchResult {
        guard isTransitioning == false else { return .noop }
        guard let target = vaultStore.account(uid: targetUID) else {
            return .failed(AccountsL10n.text("未找到目标账号"))
        }
        if target.credentialState == .expired {
            return .requiresRelogin(target)
        }
        if vaultStore.activeUID == targetUID {
            return .noop
        }
        guard let targetCookies = cookieVault.loadCookies(forUID: targetUID),
              targetCookies.isEmpty == false else {
            vaultStore.markCredentialState(.expired, for: targetUID)
            return .requiresRelogin(vaultStore.account(uid: targetUID) ?? target)
        }

        isTransitioning = true
        defer { isTransitioning = false }

        let previousUID = vaultStore.activeUID
        if let previousUID,
           let previousAccount = vaultStore.account(uid: previousUID),
           previousAccount.credentialState == .valid {
            let currentCookies = await cookieSession.exportAccountSessionCookies()
            if currentCookies.isEmpty == false {
                let saved = cookieVault.saveCookies(currentCookies, forUID: previousUID)
                guard saved else {
                    return .failed(AccountsL10n.text("保存当前账号凭证失败，已取消切换"))
                }
            }
        }

        vaultStore.pendingSwitchTargetUID = targetUID
        await performSessionSwap(to: target, cookies: targetCookies)
        vaultStore.pendingSwitchTargetUID = nil
        lastSwitchedFromUID = previousUID
        lastExpiredPromptUID = nil

        let updatedTarget = vaultStore.account(uid: targetUID) ?? target
        let toastText = AccountsL10n.format("已切换到 %@", updatedTarget.displayName)
        await finishTransitionResetToHome { root in
            if let root {
                BottomToast.show(toastText, style: .success, in: root.view)
            }
        }
        postSwitchVerifier?(targetUID, previousUID)
        return .switched(updatedTarget)
    }

    /// 由 AddAccountWebViewController 提取独立账号 Cookie 后调用。
    func completeAddAccount(
        account: AccountResponse,
        cookies: [HTTPCookie]
    ) async -> AccountSwitchResult {
        guard isTransitioning == false else { return .noop }
        guard let savedAccount = SavedAccount(account: account, lastUsedAt: now(), credentialState: .valid) else {
            return .failed(AccountsL10n.text("未能识别账号信息，请重试"))
        }
        let accountCookies = NodeSeekCookieClassifier.accountSessionCookies(from: cookies)
        guard accountCookies.isEmpty == false else {
            return .failed(AccountsL10n.text("未能读取登录凭证，请重试"))
        }

        isTransitioning = true
        defer { isTransitioning = false }

        let previousUID = vaultStore.activeUID
        if let previousUID,
           previousUID != savedAccount.uid,
           let previousAccount = vaultStore.account(uid: previousUID),
           previousAccount.credentialState == .valid {
            let currentCookies = await cookieSession.exportAccountSessionCookies()
            if currentCookies.isEmpty == false {
                let saved = cookieVault.saveCookies(currentCookies, forUID: previousUID)
                guard saved else {
                    return .failed(AccountsL10n.text("保存当前账号凭证失败，已取消添加"))
                }
            }
        }

        guard cookieVault.saveCookies(accountCookies, forUID: savedAccount.uid) else {
            return .failed(AccountsL10n.text("保存新账号凭证失败，请重试"))
        }

        let stored = vaultStore.upsert(savedAccount, setActive: false)
        vaultStore.pendingSwitchTargetUID = stored.uid
        await performSessionSwap(to: stored, cookies: accountCookies)
        vaultStore.pendingSwitchTargetUID = nil
        lastSwitchedFromUID = previousUID == stored.uid ? nil : previousUID
        lastExpiredPromptUID = nil

        let toastText = AccountsL10n.format("已切换到 %@", stored.displayName)
        await finishTransitionResetToHome { root in
            if let root {
                BottomToast.show(toastText, style: .success, in: root.view)
            }
        }
        return .switched(stored)
    }

    /// 退出当前账号：删除本地 Cookie 快照、进入游客模式、不清空 NodeImage Key，并在有其他账号时引导切换。
    func logoutCurrentAccount() async -> AccountLogoutOutcome {
        guard isTransitioning == false else {
            return AccountLogoutOutcome(remainingAccountCount: vaultStore.accounts.count)
        }

        isTransitioning = true
        defer { isTransitioning = false }

        if let activeUID = vaultStore.activeUID {
            cookieVault.deleteCookies(forUID: activeUID)
            vaultStore.remove(uid: activeUID)
        } else if let snapshotUID = await currentAccountStore.snapshot()?.account.nodeSeekUID {
            cookieVault.deleteCookies(forUID: snapshotUID)
            vaultStore.remove(uid: snapshotUID)
        }

        vaultStore.pendingSwitchTargetUID = nil
        lastSwitchedFromUID = nil
        lastExpiredPromptUID = nil

        await currentAccountStore.beginLogoutCleanup()
        invalidateHiddenWebViews()
        await clearSessionCaches()
        await cookieSession.clearAccountSessionCookies()
        await currentAccountStore.finishLogoutCleanup(atLaunch: false)

        let remainingCount = vaultStore.accounts.count
        await finishTransitionResetToHome { root in
            guard let root else { return }
            if remainingCount > 0 {
                AccountsModule.presentPostLogoutSwitchPrompt(from: root)
            } else {
                BottomToast.show(AccountsL10n.text("已退出登录"), style: .success, in: root.view)
            }
        }
        return AccountLogoutOutcome(remainingAccountCount: remainingCount)
    }

    func removeAccount(uid: Int) async -> AccountRemoveOutcome {
        guard isTransitioning == false else { return .noop }
        if vaultStore.activeUID == uid {
            let outcome = await logoutCurrentAccount()
            return .loggedOutCurrent(remainingAccountCount: outcome.remainingAccountCount)
        }
        cookieVault.deleteCookies(forUID: uid)
        let removed = vaultStore.remove(uid: uid)
        return removed ? .removedInactive : .noop
    }

    func updateCookiesAfterIsolatedCheckIn(_ cookies: [HTTPCookie], forUID uid: Int) {
        guard isTransitioning == false else { return }
        guard vaultStore.activeUID != uid,
              vaultStore.account(uid: uid) != nil else { return }
        let accountCookies = NodeSeekCookieClassifier.accountSessionCookies(from: cookies)
        guard accountCookies.isEmpty == false else { return }
        _ = cookieVault.saveCookies(accountCookies, forUID: uid)
    }

    func markAccountExpiredSilently(uid: Int) {
        vaultStore.markCredentialState(.expired, for: uid)
    }

    func cookiesForBackgroundAccount(uid: Int) -> [HTTPCookie]? {
        cookieVault.loadCookies(forUID: uid)
    }

    func exportCloudflareCookies() async -> [HTTPCookie] {
        await cookieSession.exportCloudflareCookies()
    }

    #if DEBUG
    /// 仅供开发调试：将当前活跃账号的真实 Cookie 复制为一个虚拟 UID 测试分身，便于单账号验证多账号互切与退登引导。
    func cloneActiveAccountForTesting() async -> Result<SavedAccount, NSError> {
        let activeAccount: AccountResponse?
        if let saved = vaultStore.activeAccount {
            activeAccount = saved.toAccountResponse()
        } else {
            activeAccount = await currentAccountStore.snapshot()?.account
        }
        guard let activeAccount, activeAccount.isLoggedIn, let profileURL = activeAccount.profileURL else {
            return .failure(NSError(
                domain: "AccountsDebug",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "请先登录一个账号再克隆测试分身"]
            ))
        }
        let cookies = await cookieSession.exportAccountSessionCookies()
        guard cookies.isEmpty == false else {
            return .failure(NSError(
                domain: "AccountsDebug",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "未读取到当前账号 Cookie，请先刷新首页再试"]
            ))
        }

        let existingCloneUIDs = Set(vaultStore.accounts.map(\.uid))
        var index = 1
        var cloneUID = 900_000_001
        while existingCloneUIDs.contains(cloneUID) {
            index += 1
            cloneUID += 1
        }

        guard cookieVault.saveCookies(cookies, forUID: cloneUID) else {
            return .failure(NSError(
                domain: "AccountsDebug",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "保存测试分身凭证到钥匙串失败"]
            ))
        }

        let clone = SavedAccount(
            uid: cloneUID,
            displayName: "\(activeAccount.displayName) (测试分身 \(index))",
            avatarURL: activeAccount.avatarURL,
            profileURL: profileURL,
            stats: activeAccount.stats,
            lastUsedAt: now().addingTimeInterval(-1),
            credentialState: .valid
        )
        let stored = vaultStore.upsert(clone, setActive: false)
        return .success(stored)
    }
    #endif

    // MARK: - Private

    private func performSessionSwap(to target: SavedAccount, cookies: [HTTPCookie]) async {
        _ = await currentAccountStore.rotateSessionID()
        invalidateHiddenWebViews()
        await clearSessionCaches()
        await cookieSession.replaceAccountSessionCookies(with: cookies)
        _ = await currentAccountStore.replaceSnapshot(target.toAccountResponse(), updatedAt: now())
        vaultStore.setActive(uid: target.uid, touchLastUsedAt: now())
        vaultStore.markCredentialState(.valid, for: target.uid)
    }

    private func recoverInterruptedSwitch(targetUID: Int) async {
        defer { vaultStore.pendingSwitchTargetUID = nil }
        guard let target = vaultStore.account(uid: targetUID),
              let cookies = cookieVault.loadCookies(forUID: targetUID),
              cookies.isEmpty == false else {
            AppLog.warning(.account, "accounts: 冷启动恢复切号缺少快照，已清除标记 uid=\(targetUID)")
            return
        }
        AppLog.info(.account, "accounts: 冷启动补全中断的切号 uid=\(targetUID)")
        await performSessionSwap(to: target, cookies: cookies)
    }

    private func finishTransitionResetToHome(
        afterReset: @escaping @MainActor (UIViewController?) -> Void
    ) async {
        if let rootResetHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                rootResetHandler { [notificationCenter] newRoot in
                    // 先完成根界面替换再发通知，避免旧 TabBar 做无意义重建，同时通知所有全局服务清旧态。
                    notificationCenter.post(
                        name: .nodeSeekAccountSessionDidChange,
                        object: nil,
                        userInfo: ["replacesRoot": true]
                    )
                    notificationCenter.post(name: .nodeSeekLoginSessionDidClose, object: nil)
                    afterReset(newRoot)
                    continuation.resume()
                }
            }
        } else {
            notificationCenter.post(
                name: .nodeSeekAccountSessionDidChange,
                object: nil,
                userInfo: ["replacesRoot": true]
            )
            notificationCenter.post(name: .nodeSeekLoginSessionDidClose, object: nil)
            afterReset(nil)
        }
    }

    private func presentExpiredAccountAlert(account: SavedAccount, previousUID: Int?) {
        guard let presenter = Self.topMostViewController() else { return }
        guard !(presenter is UIAlertController), !(presenter is AddAccountWebViewController) else { return }

        let title = AccountsL10n.text("登录状态可能已失效")
        let message = AccountsL10n.format("账号「%@」的登录状态可能已过期，本地凭证已保留。你可以重新登录或切换其他账号。", account.displayName)
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: AccountsL10n.text("重新登录"), style: .default) { _ in
            Task { @MainActor in
                AccountsModule.presentAddAccount(from: presenter)
            }
        })
        if let previousUID,
           let previousAccount = vaultStore.account(uid: previousUID),
           previousAccount.credentialState == .valid {
            alert.addAction(UIAlertAction(
                title: AccountsL10n.format("切回 %@", previousAccount.displayName),
                style: .default
            ) { _ in
                Task { @MainActor in
                    _ = await AccountsModule.switchToAccount(uid: previousUID, from: presenter)
                }
            })
        } else if vaultStore.hasOtherAccounts(excluding: account.uid) {
            alert.addAction(UIAlertAction(title: AccountsL10n.text("切换其他账号"), style: .default) { _ in
                Task { @MainActor in
                    AccountsModule.presentAccountSwitcher(from: presenter)
                }
            })
        }
        alert.addAction(UIAlertAction(title: AccountsL10n.text("稍后再说"), style: .cancel))
        presenter.present(alert, animated: true)
    }

    private static func topMostViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var current = keyWindow?.rootViewController
        while let presented = current?.presentedViewController {
            current = presented
        }
        return current
    }
}
