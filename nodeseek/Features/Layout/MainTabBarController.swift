//
//  MainTabBarController.swift
//  nodeseek
//

import UIKit

/// Tab 根页面在已选中时再次点按 Tab 的处理，例如回到顶部。
protocol TabReselectHandling: AnyObject {
    func handleTabReselect()
}

/// 多 Tab 模式的根界面：默认首页 / 通知 / 我的，用户可在设置里增减中间的入口。
final class MainTabBarController: UITabBarController, UITabBarControllerDelegate {
    private let layoutSettings: AppNavigationLayoutSettings
    private let visitedStore: VisitedPostStoreProtocol
    private var unreadCountObserver: NSObjectProtocol?
    private var tabItemsObserver: NSObjectProtocol?
    private var latestUnreadCount: NodeSeekNotificationUnreadCount?
    /// 已建好的 Tab 导航栈，底部栏调整时复用，避免正在看的页面被重建。
    private var navigationControllersByItem: [MainTabItem: UINavigationController] = [:]
    private(set) var tabItems: [MainTabItem] = []

    init(
        layoutSettings: AppNavigationLayoutSettings = .shared,
        visitedStore: VisitedPostStoreProtocol? = nil
    ) {
        self.layoutSettings = layoutSettings
        self.visitedStore = visitedStore ?? VisitedPostStore.shared
        super.init(nibName: nil, bundle: nil)
        delegate = self
        applyTabItems(layoutSettings.tabItems)
        observeTabItems()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let unreadCountObserver {
            NotificationCenter.default.removeObserver(unreadCountObserver)
        }
        if let tabItemsObserver {
            NotificationCenter.default.removeObserver(tabItemsObserver)
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

    func select(_ item: MainTabItem) {
        guard let index = tabItems.firstIndex(of: item) else { return }
        selectedIndex = index
    }

    func applyNotificationUnreadCount(_ unreadCount: NodeSeekNotificationUnreadCount) {
        latestUnreadCount = unreadCount
        // 通知 Tab 被关掉时不显示角标
        guard let item = navigationControllersByItem[.notification]?.tabBarItem else { return }
        let count = unreadCount.all
        item.badgeValue = count > 0 ? (count > 99 ? "99+" : "\(count)") : nil
    }

    /// 按新的底部栏重排 Tab；保留已有导航栈和当前选中项。
    func applyTabItems(_ items: [MainTabItem]) {
        let items = MainTabItem.normalized(items)
        guard items != tabItems else { return }
        let selectedItem = tabItems.indices.contains(selectedIndex) ? tabItems[selectedIndex] : nil
        tabItems = items

        var reused: [MainTabItem: UINavigationController] = [:]
        let controllers = items.map { item -> UINavigationController in
            let navigationController = navigationControllersByItem[item] ?? makeNavigationController(for: item)
            reused[item] = navigationController
            return navigationController
        }
        navigationControllersByItem = reused
        setViewControllers(controllers, animated: false)
        if let selectedItem, let index = items.firstIndex(of: selectedItem) {
            selectedIndex = index
        }
        if let latestUnreadCount {
            applyNotificationUnreadCount(latestUnreadCount)
        }
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

    private func makeNavigationController(for item: MainTabItem) -> UINavigationController {
        let navigationController = TabRootNavigationController(rootViewController: makeRootViewController(for: item))
        navigationController.tabBarItem = UITabBarItem(
            title: item.title,
            image: UIImage(systemName: item.symbolName),
            selectedImage: UIImage(systemName: "\(item.symbolName).fill") ?? UIImage(systemName: item.symbolName)
        )
        navigationController.tabBarItem.accessibilityIdentifier = item.accessibilityIdentifier
        return navigationController
    }

    /// 新加的 Tab 直接复用现有页面，点开帖子时在本 Tab 的导航栈里打开详情。
    private func makeRootViewController(for item: MainTabItem) -> UIViewController {
        switch item {
        case .home:
            return PostListRouter.createModule(layout: .tabs)
        case .notification:
            return NotificationViewController()
        case .me:
            return MeViewController()
        case .search:
            return SearchViewController()
        case .recent:
            let viewController = RecentVisitedPostsViewController(visitedStore: visitedStore)
            viewController.reloadsOnAppear = true
            viewController.onSelectRecord = { [weak viewController] record in
                Self.pushPostDetail(post: PostListRouter.postSummary(from: record), page: 1, anchorID: nil, from: viewController)
            }
            return viewController
        case .discussions:
            let viewController = UserDiscussionsViewController(title: item.title)
            viewController.onSelectPost = { [weak viewController] post, page, anchorID in
                Self.pushPostDetail(post: post, page: page, anchorID: anchorID, from: viewController)
            }
            return viewController
        case .collections:
            let viewController = UserCollectionsViewController(title: item.title)
            viewController.onSelectPost = { [weak viewController] post, page, anchorID in
                Self.pushPostDetail(post: post, page: page, anchorID: anchorID, from: viewController)
            }
            return viewController
        case .comments:
            let viewController = UserCommentsViewController(title: item.title)
            viewController.onSelectPost = { [weak viewController] post, page, anchorID in
                Self.pushPostDetail(post: post, page: page, anchorID: anchorID, from: viewController)
            }
            return viewController
        }
    }

    private static func pushPostDetail(post: PostSummary, page: Int, anchorID: String?, from source: UIViewController?) {
        let detailViewController = PostDetailRouter.createModule(post: post, page: page, initialAnchorID: anchorID)
        source?.navigationController?.pushViewController(detailViewController, animated: true)
    }

    private func observeTabItems() {
        tabItemsObserver = NotificationCenter.default.addObserver(
            forName: AppNavigationLayoutSettings.tabItemsDidChangeNotification,
            object: layoutSettings,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.applyTabItems(self.layoutSettings.tabItems)
        }
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
