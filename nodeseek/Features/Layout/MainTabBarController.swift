//
//  MainTabBarController.swift
//  nodeseek
//

import UIKit

/// Tab 根页面在已选中时再次点按 Tab 的处理，例如回到顶部。
protocol TabReselectHandling: AnyObject {
    func handleTabReselect()
}

/// 多 Tab 模式的根界面：首页 / 通知 / 我的。
final class MainTabBarController: UITabBarController, UITabBarControllerDelegate {
    enum Tab: Int {
        case home
        case notification
        case me
    }

    private var unreadCountObserver: NSObjectProtocol?

    init() {
        super.init(nibName: nil, bundle: nil)
        viewControllers = [
            Self.makeTab(
                root: PostListRouter.createModule(layout: .tabs),
                title: "首页",
                symbolName: "house",
                identifier: "main-tab-home"
            ),
            Self.makeTab(
                root: NotificationViewController(),
                title: "通知",
                symbolName: "bell",
                identifier: "main-tab-notification"
            ),
            Self.makeTab(
                root: MeViewController(),
                title: "我的",
                symbolName: "person",
                identifier: "main-tab-me"
            )
        ]
        delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let unreadCountObserver {
            NotificationCenter.default.removeObserver(unreadCountObserver)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 黑白主题：选中用文字色，未选中用次级文字色
        tabBar.tintColor = .label
        tabBar.unselectedItemTintColor = .secondaryLabel
        observeNotificationUnreadCount()
    }

    var selectedNavigationController: UINavigationController? {
        selectedViewController as? UINavigationController
    }

    func select(_ tab: Tab) {
        selectedIndex = tab.rawValue
    }

    func applyNotificationUnreadCount(_ unreadCount: NodeSeekNotificationUnreadCount) {
        guard let item = viewControllers?[Tab.notification.rawValue].tabBarItem else { return }
        let count = unreadCount.all
        item.badgeValue = count > 0 ? (count > 99 ? "99+" : "\(count)") : nil
    }

    // MARK: - UITabBarControllerDelegate

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if viewController === selectedViewController,
           let navigationController = viewController as? UINavigationController,
           navigationController.viewControllers.count == 1,
           let root = navigationController.viewControllers.first as? TabReselectHandling {
            root.handleTabReselect()
        }
        return true
    }

    // MARK: - Private

    private static func makeTab(
        root: UIViewController,
        title: String,
        symbolName: String,
        identifier: String
    ) -> UINavigationController {
        let navigationController = TabRootNavigationController(rootViewController: root)
        navigationController.tabBarItem = UITabBarItem(
            title: title,
            image: UIImage(systemName: symbolName),
            selectedImage: UIImage(systemName: "\(symbolName).fill")
        )
        navigationController.tabBarItem.accessibilityIdentifier = identifier
        return navigationController
    }

    private func observeNotificationUnreadCount() {
        guard unreadCountObserver == nil else { return }
        unreadCountObserver = NotificationCenter.default.addObserver(
            forName: .nodeSeekNotificationUnreadCountDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let unreadCount = NodeSeekNotificationUnreadCountEvent.unreadCount(from: notification) else { return }
            self?.applyNotificationUnreadCount(unreadCount)
        }
    }
}

/// Tab 内的导航栈：进入二级页面时隐藏底栏。
final class TabRootNavigationController: UINavigationController {
    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        if viewControllers.isEmpty == false {
            viewController.hidesBottomBarWhenPushed = true
        }
        super.pushViewController(viewController, animated: animated)
    }
}
