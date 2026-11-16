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

    /// transport 只在测试里替换，正常使用走 URLSession。
    init(keyStore: SeekMailAPIKeyStoring = SeekMailAPIKeyStore.shared,
         transport: SeekMailProvider<SeekMailAPI>.Transport? = nil) {
        self.keyStore = keyStore
        self.transport = transport
        super.init(nibName: nil, bundle: nil)
        title = "邮箱"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyDidChange),
            name: SeekMailAPIKeyStore.didChangeNotification, object: nil
        )
        render()
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
            let inbox = SeekMailInboxViewController(keyStore: keyStore, transport: transport)
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
            return
        }
        let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: makeMoreMenu())
        more.accessibilityLabel = "更多"
        more.accessibilityIdentifier = "seek-mail-more"
        navigationItem.rightBarButtonItems = [more]
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
        return UIMenu(children: [
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
            self?.keyStore.clear()
        })
        present(alert, animated: true)
    }
}

/// 已绑定时的邮件页。第 2 步只显示连接状态，邮件列表在下一步实现。
final class SeekMailInboxViewController: UIViewController {
    private let keyStore: SeekMailAPIKeyStoring
    /// Key 已在网页上删除或失效（401）时回调，由入口页清掉 Key 并回到绑定页。
    var onUnauthorized: (() -> Void)?
    private let provider: SeekMailProvider<SeekMailAPI>
    private var loadTask: Task<Void, Never>?

    private let stack = UIStackView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    init(keyStore: SeekMailAPIKeyStoring, transport: SeekMailProvider<SeekMailAPI>.Transport? = nil) {
        self.keyStore = keyStore
        if let transport {
            provider = SeekMailProvider(apiKey: { [keyStore] in keyStore.apiKey() }, transport: transport)
        } else {
            provider = SeekMailProvider(apiKey: { [keyStore] in keyStore.apiKey() })
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { loadTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let icon = UIImageView(image: UIImage(systemName: "envelope.badge"))
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40, weight: .light)
        icon.tintColor = .tertiaryLabel
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0
        detailLabel.accessibilityIdentifier = "seek-mail-inbox-detail"
        [icon, titleLabel, detailLabel, spinner].forEach(stack.addArrangedSubview)
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -16)
        ])
        load()
    }

    private func load() {
        titleLabel.text = "已连接 seek.li 邮箱"
        detailLabel.text = nil
        spinner.startAnimating()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let mailboxes = try await provider.mailboxes()
                spinner.stopAnimating()
                detailLabel.text = "共 \(mailboxes.count) 个邮箱"
            } catch is CancellationError {
            } catch let error as SeekMailError {
                spinner.stopAnimating()
                if case .unauthorized = error {
                    onUnauthorized?()
                    return
                }
                detailLabel.text = error.userMessage
            } catch {
                spinner.stopAnimating()
                detailLabel.text = "加载失败，请稍后重试"
            }
        }
    }
}
