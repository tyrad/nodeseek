//
//  NotificationViewControllerTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/6/8.
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct NotificationViewControllerTests {
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
    private var markViewedCallValues: [MarkViewedCall] = []

    init(
        unreadCount: NodeSeekNotificationUnreadCount,
        atMeRecords: [NodeSeekNotificationRecord] = [],
        replyRecords: [NodeSeekNotificationRecord] = [],
        messageRecords: [NodeSeekMessageConversationRecord] = [],
        markViewedError: Error? = nil
    ) {
        self.unreadCount = unreadCount
        self.atMeRecords = atMeRecords
        self.replyRecords = replyRecords
        self.messageRecords = messageRecords
        self.markViewedError = markViewedError
    }

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
        atMeRecords
    }

    func loadReplies() async throws -> [NodeSeekNotificationRecord] {
        replyRecords
    }

    func loadMessageConversations() async throws -> [NodeSeekMessageConversationRecord] {
        messageRecords
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
}
