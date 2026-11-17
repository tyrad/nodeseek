//
//  SeekMailHomeViewController.swift
//  nodeseek
//

import UIKit

/// 邮箱入口：没有 Key 时显示绑定页，有 Key 时显示邮件页；Key 变化时自动切换。
/// 「我的」、侧边栏和底部栏都打开这一页。
final class SeekMailHomeViewController: UIViewController {
    private let keyStore: SeekMailAPIKeyStoring
    private let transport: SeekMailProvider<SeekMailAPI>.Transport?
    private var content: UIViewController?
    /// 当前邮件页用的 Key；更换 Key 后要用新 Key 重新加载。
    private var shownKey: String?
    /// Key 失效被清掉时，回到绑定页要说明原因。
    private var pendingBindMessage: String?
    private let selectionStore: SeekMailSelectionStore
    private let cache: SeekMailListCache?
    private let memoryCache: SeekMailMemoryCache?

    /// transport 只在测试里替换，正常使用走 URLSession。
    init(keyStore: SeekMailAPIKeyStoring = SeekMailAPIKeyStore.shared,
         transport: SeekMailProvider<SeekMailAPI>.Transport? = nil,
         selectionStore: SeekMailSelectionStore = SeekMailSelectionStore(),
         cache: SeekMailListCache? = SeekMailListCache(),
         memoryCache: SeekMailMemoryCache? = .shared) {
        self.keyStore = keyStore
        self.transport = transport
        self.selectionStore = selectionStore
        self.cache = cache
        self.memoryCache = memoryCache
        super.init(nibName: nil, bundle: nil)
        title = SeekMailL10n.text("邮箱")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        // 搜索框挂在导航栏上，结果直接显示在本页
        definesPresentationContext = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyDidChange),
            name: SeekMailAPIKeyStore.didChangeNotification, object: nil
        )
        render()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 刚读过邮件，离开时让入口的未读数跟上
        if isMovingFromParent || navigationController?.isBeingDismissed == true {
            SeekMailUnreadMonitor.shared.check(force: true)
        }
    }

    @objc private func keyDidChange() {
        render()
    }

    private func render() {
        let key = keyStore.apiKey()
        if let key, content is SeekMailInboxViewController, key == shownKey { return }
        if key == nil, content is SeekMailBindViewController { return }

        shownKey = key
        let next: UIViewController
        if key != nil {
            let inbox = SeekMailInboxViewController(keyStore: keyStore, transport: transport,
                                                    selectionStore: selectionStore, cache: cache, memoryCache: memoryCache)
            inbox.onNavigationChange = { [weak self] in self?.configureNavigationItems(bound: true) }
            inbox.onOpenSettings = { [weak self] in self?.showSettings() }
            inbox.onUnauthorized = { [weak self] in
                self?.pendingBindMessage = SeekMailL10n.text("之前保存的 Key 已失效，请重新粘贴")
                self?.keyStore.clear()
            }
            next = inbox
        } else {
            let bind = SeekMailBindViewController(keyStore: keyStore)
            bind.initialErrorMessage = pendingBindMessage
            pendingBindMessage = nil
            next = bind
        }
        replaceContent(with: next)
        configureNavigationItems(bound: key != nil)
    }

    private func replaceContent(with next: UIViewController) {
        if let content {
            content.willMove(toParent: nil)
            content.view.removeFromSuperview()
            content.removeFromParent()
        }
        addChild(next)
        next.view.frame = view.bounds
        next.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(next.view)
        next.didMove(toParent: self)
        content = next
    }

    private weak var navigationInbox: SeekMailInboxViewController?
    private var navigationCanCompose: Bool?

    private func configureNavigationItems(bound: Bool) {
        let inbox = content as? SeekMailInboxViewController
        let canCompose = inbox?.model.canCompose
        // 未读数变化不影响导航操作，复用按钮以免系统重复过渡。
        if bound, let inbox, navigationInbox === inbox, navigationCanCompose == canCompose { return }
        navigationInbox = bound ? inbox : nil
        navigationCanCompose = bound ? canCompose : nil
        // 作为 Tab 根页面时，导航栏按钮要同步到外层导航栏
        defer {
            if let tabs = parent as? MainTabBarController, tabs.selectedViewController === self {
                tabs.syncNavigationItemWithSelectedTab()
            }
        }
        guard bound else {
            navigationItem.rightBarButtonItems = []
            return
        }
        // 设置入口在邮箱标签行，导航栏保留搜索和写信
        var items: [UIBarButtonItem] = []
        if let inbox = content as? SeekMailInboxViewController, inbox.model.canCompose {
            let compose = UIBarButtonItem(image: UIImage(systemName: "square.and.pencil"), primaryAction: UIAction { [weak inbox] _ in
                inbox?.presentCompose()
            })
            compose.accessibilityLabel = SeekMailL10n.text("写信")
            compose.accessibilityIdentifier = "seek-mail-compose"
            items.append(compose)
        }
        if let inbox = content as? SeekMailInboxViewController {
            let search = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), primaryAction: UIAction { [weak inbox] _ in
                inbox?.showSearch()
            })
            search.accessibilityLabel = NSLocalizedString("搜索", tableName: "Search", comment: "")
            search.accessibilityIdentifier = "seek-mail-search-button"
            items.append(search)
        }
        navigationItem.rightBarButtonItems = items
    }

    private func showSettings() {
        guard let inbox = content as? SeekMailInboxViewController else { return }
        let actions = SeekMailSettingsViewController.Actions(
            makeCreateMailbox: { [weak inbox] onCreated in
                inbox?.makeCreateMailboxController(onCreated: onCreated) ?? UIViewController()
            },
            replaceKey: { [weak self] in self?.showReplaceKey() },
            removeKey: { [weak self] in self?.removeKey() }
        )
        let settings = SeekMailSettingsViewController(selectionStore: selectionStore, provider: inbox.model.provider, actions: actions)
        navigationController?.pushViewController(settings, animated: true)
    }

    /// 新 Key 验证通过才替换旧 Key，验证失败时旧 Key 继续可用。
    private func showReplaceKey() {
        let bind = SeekMailBindViewController(keyStore: keyStore, onBound: { [weak self] _ in
            guard let self else { return }
            navigationController?.popToViewController(self.navigationAnchor, animated: true)
        })
        bind.title = SeekMailL10n.text("更换 API Key")
        navigationController?.pushViewController(bind, animated: true)
    }

    /// 作为 Tab 根页面时，导航栈里的是外层 MainTabBarController。
    private var navigationAnchor: UIViewController {
        parent is MainTabBarController ? parent! : self
    }

    /// 设置页确认后调用：记住的邮箱属于旧账号，一起清掉，再回到邮箱页显示绑定页。
    private func removeKey() {
        navigationController?.popToViewController(navigationAnchor, animated: true)
        selectionStore.clear()
        cache?.clear()
        memoryCache?.clear()
        keyStore.clear()
    }
}
