import UIKit

@MainActor
enum UserAvatarMenu {
    private static var pendingFollows: Set<Int> = []
    private static var pendingChanges: Set<Int> = []

    /// 在长按时固定目标和展示页，列表项复用后也不会操作另一位作者。
    static func avatarConfiguration(url: URL, name: String, source: UIView,
                                    followAction: UIAction? = nil) -> UIContextMenuConfiguration {
        let presenter = sequence(first: source as UIResponder, next: { $0.next })
            .lazy.compactMap { $0 as? UIViewController }.first
        return UIContextMenuConfiguration(identifier: nil, previewProvider: {
            UserProfileRouter.makeViewController(profileURL: url)
        }) { [weak presenter] _ in
            guard let presenter, let uid = UserProfileRouter.nativeUID(for: url),
                  let name = AuthorDisplayPolicy.displayName(from: name) else { return nil }
            return UIMenu(children: [element(for: BlockedMember(id: uid, name: name), presenter: presenter,
                                             client: NodeSeekUserContentClient(), followAction: followAction)])
        }
    }

    static func element(for member: BlockedMember, presenter: UIViewController,
                        client: NodeSeekUserContentClient,
                        accountStore: CurrentAccountStore = .shared, followAction: UIAction? = nil) -> UIDeferredMenuElement {
        .uncached { [weak presenter] complete in
            Task { @MainActor in
                guard let presenter, let account = await accountStore.snapshot()?.account,
                      account.isLoggedIn, let accountID = account.nodeSeekUID, accountID != member.id else { return complete([]) }
                async let follow = resolveFollowAction(followAction, member: member, client: client, presenter: presenter)
                let message = UIAction(title: UserContentL10n.text("私信"), image: UIImage(systemName: "bubble.left")) { [weak presenter] _ in
                    guard let presenter else { return }
                    openMessage(to: member.id, from: presenter)
                }
                let block = await blockAction(for: member, accountID: accountID, client: client, presenter: presenter)
                complete([await follow, message, block])
            }
        }
    }

    static func followAction(followed: Bool, busy: Bool = false, perform: @escaping () -> Void) -> UIAction {
        UIAction(title: UserContentL10n.text(followed ? "取消关注" : "关注"),
                 image: UIImage(systemName: followed ? "person.badge.minus" : "person.badge.plus"),
                 attributes: busy ? .disabled : []) { _ in perform() }
    }

    private static func resolveFollowAction(_ existing: UIAction?, member: BlockedMember, client: NodeSeekUserContentClient,
                                            presenter: UIViewController) async -> UIAction {
        if let existing { return existing }
        do {
            let followed = try await client.loadProfile(uid: member.id).followed
            return followAction(followed: followed, busy: pendingFollows.contains(member.id)) { [weak presenter] in
                guard let presenter else { return }
                let update: () -> Void = {
                    Task { @MainActor in
                        guard pendingFollows.insert(member.id).inserted else { return }
                        defer { pendingFollows.remove(member.id) }
                        do {
                            try await client.setFollowing(!followed, uid: member.id)
                            BottomToast.show(UserContentL10n.text(followed ? "已取消关注" : "已关注"), in: presenter.view)
                        } catch {
                            BottomToast.show(error.localizedDescription, style: .failure, in: presenter.view)
                        }
                    }
                }
                if followed {
                    confirmUnfollow(member.name, from: presenter, source: presenter.view, completion: update)
                } else {
                    update()
                }
            }
        } catch {
            return UIAction(title: UserContentL10n.text("关注"), subtitle: error.localizedDescription,
                            attributes: .disabled) { _ in }
        }
    }

    static func confirmUnfollow(_ name: String, from presenter: UIViewController, source: UIView,
                                completion: @escaping () -> Void) {
        let title = String(format: UserContentL10n.text("不再关注「%@」？"), name)
        let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: UserContentL10n.text("取消关注"), style: .destructive) { _ in completion() })
        sheet.addAction(UIAlertAction(title: AccountsL10n.text("取消"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = source
        sheet.popoverPresentationController?.sourceRect = CGRect(x: source.bounds.midX, y: source.bounds.midY, width: 1, height: 1)
        presenter.present(sheet, animated: true)
    }

    static func openMessage(to uid: Int, from presenter: UIViewController) {
        let url = NodeSeekNotificationURLBuilder.webURL(fragment: "/message?mode=talk&to=\(uid)")
        presenter.navigationController?.pushViewController(NodeSeekWebViewController(url: url), animated: true)
    }

    private static func blockAction(for member: BlockedMember, accountID: Int, client: NodeSeekUserContentClient,
                                    presenter: UIViewController) async -> UIAction {
        do {
            let blocked = try await client.isBlocked(member.id, for: accountID)
            return UIAction(
                title: AccountsL10n.text(blocked ? "解除拉黑" : "拉黑用户"),
                image: UIImage(systemName: blocked ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.minus"),
                attributes: blocked ? [] : .destructive
            ) { [weak presenter] _ in
                guard let presenter else { return }
                confirm(!blocked, member: member, accountID: accountID, client: client, presenter: presenter)
            }
        } catch {
            return UIAction(title: AccountsL10n.text("黑名单加载失败"), subtitle: error.localizedDescription,
                            attributes: .disabled) { _ in }
        }
    }

    static func confirm(_ blocked: Bool, member: BlockedMember, accountID: Int,
                        client: NodeSeekUserContentClient, presenter: UIViewController) {
        guard !pendingChanges.contains(member.id) else { return }
        presenter.confirmBlockChange(blocked, member: member) {
            Task { await update(blocked, member: member, accountID: accountID, client: client, presenter: presenter) }
        }
    }

    private static func update(_ blocked: Bool, member: BlockedMember, accountID: Int, client: NodeSeekUserContentClient,
                               presenter: UIViewController) async {
        guard pendingChanges.insert(member.id).inserted else { return }
        let progress = BottomToast.show(AccountsL10n.text(blocked ? "正在拉黑…" : "正在解除拉黑…"),
                                        style: .progress, in: presenter.view, duration: 60)
        defer {
            pendingChanges.remove(member.id)
            BottomToast.dismiss(progress)
        }
        do {
            try await client.setBlocked(blocked, member: member, for: accountID)
            let message = blocked ? "拉黑成功（%@），手动刷新帖子后生效。" : "解除拉黑成功（%@），手动刷新帖子后生效。"
            BottomToast.show(AccountsL10n.format(message, member.name), in: presenter.view, duration: 4)
        } catch {
            BottomToast.show(error.localizedDescription, style: .failure, in: presenter.view)
        }
    }
}
