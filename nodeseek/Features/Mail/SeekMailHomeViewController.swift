//
//  SeekMailHomeViewController.swift
//  nodeseek
//

import SafariServices
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
        title = "邮箱"
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
            inbox.onUnauthorized = { [weak self] in
                self?.pendingBindMessage = "之前保存的 Key 已失效，请重新粘贴"
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

    private func configureNavigationItems(bound: Bool) {
        // 作为 Tab 根页面时，导航栏按钮要同步到外层导航栏
        defer {
            if let tabs = parent as? MainTabBarController, tabs.selectedViewController === self {
                tabs.syncNavigationItemWithSelectedTab()
            }
        }
        guard bound else {
            navigationItem.rightBarButtonItems = []
            navigationItem.titleView = nil
            return
        }
        if let inbox = content as? SeekMailInboxViewController {
            navigationItem.titleView = inbox.titleButton
        }
        let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: makeMoreMenu())
        more.accessibilityLabel = "更多"
        more.accessibilityIdentifier = "seek-mail-more"
        var items = [more]
        if let inbox = content as? SeekMailInboxViewController, inbox.model.canCompose {
            let compose = UIBarButtonItem(image: UIImage(systemName: "square.and.pencil"), primaryAction: UIAction { [weak inbox] _ in
                inbox?.presentCompose()
            })
            compose.accessibilityLabel = "写信"
            compose.accessibilityIdentifier = "seek-mail-compose"
            items.append(compose)
        }
        navigationItem.rightBarButtonItems = items
    }

    private func makeMoreMenu() -> UIMenu {
        let manage = UIAction(title: "在网页中管理", image: UIImage(systemName: "safari")) { [weak self] _ in
            self?.present(SFSafariViewController(url: SeekMailLinks.manage), animated: true)
        }
        let replace = UIAction(title: "更换 API Key", image: UIImage(systemName: "key")) { [weak self] _ in
            self?.showReplaceKey()
        }
        let remove = UIAction(title: "移除 Key 并退出", image: UIImage(systemName: "rectangle.portrait.and.arrow.right"),
                              attributes: .destructive) { [weak self] _ in
            self?.confirmRemoveKey()
        }
        let inboxItems = (content as? SeekMailInboxViewController)?.menuElements() ?? []
        return UIMenu(children: [
            UIMenu(options: .displayInline, children: inboxItems),
            UIMenu(options: .displayInline, children: [manage]),
            UIMenu(options: .displayInline, children: [replace, remove])
        ])
    }

    /// 新 Key 验证通过才替换旧 Key，验证失败时旧 Key 继续可用。
    private func showReplaceKey() {
        let bind = SeekMailBindViewController(keyStore: keyStore, onBound: { [weak self] _ in
            guard let self else { return }
            navigationController?.popToViewController(self.navigationAnchor, animated: true)
        })
        bind.title = "更换 API Key"
        navigationController?.pushViewController(bind, animated: true)
    }

    /// 作为 Tab 根页面时，导航栈里的是外层 MainTabBarController。
    private var navigationAnchor: UIViewController {
        parent is MainTabBarController ? parent! : self
    }

    private func confirmRemoveKey() {
        let alert = UIAlertController(
            title: "移除 API Key？",
            message: "本机保存的 Key 会被删除，邮箱数据不受影响。之后需要重新粘贴 Key 才能查看邮件。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "移除", style: .destructive) { [weak self] _ in
            // 记住的邮箱属于旧账号，一起清掉
            self?.selectionStore.clear()
            self?.cache?.clear()
            self?.memoryCache?.clear()
            self?.keyStore.clear()
        })
        present(alert, animated: true)
    }
}
