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
/// 本身放在外层导航栈里：进入二级页面时连同底栏一起被推走，不用 hidesBottomBarWhenPushed 单独收起底栏。
final class MainTabBarController: UITabBarController, UITabBarControllerDelegate {
    private let layoutSettings: AppNavigationLayoutSettings
    private let visitedStore: VisitedPostStoreProtocol
    private var unreadCountObserver: NSObjectProtocol?
    private var tabItemsObserver: NSObjectProtocol?
    private var latestUnreadCount: NodeSeekNotificationUnreadCount?
    /// 已建好的 Tab 根页面，底部栏调整时复用，避免正在看的页面被重建。
    private var rootViewControllersByItem: [MainTabItem: UIViewController] = [:]
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        syncNavigationItemWithSelectedTab()
    }

    func select(_ item: MainTabItem) {
        guard let index = tabItems.firstIndex(of: item) else { return }
        selectedIndex = index
        syncNavigationItemWithSelectedTab()
    }

    func applyNotificationUnreadCount(_ unreadCount: NodeSeekNotificationUnreadCount) {
        latestUnreadCount = unreadCount
        // 通知 Tab 被关掉时不显示角标
        guard let item = rootViewControllersByItem[.notification]?.tabBarItem else { return }
        let count = unreadCount.all
        item.badgeValue = count > 0 ? (count > 99 ? "99+" : "\(count)") : nil
    }

    /// 按新的底部栏重排 Tab；保留已有导航栈和当前选中项。
    func applyTabItems(_ items: [MainTabItem]) {
        let items = MainTabItem.normalized(items)
        guard items != tabItems else { return }
        let selectedItem = tabItems.indices.contains(selectedIndex) ? tabItems[selectedIndex] : nil
        tabItems = items

        var reused: [MainTabItem: UIViewController] = [:]
        let controllers = items.map { item -> UIViewController in
            let viewController = rootViewControllersByItem[item] ?? makeTabRootViewController(for: item)
            reused[item] = viewController
            return viewController
        }
        rootViewControllersByItem = reused
        setViewControllers(controllers, animated: false)
        if let selectedItem, let index = items.firstIndex(of: selectedItem) {
            selectedIndex = index
        }
        syncNavigationItemWithSelectedTab()
        if let latestUnreadCount {
            applyNotificationUnreadCount(latestUnreadCount)
        }
    }

    // MARK: - UITabBarControllerDelegate

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        // 底栏只在 Tab 界面位于栈顶时可见，所以不用再判断是否在二级页面
        if viewController === selectedViewController, let root = viewController as? TabReselectHandling {
            root.handleTabReselect()
        }
        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        syncNavigationItemWithSelectedTab()
    }

    // MARK: - Private

    /// 外层导航条显示的是本控制器的 navigationItem；各 Tab 根页面仍按原样配置自己的 navigationItem，
    /// 切 Tab 时搬过来，页面代码不用区分两种布局。
    private func syncNavigationItemWithSelectedTab() {
        guard let selected = selectedViewController else { return }
        selected.loadViewIfNeeded()
        let source = selected.navigationItem
        navigationItem.title = source.title ?? selected.title
        navigationItem.titleView = source.titleView
        navigationItem.leftBarButtonItems = source.leftBarButtonItems
        navigationItem.rightBarButtonItems = source.rightBarButtonItems
        navigationItem.largeTitleDisplayMode = source.largeTitleDisplayMode
        navigationItem.backButtonTitle = source.backButtonTitle
        navigationItem.backBarButtonItem = source.backBarButtonItem
        navigationItem.backButtonDisplayMode = source.backButtonDisplayMode
    }

    private func makeTabRootViewController(for item: MainTabItem) -> UIViewController {
        let viewController = makeRootViewController(for: item)
        viewController.tabBarItem = UITabBarItem(
            title: item.title,
            image: UIImage(systemName: item.symbolName),
            selectedImage: UIImage(systemName: "\(item.symbolName).fill") ?? UIImage(systemName: item.symbolName)
        )
        viewController.tabBarItem.accessibilityIdentifier = item.accessibilityIdentifier
        return viewController
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
