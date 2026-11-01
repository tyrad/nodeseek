//
//  NotificationViewControllerTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/6/8.
//

import Testing
import UIKit
@testable import nodeseek

@Suite(.serialized)
@MainActor
struct NotificationViewControllerTests {
    @Test(arguments: [NodeSeekNotificationTab.atMe, .reply])
    func initialTabSelectsAndLoadsOnlyTarget(tab: NodeSeekNotificationTab) async throws {
        let client = StubNotificationViewClient(unreadCount: .zero)
        let viewController = NotificationViewController(
            initialTab: tab, client: client, currentAccountStore: makeCurrentAccountStore()
        )
        viewController.loadViewIfNeeded()
        let control = try #require(viewController.view.firstSubview(of: UISegmentedControl.self))
        #expect(control.selectedSegmentIndex == tab.rawValue)
        try await waitUntilAsync { await client.loadedTabs().isEmpty == false }
        #expect(await client.loadedTabs() == [tab])
    }

    @Test(arguments: NodeSeekNotificationTab.allCases)
    func switchingToUnloadedTabClearsRowsBeforeScrolling(tab: NodeSeekNotificationTab) async throws {
        let notifications = NotificationLoadQueue<[NodeSeekNotificationRecord]>()
        let messages = NotificationLoadQueue<[NodeSeekMessageConversationRecord]>()
        let records = (0..<80).map { makeNotificationRecord(id: 3_000_000 + $0, viewed: 1) }
        let client = StubNotificationViewClient(
            unreadCount: .zero,
            atMeRecords: records,
            replyRecords: records,
            atMeLoads: tab == .atMe ? notifications : nil,
            replyLoads: tab == .reply ? notifications : nil,
            messageLoads: tab == .message ? messages : nil
        )
        let screen = try makeNotificationScreen(client: client, initialTab: tab == .atMe ? .reply : .atMe)
        defer {
            screen.window.isHidden = true
            Task {
                await notifications.finishAll(returning: [])
                await messages.finishAll(returning: [])
            }
        }
        try await waitUntil { screen.table.numberOfRows(inSection: 0) == 80 }
        screen.window.layoutIfNeeded()
        screen.table.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
        try await Task.sleep(nanoseconds: 100_000_000)

        screen.select(tab)

        #expect(screen.table.numberOfRows(inSection: 0) == 0)
        #expect(screen.controller.tableView(screen.table, numberOfRowsInSection: 0) == 0)
        // 保留真实滚动与预取路径，回归 TestFlight 中的数组越界。
        screen.table.setContentOffset(CGPoint(x: 0, y: 900), animated: true)
        try await Task.sleep(nanoseconds: 400_000_000)
        if tab == .message {
            let id = try await nextLoadID(in: messages)
            await messages.complete(id: id, returning: [])
        } else {
            let id = try await nextLoadID(in: notifications)
            await notifications.complete(id: id, returning: [])
        }
        try await waitUntil { screen.table.backgroundView is UILabel }
        #expect(screen.table.numberOfRows(inSection: 0) == 0)
    }

    @Test(arguments: NodeSeekNotificationTab.allCases)
    func staleCellRequestsAreIgnoredDuringLoadingAndOutsideCurrentRows(tab: NodeSeekNotificationTab) async throws {
        let notifications = NotificationLoadQueue<[NodeSeekNotificationRecord]>()
        let messages = NotificationLoadQueue<[NodeSeekMessageConversationRecord]>()
        let client = StubNotificationViewClient(
            unreadCount: .zero,
            atMeLoads: tab == .atMe ? notifications : nil,
            replyLoads: tab == .reply ? notifications : nil,
            messageLoads: tab == .message ? messages : nil
        )
        let screen = try makeNotificationScreen(client: client, initialTab: tab)
        defer { screen.window.isHidden = true }
        let loadingCell = screen.controller.tableView(screen.table, cellForRowAt: IndexPath(row: 0, section: 0))
        #expect(type(of: loadingCell) == UITableViewCell.self)

        if tab == .message {
            let id = try await nextLoadID(in: messages)
            await messages.complete(id: id, returning: [makeMessageRecord()])
        } else {
            let id = try await nextLoadID(in: notifications)
            await notifications.complete(id: id, returning: [makeNotificationRecord(id: 1, viewed: 1)])
        }
        try await waitUntil { screen.table.numberOfRows(inSection: 0) == 1 }
        let staleCell = screen.controller.tableView(screen.table, cellForRowAt: IndexPath(row: 20, section: 0))
        #expect(type(of: staleCell) == UITableViewCell.self)
        let validCell = screen.controller.tableView(screen.table, cellForRowAt: IndexPath(row: 0, section: 0))
        #expect(type(of: validCell) != UITableViewCell.self)
    }

    @Test func olderRefreshDoesNotReplaceNewerRows() async throws {
        let loads = NotificationLoadQueue<[NodeSeekNotificationRecord]>()
        let client = StubNotificationViewClient(unreadCount: .zero, atMeLoads: loads)
        let screen = try makeNotificationScreen(client: client)
        defer { screen.window.isHidden = true }
        let initial = try await nextLoadID(in: loads)
        await loads.complete(id: initial, returning: [makeNotificationRecord(id: 1, viewed: 1)])
        try await waitUntil { screen.table.numberOfRows(inSection: 0) == 1 }

        screen.refresh()
        let older = try await nextLoadID(in: loads)
        screen.refresh()
        let newer = try await nextLoadID(in: loads, excluding: [older])
        await loads.complete(id: newer, returning: [
            makeNotificationRecord(id: 2, viewed: 1), makeNotificationRecord(id: 3, viewed: 1)
        ])
        try await waitUntil { screen.table.numberOfRows(inSection: 0) == 2 }
        await loads.complete(id: older, returning: [])
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(screen.controller.tableView(screen.table, numberOfRowsInSection: 0) == 2)
        #expect(screen.table.numberOfRows(inSection: 0) == 2)
    }

    @Test func returningToCachedTabDiscardsPendingRefresh() async throws {
        let loads = NotificationLoadQueue<[NodeSeekNotificationRecord]>()
        let client = StubNotificationViewClient(
            unreadCount: .zero, replyRecords: [makeNotificationRecord(id: 2, viewed: 1)], atMeLoads: loads
        )
        let screen = try makeNotificationScreen(client: client)
        defer { screen.window.isHidden = true }
        let initial = try await nextLoadID(in: loads)
        await loads.complete(id: initial, returning: [makeNotificationRecord(id: 1, viewed: 1)])
        try await waitUntil { screen.table.numberOfRows(inSection: 0) == 1 }
        screen.select(.reply)
        try await waitUntil {
            screen.table.numberOfRows(inSection: 0) == 1 && screen.table.backgroundView == nil
        }
        screen.select(.atMe)
        screen.refresh()
        let pending = try await nextLoadID(in: loads)
        screen.select(.reply)
        screen.select(.atMe)
        await loads.complete(id: pending, returning: [])
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(screen.controller.tableView(screen.table, numberOfRowsInSection: 0) == 1)
        #expect(screen.table.numberOfRows(inSection: 0) == 1)
    }

    @Test func obsoleteFailureDoesNotEndCurrentRefresh() async throws {
        let loads = NotificationLoadQueue<[NodeSeekNotificationRecord]>()
        let client = StubNotificationViewClient(unreadCount: .zero, atMeLoads: loads)
        let screen = try makeNotificationScreen(client: client)
        defer { screen.window.isHidden = true }
        let initial = try await nextLoadID(in: loads)
        await loads.complete(id: initial, returning: [makeNotificationRecord(id: 1, viewed: 1)])
        try await waitUntil { screen.table.numberOfRows(inSection: 0) == 1 }
        screen.refresh()
        let older = try await nextLoadID(in: loads)
        screen.refresh()
        let current = try await nextLoadID(in: loads, excluding: [older])
        try #require(screen.table.refreshControl?.isRefreshing == true)
        await loads.fail(id: older)
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(screen.table.refreshControl?.isRefreshing == true)
        #expect(screen.table.numberOfRows(inSection: 0) == 1)
        await loads.complete(id: current, returning: [])
        try await waitUntil { screen.table.backgroundView is UILabel }
        #expect(screen.table.refreshControl?.isRefreshing == false)
        #expect(screen.table.numberOfRows(inSection: 0) == 0)
    }

    @Test func failedSingleMarkReadRestoresUnreadCountAndRowState() async throws {
        let client = StubNotificationViewClient(
            unreadCount: NodeSeekNotificationUnreadCount(message: 0, atMe: 1, reply: 0, all: 1),
            atMeRecords: [makeNotificationRecord(id: 3056861, viewed: 0)],
            markViewedError: URLError(.badServerResponse)
        )
        let viewController = NotificationViewController(client: client, currentAccountStore: makeCurrentAccountStore())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let navigationController = UINavigationController(rootViewController: viewController)
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        viewController.loadViewIfNeeded()
        let tableView = try #require(viewController.view.firstSubview(of: UITableView.self))
        let segmentedControl = try #require(viewController.view.firstSubview(of: UISegmentedControl.self))
        try await waitUntil {
            tableView.numberOfRows(inSection: 0) == 1
                && segmentedControl.titleForSegment(at: NodeSeekNotificationTab.atMe.rawValue) == "@我 1"
        }

        let cell = viewController.tableView(tableView, cellForRowAt: IndexPath(row: 0, section: 0))
        let markReadButton = try #require(cell.firstButton(accessibilityIdentifier: "notification-mark-read-button"))
        #expect(markReadButton.isHidden == false)
        markReadButton.sendActions(for: .touchUpInside)

        try await waitUntilAsync {
            await client.markViewedCallCount() == 1
        }
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(segmentedControl.titleForSegment(at: NodeSeekNotificationTab.atMe.rawValue) == "@我 1")
        let rollbackCell = viewController.tableView(tableView, cellForRowAt: IndexPath(row: 0, section: 0))
        let rollbackButton = try #require(rollbackCell.firstButton(accessibilityIdentifier: "notification-mark-read-button"))
        #expect(rollbackButton.isHidden == false)
    }

    @Test func selectingUnreadMessageConversationMarksMessageViewedBeforeOpeningConversation() async throws {
        let client = StubNotificationViewClient(
            unreadCount: NodeSeekNotificationUnreadCount(message: 1, atMe: 0, reply: 0, all: 1),
            messageRecords: [
                NodeSeekMessageConversationRecord(
                    receiverID: 31037,
                    senderID: 14496,
                    maxID: 920,
                    content: "hello",
                    createdAt: Date(timeIntervalSince1970: 1_000),
                    viewed: 0,
                    senderName: "kiya",
                    receiverName: "mistj"
                )
            ]
        )
        let publishedUnreadCounts = PublishedUnreadCounts()
        let observer = NotificationCenter.default.addObserver(
            forName: .nodeSeekNotificationUnreadCountDidUpdate,
            object: nil,
            queue: .main
        ) { notification in
            guard let unreadCount = NodeSeekNotificationUnreadCountEvent.unreadCount(from: notification) else { return }
            Task { @MainActor in
                publishedUnreadCounts.append(unreadCount)
            }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }
        let viewController = NotificationViewController(client: client, currentAccountStore: makeCurrentAccountStore())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let navigationController = UINavigationController(rootViewController: viewController)
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        viewController.loadViewIfNeeded()
        try await waitUntil {
            publishedUnreadCounts.values.contains(
                NodeSeekNotificationUnreadCount(message: 1, atMe: 0, reply: 0, all: 1)
            )
        }
        let tableView = try #require(viewController.view.firstSubview(of: UITableView.self))
        let segmentedControl = try #require(viewController.view.firstSubview(of: UISegmentedControl.self))
        segmentedControl.selectedSegmentIndex = NodeSeekNotificationTab.message.rawValue
        segmentedControl.sendActions(for: .valueChanged)

        try await waitUntil {
            tableView.numberOfRows(inSection: 0) == 1
                && segmentedControl.titleForSegment(at: NodeSeekNotificationTab.message.rawValue) == "私信 1"
        }

        viewController.tableView(tableView, didSelectRowAt: IndexPath(row: 0, section: 0))

        try await waitUntilAsync {
            await client.markViewedCalls() == [
                StubNotificationViewClient.MarkViewedCall(ids: [920], tab: .message)
            ]
        }
        try await waitUntil {
            segmentedControl.titleForSegment(at: NodeSeekNotificationTab.message.rawValue) == "私信"
        }
        try await waitUntil {
            publishedUnreadCounts.values.last == .zero
        }
        #expect(navigationController.topViewController is NodeSeekWebViewController)
    }
}

@MainActor
private final class PublishedUnreadCounts {
    private(set) var values: [NodeSeekNotificationUnreadCount] = []

    func append(_ unreadCount: NodeSeekNotificationUnreadCount) {
        values.append(unreadCount)
    }
}

private func makeNotificationRecord(id: Int, viewed: Int) -> NodeSeekNotificationRecord {
    NodeSeekNotificationRecord(
        id: id,
        viewed: viewed,
        commentID: 10503771,
        floorID: 11,
        createdAt: Date(timeIntervalSince1970: 1_000),
        commenterID: 24060,
        title: "通知标题",
        postID: 763505,
        firstCommentID: 10501640,
        commenterName: "kiya"
    )
}

private func makeCurrentAccountStore() -> CurrentAccountStore {
    let suiteName = "notification-view-controller-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return CurrentAccountStore(userDefaults: defaults, storageKey: "account")
}

private actor StubNotificationViewClient: NodeSeekNotificationClientProtocol {
    struct MarkViewedCall: Equatable {
        let ids: [Int]
        let tab: NodeSeekNotificationTab
    }

    private var unreadCount: NodeSeekNotificationUnreadCount
    private let atMeRecords: [NodeSeekNotificationRecord]
    private let replyRecords: [NodeSeekNotificationRecord]
    private let messageRecords: [NodeSeekMessageConversationRecord]
    private let markViewedError: Error?
    private let atMeLoads: NotificationLoadQueue<[NodeSeekNotificationRecord]>?
    private let replyLoads: NotificationLoadQueue<[NodeSeekNotificationRecord]>?
    private let messageLoads: NotificationLoadQueue<[NodeSeekMessageConversationRecord]>?
    private var loadedTabValues: [NodeSeekNotificationTab] = []
    private var markViewedCallValues: [MarkViewedCall] = []

    init(
        unreadCount: NodeSeekNotificationUnreadCount,
        atMeRecords: [NodeSeekNotificationRecord] = [],
        replyRecords: [NodeSeekNotificationRecord] = [],
        messageRecords: [NodeSeekMessageConversationRecord] = [],
        markViewedError: Error? = nil,
        atMeLoads: NotificationLoadQueue<[NodeSeekNotificationRecord]>? = nil,
        replyLoads: NotificationLoadQueue<[NodeSeekNotificationRecord]>? = nil,
        messageLoads: NotificationLoadQueue<[NodeSeekMessageConversationRecord]>? = nil
    ) {
        self.unreadCount = unreadCount
        self.atMeRecords = atMeRecords
        self.replyRecords = replyRecords
        self.messageRecords = messageRecords
        self.markViewedError = markViewedError
        self.atMeLoads = atMeLoads
        self.replyLoads = replyLoads
        self.messageLoads = messageLoads
    }

    func loadedTabs() -> [NodeSeekNotificationTab] { loadedTabValues }

    func markViewedCallCount() -> Int {
        markViewedCallValues.count
    }

    func markViewedCalls() -> [MarkViewedCall] {
        markViewedCallValues
    }

    func loadUnreadCount() async throws -> NodeSeekNotificationUnreadCount {
        unreadCount
    }

    func loadAtMe() async throws -> [NodeSeekNotificationRecord] {
        loadedTabValues.append(.atMe)
        if let atMeLoads { return try await atMeLoads.load() }
        return atMeRecords
    }

    func loadReplies() async throws -> [NodeSeekNotificationRecord] {
        loadedTabValues.append(.reply)
        if let replyLoads { return try await replyLoads.load() }
        return replyRecords
    }

    func loadMessageConversations() async throws -> [NodeSeekMessageConversationRecord] {
        loadedTabValues.append(.message)
        if let messageLoads { return try await messageLoads.load() }
        return messageRecords
    }

    func markViewed(ids: [Int], tab: NodeSeekNotificationTab) async throws {
        markViewedCallValues.append(MarkViewedCall(ids: ids, tab: tab))
        if let markViewedError {
            throw markViewedError
        }
        unreadCount.decrement(for: tab, by: ids.count)
    }

    func markAllViewed(tab: NodeSeekNotificationTab) async throws {
        unreadCount.setCount(0, for: tab)
    }
}

private actor NotificationLoadQueue<Value: Sendable> {
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<Value, Error>] = [:]

    func load() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            nextID += 1
            pending[nextID] = continuation
        }
    }

    func pendingIDs() -> Set<Int> { Set(pending.keys) }

    func complete(id: Int, returning value: Value) {
        pending.removeValue(forKey: id)?.resume(returning: value)
    }

    func fail(id: Int) {
        pending.removeValue(forKey: id)?.resume(throwing: URLError(.badServerResponse))
    }

    func finishAll(returning value: Value) {
        let continuations = Array(pending.values)
        pending.removeAll()
        for continuation in continuations { continuation.resume(returning: value) }
    }
}

private func nextLoadID<Value: Sendable>(
    in queue: NotificationLoadQueue<Value>, excluding ids: Set<Int> = []
) async throws -> Int {
    try await waitUntilAsync { await queue.pendingIDs().subtracting(ids).isEmpty == false }
    let pending = await queue.pendingIDs().subtracting(ids)
    return try #require(pending.min())
}

@MainActor
private struct NotificationScreen {
    let window: UIWindow
    let controller: NotificationViewController
    let table: UITableView
    let control: UISegmentedControl

    func select(_ tab: NodeSeekNotificationTab) {
        control.selectedSegmentIndex = tab.rawValue
        control.sendActions(for: .valueChanged)
    }

    func refresh() {
        window.layoutIfNeeded()
        table.setContentOffset(
            CGPoint(x: 0, y: -table.adjustedContentInset.top - 100), animated: false
        )
        table.refreshControl?.beginRefreshing()
        table.refreshControl?.sendActions(for: .valueChanged)
    }
}

@MainActor
private func makeNotificationScreen(
    client: NodeSeekNotificationClientProtocol, initialTab: NodeSeekNotificationTab = .atMe
) throws -> NotificationScreen {
    let controller = NotificationViewController(
        initialTab: initialTab, client: client, currentAccountStore: makeCurrentAccountStore()
    )
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
    window.rootViewController = UINavigationController(rootViewController: controller)
    window.makeKeyAndVisible()
    controller.loadViewIfNeeded()
    window.layoutIfNeeded()
    let table = try #require(controller.view.firstSubview(of: UITableView.self))
    let control = try #require(controller.view.firstSubview(of: UISegmentedControl.self))
    return NotificationScreen(window: window, controller: controller, table: table, control: control)
}

private func makeMessageRecord() -> NodeSeekMessageConversationRecord {
    NodeSeekMessageConversationRecord(
        receiverID: 31037, senderID: 14496, maxID: 920, content: "hello",
        createdAt: Date(timeIntervalSince1970: 1_000), viewed: 1, senderName: "kiya", receiverName: "mistj"
    )
}

private extension UIView {
    func firstSubview<View: UIView>(of type: View.Type) -> View? {
        if let view = self as? View {
            return view
        }
        for subview in subviews {
            if let match = subview.firstSubview(of: type) {
                return match
            }
        }
        return nil
    }

    func firstButton(accessibilityIdentifier: String) -> UIButton? {
        if let button = self as? UIButton, button.accessibilityIdentifier == accessibilityIdentifier {
            return button
        }
        for subview in subviews {
            if let match = subview.firstButton(accessibilityIdentifier: accessibilityIdentifier) {
                return match
            }
        }
        return nil
    }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @escaping @MainActor () -> Bool
) async throws {
    let step: UInt64 = 25_000_000
    var waited: UInt64 = 0
    while waited < timeoutNanoseconds {
        if condition() {
            return
        }
        try await Task.sleep(nanoseconds: step)
        waited += step
    }
    throw NotificationTestError.timedOut
}

private func waitUntilAsync(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @escaping () async -> Bool
) async throws {
    let step: UInt64 = 25_000_000
    var waited: UInt64 = 0
    while waited < timeoutNanoseconds {
        if await condition() {
            return
        }
        try await Task.sleep(nanoseconds: step)
        waited += step
    }
    throw NotificationTestError.timedOut
}

private enum NotificationTestError: Error {
    case timedOut
}
