import Foundation
import Testing
import UIKit
@testable import nodeseek

/// 写信、新邮件提醒、列表缓存。地址都是假值。
@MainActor
struct SeekMailP1Tests {
    // MARK: - 写信内容

    @Test func parsesRecipientsAndValidates() {
        #expect(SeekMailComposeContent.addresses(from: " a@x.com, b@y.org；c@z.io\nd@w.net ") == ["a@x.com", "b@y.org", "c@z.io", "d@w.net"])
        var content = SeekMailComposeContent(mailboxID: 1, to: "a@x.com", subject: "Hi")
        #expect(content.problem == nil)
        #expect(content.draft == SeekMailDraft(mailboxID: 1, to: ["a@x.com"], subject: "Hi", bodyText: ""))
        content.cc = "bad-address"
        #expect(content.problem == .invalidAddress("bad-address"))
        content.cc = ""
        content.subject = " "
        #expect(content.problem == .emptyContent)
        content.to = ""
        #expect(content.problem == .noRecipient)
        #expect(SeekMailComposeContent(to: "a@x.com", subject: "s").problem == .noSender)
    }

    @Test func replyPrefillsRecipientSubjectQuoteAndSender() throws {
        let mailboxes = try decode([SeekMailbox].self, #"[{"id":1,"address":"me@nodeseek.org"},{"id":2,"address":"me@seek.li"}]"#)
        let mail = try decode(SeekMail.self, #"{"id":9,"mailboxId":1,"fromAddress":"bob@example.com","fromName":"Bob","subject":"Question","bodyText":"line1\nline2\n\n"}"#)
        let reply = SeekMailComposeContent.reply(to: mail, mailboxes: mailboxes)
        #expect(reply.to == "bob@example.com")
        #expect(reply.subject == "Re: Question")
        // 收信邮箱不能发信，换成第一个能发信的
        #expect(reply.mailboxID == 2)
        #expect(reply.body.hasSuffix("Bob <bob@example.com> 写道：\n> line1\n> line2"))

        let again = try decode(SeekMail.self, #"{"id":10,"mailboxId":2,"fromAddress":"bob@example.com","subject":"RE: Question","bodyText":""}"#)
        #expect(SeekMailComposeContent.reply(to: again, mailboxes: mailboxes).subject == "RE: Question")
        #expect(SeekMailComposeContent.reply(to: again, mailboxes: mailboxes).mailboxID == 2)
    }

    @Test func composeSendsAndReportsSuccess() async throws {
        let transport = SeekMailRouteTransport()
        transport.details["/openapi/v1/send"] = #"{"data":{"id":5,"status":"queued"}}"#
        var sent = 0
        let compose = try makeCompose(transport) { sent += 1 }
        let to = try #require(compose.view.mailTestView(id: "seek-mail-compose-to") as? UITextField)
        let subject = try #require(compose.view.mailTestView(id: "seek-mail-compose-subject") as? UITextField)
        let send = try #require(compose.navigationItem.rightBarButtonItem)
        #expect(send.isEnabled == false)
        to.text = "a@x.com, b@y.org"
        to.sendActions(for: .editingChanged)
        subject.text = "Hello"
        subject.sendActions(for: .editingChanged)
        #expect(send.isEnabled)

        guard #available(iOS 16.0, *) else { return }
        send.primaryAction?.performWithSender(nil, target: nil)
        await mailWaitUntil { sent == 1 }
        let request = try #require(transport.requests.last)
        #expect(request.httpMethod == "POST")
        let body = try #require(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["to"] as? String == "a@x.com,b@y.org")
        #expect(body["mailboxId"] as? Int == 2)
    }

    @Test func composeKeepsDraftAndShowsServerMessageOnFailure() async throws {
        let transport = SeekMailRouteTransport()
        transport.status = 500
        transport.override = #"{"error":{"code":"SEND_FAILED","message":"该域名已禁止发信"}}"#
        var sent = 0
        let compose = try makeCompose(transport) { sent += 1 }
        let to = try #require(compose.view.mailTestView(id: "seek-mail-compose-to") as? UITextField)
        let error = try #require(compose.view.mailTestView(id: "seek-mail-compose-error") as? UILabel)
        to.text = "a@x.com"
        to.sendActions(for: .editingChanged)
        (compose.view.mailTestView(id: "seek-mail-compose-body") as? UITextView)?.text = "正文"

        guard #available(iOS 16.0, *) else { return }
        compose.navigationItem.rightBarButtonItem?.primaryAction?.performWithSender(nil, target: nil)
        await mailWaitUntil { error.isHidden == false }
        #expect(error.text == "该域名已禁止发信")
        #expect(sent == 0)
        #expect(to.text == "a@x.com")
        #expect(compose.navigationItem.rightBarButtonItem?.accessibilityIdentifier == "seek-mail-compose-send")
    }

    @Test func composeKeyboardToolbarPreservesInput() throws {
        let compose = try makeCompose(SeekMailRouteTransport()) {}
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UINavigationController(rootViewController: compose)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        compose.view.layoutIfNeeded()
        defer { window.endEditing(true); window.isHidden = true }
        let to = try #require(compose.view.mailTestView(id: "seek-mail-compose-to") as? UITextField)
        let cc = try #require(compose.view.mailTestView(id: "seek-mail-compose-cc") as? UITextField)
        let subject = try #require(compose.view.mailTestView(id: "seek-mail-compose-subject") as? UITextField)
        let body = try #require(compose.view.mailTestView(id: "seek-mail-compose-body") as? UITextView)
        let toolbar = try #require(to.inputAccessoryView as? UIToolbar)
        #expect(cc.inputAccessoryView === toolbar)
        #expect(subject.inputAccessoryView === toolbar)
        #expect(body.inputAccessoryView === toolbar)
        let dismiss = try #require(toolbar.items?.last)
        let action = try #require(dismiss.action)
        to.text = "a@example.com"
        #expect(subject.becomeFirstResponder())
        subject.setMarkedText("主题", selectedRange: NSRange(location: 2, length: 0))
        #expect(UIApplication.shared.sendAction(action, to: dismiss.target, from: dismiss, for: nil))
        #expect(!subject.isFirstResponder)
        #expect(subject.markedTextRange == nil)
        #expect(subject.text == "主题")
        #expect(body.becomeFirstResponder())
        body.setMarkedText("正文", selectedRange: NSRange(location: 2, length: 0))
        #expect(UIApplication.shared.sendAction(action, to: dismiss.target, from: dismiss, for: nil))
        #expect(!body.isFirstResponder)
        #expect(body.markedTextRange == nil)
        #expect(body.text == "正文")
        #expect(to.text == "a@example.com")
        #expect(compose.navigationItem.rightBarButtonItem?.isEnabled == true)
    }

    // MARK: - 新邮件提醒

    @Test func monitorReadsCountsThrottlesAndDetectsNewMail() async throws {
        let transport = SeekMailRouteTransport()
        transport.details["/openapi/v1/mails/counts"] = #"{"data":{"mailboxes":{"1":2,"2":1},"total":3}}"#
        transport.details["/openapi/v1/mails/unread"] = #"{"data":[{"id":40,"mailboxId":1,"fromAddress":"a@x.com"},{"id":41,"mailboxId":2,"fromAddress":"b@x.com"}],"page":{"limit":50,"hasMore":false,"nextCursor":""}}"#
        let center = NotificationCenter()
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let defaults = makeDefaults()
        let monitor = SeekMailUnreadMonitor(
            keyStore: InMemorySeekMailKeyStore(key: "sk_live_ok"), transport: transport.load,
            defaults: defaults, notificationCenter: center, now: { clock }
        )
        var newMail: [Int] = []
        center.addObserver(forName: SeekMailUnreadMonitor.newMailNotification, object: nil, queue: nil) { note in
            newMail.append(note.userInfo?["count"] as? Int ?? -1)
        }

        monitor.check()
        await mailWaitUntil { transport.requests.count == 2 }
        #expect(monitor.totalUnread == 3)
        // 第一次是完整同步，只记位置，不算新邮件
        #expect(transport.requests.last?.url?.query == "limit=50")
        #expect(newMail.isEmpty)

        // 30 秒内不重复检查
        clock += 10
        monitor.check()
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(transport.requests.count == 2)

        // 未读总数没涨：只查 counts，不再拉 unread
        clock += 40
        monitor.check()
        await mailWaitUntil { transport.requests.count == 3 }
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(transport.requests.count == 3)
        #expect(transport.requests.last?.url?.path.hasSuffix("/mails/counts") == true)

        clock += 40
        transport.details["/openapi/v1/mails/counts"] = #"{"data":{"mailboxes":{"1":3,"2":1},"total":4}}"#
        transport.details["/openapi/v1/mails/unread"] = #"{"data":[{"id":42,"mailboxId":1,"fromAddress":"c@x.com"}],"page":{"limit":50,"hasMore":false,"nextCursor":""}}"#
        monitor.check()
        await mailWaitUntil { newMail.count == 1 }
        #expect(transport.requests.last?.url?.query == "after_id=41&limit=50")
        #expect(newMail == [1])
        #expect(SeekMailUnreadMonitor.badgeText(0) == nil)
        #expect(SeekMailUnreadMonitor.badgeText(120) == "99+")
    }

    @Test func localUnreadChangesUpdateBadgeAndClearSnapshot() {
        let monitor = SeekMailUnreadMonitor(keyStore: InMemorySeekMailKeyStore(),
                                            defaults: makeDefaults(), notificationCenter: NotificationCenter())
        monitor.applyCounts(SeekMailUnreadCounts(byMailbox: [1: 3], total: 3))
        #expect(SeekMailUnreadMonitor.badgeText(monitor.totalUnread) == "3")
        monitor.applyCounts(SeekMailUnreadCounts(byMailbox: [1: 2], total: 2))
        #expect(SeekMailUnreadMonitor.badgeText(monitor.totalUnread) == "2")
        monitor.applyCounts(SeekMailUnreadCounts(byMailbox: [1: 0], total: 0))
        #expect(SeekMailUnreadMonitor.badgeText(monitor.totalUnread) == nil)
        monitor.check(force: true)
        #expect(monitor.latestCounts == nil)
    }

    @Test func monitorClearsCountWithoutKey() {
        let center = NotificationCenter()
        let monitor = SeekMailUnreadMonitor(keyStore: InMemorySeekMailKeyStore(), transport: SeekMailRouteTransport().load,
                                            defaults: makeDefaults(), notificationCenter: center)
        monitor.check(force: true)
        #expect(monitor.totalUnread == nil)
    }

    // MARK: - 列表缓存

    @Test func cacheRoundTripsAndIsolatesAccounts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mails = try decode([SeekMail].self, #"[{"id":1,"mailboxId":1,"fromAddress":"a@x.com","subject":"s","bodyText":"b","receivedAt":"2026-11-16T03:31:18.123456789Z","verificationCode":"123456"}]"#)
        let boxes = try decode([SeekMailbox].self, #"[{"id":1,"address":"me@seek.li"}]"#)

        let cache = SeekMailListCache(directory: directory)
        cache.saveMailboxes(boxes, folders: [], for: "key-a")
        cache.saveMails(mails, for: "key-a", page: "all|inbox")

        // 新实例从文件读回
        let reloaded = SeekMailListCache(directory: directory)
        #expect(reloaded.mailboxes(for: "key-a")?.mailboxes == boxes)
        #expect(reloaded.mails(for: "key-a", page: "all|inbox") == mails)
        #expect(reloaded.mails(for: "key-b", page: "all|inbox") == nil)
        reloaded.clear()
        #expect(SeekMailListCache(directory: directory).mailboxes(for: "key-a") == nil)
    }

    @Test func modelShowsSnapshotBeforeNetwork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SeekMailListCache(directory: directory)
        let transport = SeekMailRouteTransport()
        let provider = SeekMailProvider<SeekMailAPI>(apiKey: { "sk_live_test" }, plugins: [], transport: transport.load)
        let first = SeekMailInboxModel(provider: provider, selectionStore: makeSelectionStore(),
                                       cache: cache, cacheKey: { "sk_live_test" })
        first.start()
        await mailWaitUntil { first.phase == .loaded }

        transport.delayNanoseconds = 300_000_000
        let second = SeekMailInboxModel(provider: provider, selectionStore: makeSelectionStore(),
                                        cache: SeekMailListCache(directory: directory), cacheKey: { "sk_live_test" })
        second.start()
        // 网络还没回来，已经能看到上次的邮件和邮箱名
        #expect(second.phase == .loaded)
        #expect(second.mails.map(\.id) == [11, 12])
        #expect(second.names[2]?.title == "账单")
    }

    // MARK: - 辅助

    private func makeCompose(_ transport: SeekMailRouteTransport, onSent: @escaping () -> Void) throws -> SeekMailComposeViewController {
        let mailboxes = try decode([SeekMailbox].self, #"[{"id":1,"address":"me@nodeseek.org"},{"id":2,"address":"me@seek.li"}]"#)
        let provider = SeekMailProvider<SeekMailAPI>(apiKey: { "sk_live_test" }, plugins: [], transport: transport.load)
        let compose = SeekMailComposeViewController(
            provider: provider, mailboxes: mailboxes, names: SeekMailboxNaming.displays(for: mailboxes),
            content: SeekMailComposeContent(), onSent: onSent
        )
        compose.loadViewIfNeeded()
        return compose
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try SeekMailJSON.decoder.decode(T.self, from: Data(json.utf8))
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "seek-mail-monitor-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

/// 全部标为已读：逐封处理、限速和额度等待。
@MainActor
struct SeekMailMarkAllReadTests {
    @Test func skipsWaitWhenQuotaExpiresDuringStateCallback() async throws {
        let transport = SeekMailRouteTransport()
        transport.details["/openapi/v1/mails/unread"] = Self.unread
        transport.headers = ["x-ratelimit-limit": "60", "x-ratelimit-remaining": "4"]
        let provider = SeekMailProvider<SeekMailAPI>(apiKey: { "sk_live_test" }, transport: transport.load)
        var clock = Date()
        var sleeps: [TimeInterval] = []
        let job = SeekMailMarkAllReadJob(provider: provider, sleep: { sleeps.append($0) }, now: { clock })
        let mails = try await job.collect(mailboxID: nil).mails
        let deadline = try #require(provider.rateLimit).observedAt.addingTimeInterval(60)
        clock = deadline.addingTimeInterval(-0.001)
        job.onChange = { state in
            if case .waiting = state { clock = deadline.addingTimeInterval(0.001) }
        }
        job.start(Array(mails.prefix(1)))
        await mailWaitUntil { if case .finished = job.state { return true }; return false }
        #expect(sleeps.isEmpty)
        #expect(job.state == .finished(succeeded: 1, failed: 0))
    }

    @Test func boundsCacheAndRemovesExpiredMailBodies() throws {
        var clock = Date()
        let cache = SeekMailMemoryCache(now: { clock })
        for id in 1...100 {
            clock = clock.addingTimeInterval(0.001)
            let json: [String: Any] = ["mail": ["id": id, "mailboxId": 1, "bodyHtml": String(repeating: "x", count: 100_000)]]
            let detail = try SeekMailJSON.decoder.decode(SeekMailDetail.self, from: JSONSerialization.data(withJSONObject: json))
            cache.saveDetail(detail, for: "test-key")
        }
        let retained = try #require(Mirror(reflecting: cache).children.first { $0.label == "details" })
        #expect(Mirror(reflecting: retained.value).children.count == SeekMailMemoryCache.maxEntryCount)
        #expect(cache.detail(id: 100, for: "test-key") != nil)
        clock = clock.addingTimeInterval(SeekMailMemoryCache.detailLifetime + 1)
        for id in 1...100 { #expect(cache.detail(id: Int64(id), for: "test-key") == nil) }
        let entries = try #require(Mirror(reflecting: cache).children.first { $0.label == "details" })
        #expect(Mirror(reflecting: entries.value).children.isEmpty)
        cache.clear()
        let cleared = try #require(Mirror(reflecting: cache).children.first { $0.label == "details" })
        #expect(Mirror(reflecting: cleared.value).children.isEmpty)
    }

    @Test func cacheEvictsOldBodiesAndSkipsOversizedDetails() throws {
        var clock = Date()
        let cache = SeekMailMemoryCache(now: { clock })
        func save(_ id: Int, bytes: Int) throws {
            clock = clock.addingTimeInterval(1)
            let json: [String: Any] = ["mail": ["id": id, "mailboxId": 1, "bodyHtml": String(repeating: "x", count: bytes)]]
            let detail = try SeekMailJSON.decoder.decode(SeekMailDetail.self, from: JSONSerialization.data(withJSONObject: json))
            cache.saveDetail(detail, for: "key")
        }
        try save(1, bytes: 3 * 1024 * 1024)
        try save(2, bytes: 3 * 1024 * 1024)
        #expect(cache.detail(id: 1, for: "key") == nil)
        #expect(cache.detail(id: 2, for: "key") != nil)
        try save(3, bytes: SeekMailMemoryCache.maxBodyBytes + 1)
        #expect(cache.detail(id: 3, for: "key") == nil)
        #expect(cache.detail(id: 2, for: "key") != nil)
        #expect(cache.detail(id: 2, for: "different-key") == nil)
    }

    @Test func attachmentCacheIsBoundedAndExpires() {
        var clock = Date()
        let cache = SeekMailMemoryCache(now: { clock })
        for id in 1...40 {
            clock = clock.addingTimeInterval(1)
            cache.saveAttachments([], mailID: Int64(id), for: "key")
        }
        #expect(cache.attachments(mailID: 1, for: "key") == nil)
        #expect(cache.attachments(mailID: 40, for: "key") != nil)
        clock = clock.addingTimeInterval(SeekMailMemoryCache.detailLifetime + 1)
        #expect(cache.attachments(mailID: 40, for: "key") == nil)
        let entries = Mirror(reflecting: cache).children.first { $0.label == "attachments" }
        #expect(entries.map { Mirror(reflecting: $0.value).children.isEmpty } == true)
    }

    private static let unread = #"{"data":[{"id":31,"mailboxId":1,"fromAddress":"a@x.com"},{"id":32,"mailboxId":2,"fromAddress":"b@x.com"},{"id":33,"mailboxId":1,"fromAddress":"c@x.com"}],"page":{"limit":50,"hasMore":false,"nextCursor":""}}"#

    @Test func collectsCurrentMailboxAndMarksOneByOne() async throws {
        let transport = SeekMailRouteTransport()
        transport.details["/openapi/v1/mails/unread"] = Self.unread
        let provider = SeekMailProvider<SeekMailAPI>(apiKey: { "sk_live_test" }, transport: transport.load)
        var sleeps: [TimeInterval] = []
        let job = SeekMailMarkAllReadJob(provider: provider, sleep: { sleeps.append($0) })
        var marked: [Int64] = []
        var states: [SeekMailMarkAllReadJob.State] = []
        job.onMarked = { marked.append($0.id) }
        job.onChange = { states.append($0) }

        let result = try await job.collect(mailboxID: 1)
        #expect(result.mails.map(\.id) == [31, 33])
        #expect(result.total == 2)

        job.start(result.mails)
        await mailWaitUntil { if case .finished = job.state { return true } else { return false } }
        #expect(job.state == .finished(succeeded: 2, failed: 0))
        #expect(marked == [31, 33])
        let puts = transport.requests.filter { $0.httpMethod == "PUT" }.compactMap { $0.url?.path }
        #expect(puts == ["/openapi/v1/mails/31/read", "/openapi/v1/mails/33/read"])
        // 两封之间主动间隔，最后一封后不再等
        #expect(sleeps == [SeekMailMarkAllReadJob.interval])
        // 预计耗时算上请求本身：6 封约 11 秒，100 封约 3 分钟
        #expect(SeekMailMarkAllReadJob.estimatedSeconds(count: 6) == 11)
        #expect(SeekMailMarkAllReadJob.estimatedSeconds(count: 100) == 180)
        #expect(states.contains(.running(done: 1, total: 2)))
    }

    @Test func immediateStopPreventsRequestsAndDuplicateStart() async throws {
        let transport = SeekMailRouteTransport()
        transport.details["/openapi/v1/mails/unread"] = Self.unread
        let provider = SeekMailProvider<SeekMailAPI>(apiKey: { "sk_live_test" }, transport: transport.load)
        let job = SeekMailMarkAllReadJob(provider: provider, sleep: { _ in })
        let mails = try await job.collect(mailboxID: 1).mails
        job.start(mails)
        #expect(job.isActive)
        job.start(mails)
        job.stop()
        await mailWaitUntil { if case .stopped = job.state { return true }; return false }
        #expect(job.state == .stopped(done: 0, total: 2))
        #expect(transport.requests.filter { $0.httpMethod == "PUT" }.isEmpty)
    }

    @Test func waitsForQuotaWindowWhenRemainingIsLow() async throws {
        let transport = SeekMailRouteTransport()
        transport.details["/openapi/v1/mails/unread"] = Self.unread
        transport.headers = ["x-ratelimit-limit": "60", "x-ratelimit-remaining": "4"]
        let provider = SeekMailProvider<SeekMailAPI>(apiKey: { "sk_live_test" }, transport: transport.load)
        var sleeps: [TimeInterval] = []
        let job = SeekMailMarkAllReadJob(provider: provider, sleep: { sleeps.append($0) })
        var sawWaiting = false
        job.onChange = { if case .waiting = $0 { sawWaiting = true } }

        let result = try await job.collect(mailboxID: nil)
        job.start(Array(result.mails.prefix(1)))
        await mailWaitUntil { if case .finished = job.state { return true } else { return false } }
        // 统计时看到额度只剩 4，先等窗口过去再标记
        #expect(sawWaiting)
        #expect(sleeps.first.map { $0 > 50 && $0 <= 60 } == true)
        #expect(job.state == .finished(succeeded: 1, failed: 0))
    }

    @Test func modelAppliesMarkedReadLocally() async {
        let transport = SeekMailRouteTransport()
        transport.details["/openapi/v1/mails/counts"] = #"{"data":{"mailboxes":{"1":1},"total":1}}"#
        let model = SeekMailInboxModel(
            provider: SeekMailProvider(apiKey: { "sk_live_ok" }, transport: transport.load),
            selectionStore: makeSelectionStore()
        )
        model.start()
        await mailWaitUntil { model.phase == .loaded && model.unreadTotal == 1 }
        model.applyMarkedRead(id: 11, mailboxID: 1)
        #expect(model.mail(id: 11)?.isRead == true)
        #expect(model.unreadTotal == 0)
        // 已经是已读的不重复扣
        model.applyMarkedRead(id: 11, mailboxID: 1)
        #expect(model.unreadTotal == 0)
    }
}

/// 新建邮箱：先检查地址可用再创建，成功后列表切到新邮箱。
@MainActor
struct SeekMailCreateMailboxTests {
    @Test func routesCheckAsQueryAndCreateAsJSON() throws {
        let check = SeekMailAPI.checkMailbox(address: "shop@seek.li")
        #expect(check.path == "/mailboxes/check")
        #expect(check.method == .post)
        #expect(check.requiredScope == "mailbox:write")
        let create = SeekMailAPI.createMailbox(address: "shop@seek.li")
        #expect(create.path == "/mailboxes")
        #expect(create.method == .post)
        #expect(create.requiredScope == "mailbox:write")
    }

    private static func makeController(_ transport: SeekMailRouteTransport, onCreated: @escaping (SeekMailbox) -> Void = { _ in }) throws
        -> (SeekMailCreateMailboxViewController, UITextField, UIButton, UILabel) {
        let controller = SeekMailCreateMailboxViewController(
            provider: SeekMailProvider(apiKey: { "sk_live_test" }, transport: transport.load), onCreated: onCreated
        )
        controller.loadViewIfNeeded()
        let field = try #require(controller.view.mailTestView(id: "seek-mail-create-prefix") as? UITextField)
        let check = try #require(controller.view.mailTestView(id: "seek-mail-create-check") as? UIButton)
        let status = try #require(controller.view.mailTestView(id: "seek-mail-create-status") as? UILabel)
        return (controller, field, check, status)
    }

    private static func type(_ text: String, into field: UITextField) {
        field.text = text
        field.sendActions(for: .editingChanged)
    }

    private static func checkRequests(_ transport: SeekMailRouteTransport) -> Int {
        transport.requests.filter { $0.url?.path == "/openapi/v1/mailboxes/check" }.count
    }

    @Test func checksOnlyWhenTappedThenCreates() async throws {
        let transport = SeekMailRouteTransport()
        transport.posts["/openapi/v1/mailboxes/check"] = #"{"data":{"available":true}}"#
        transport.posts["/openapi/v1/mailboxes"] = #"{"data":{"id":9,"address":"shop@seek.li"}}"#
        var created: SeekMailbox?
        let (controller, field, check, status) = try Self.makeController(transport) { created = $0 }
        let submit = try #require(controller.navigationItem.rightBarButtonItem)
        #expect(check.isEnabled == false)

        Self.type("shop", into: field)
        try await Task.sleep(nanoseconds: 300_000_000)
        // 输入不自动检查，省额度
        #expect(Self.checkRequests(transport) == 0)
        #expect(check.isEnabled)
        #expect(submit.isEnabled == false)

        check.sendActions(for: .touchUpInside)
        await mailWaitUntil { submit.isEnabled }
        #expect(Self.checkRequests(transport) == 1)
        let checkRequest = try #require(transport.requests.first { $0.url?.path == "/openapi/v1/mailboxes/check" })
        #expect(checkRequest.url?.query?.contains("address=shop@seek.li") == true)

        // 改了前缀，结果作废并提示重新检查，但不发请求
        Self.type("shop2", into: field)
        #expect(submit.isEnabled == false)
        #expect(status.text == SeekMailL10n.text("地址已修改，请重新检查"))
        Self.type("shop", into: field)
        #expect(Self.checkRequests(transport) == 1)
        // 回车也能检查
        _ = controller.textFieldShouldReturn(field)
        await mailWaitUntil { submit.isEnabled }
        #expect(Self.checkRequests(transport) == 2)

        let action = try #require(submit.primaryAction)
        // 测试 target 的最低版本比 App 低
        if #available(iOS 16.0, *) { action.performWithSender(nil, target: nil) } else { return }
        await mailWaitUntil { created != nil }
        #expect(created?.id == 9)
        let createRequest = try #require(transport.requests.last { $0.url?.path == "/openapi/v1/mailboxes" })
        #expect(createRequest.httpMethod == "POST")
        let body = try #require(createRequest.httpBody)
        #expect(try JSONSerialization.jsonObject(with: body) as? [String: String] == ["address": "shop@seek.li"])
    }

    @Test func recheckInvalidatesPreviouslyAvailableAddress() async throws {
        let transport = SeekMailRouteTransport()
        transport.posts["/openapi/v1/mailboxes/check"] = #"{"data":{"available":true}}"#
        let (controller, field, check, status) = try Self.makeController(transport)
        let submit = try #require(controller.navigationItem.rightBarButtonItem)
        Self.type("shop", into: field)
        check.sendActions(for: .touchUpInside)
        await mailWaitUntil { submit.isEnabled }
        #expect(submit.isEnabled)
        transport.posts["/openapi/v1/mailboxes/check"] = #"{"data":{"available":false,"message":"taken"}}"#
        check.sendActions(for: .touchUpInside)
        #expect(submit.isEnabled == false)
        await mailWaitUntil { status.text == "taken" }
        #expect(submit.isEnabled == false)
        withExtendedLifetime(controller) {}
    }

    @Test func pastedFullAddressIsSplit() throws {
        let transport = SeekMailRouteTransport()
        let (controller, field, check, status) = try Self.makeController(transport)
        let domain = try #require(controller.view.mailTestView(id: "seek-mail-create-domain") as? UISegmentedControl)

        Self.type("Shop@NodeSeek.org", into: field)
        #expect(field.text == "Shop")
        #expect(domain.selectedSegmentIndex == 1)
        #expect(controller.address == "Shop@nodeseek.org")

        Self.type("shop@gmail.com", into: field)
        #expect(status.text == SeekMailL10n.text("只能使用 seek.li 或 nodeseek.org"))
        #expect(check.isEnabled == false)
        // 格式提示不算检查结果，补全成可用域名后不提示「重新检查」
        Self.type("shop@seek.li", into: field)
        #expect(status.text == nil)
        #expect(domain.selectedSegmentIndex == 0)
        #expect(transport.requests.isEmpty)
    }

    @Test func showsServerReasonWhenTaken() async throws {
        let transport = SeekMailRouteTransport()
        transport.posts["/openapi/v1/mailboxes/check"] = #"{"data":{"available":false,"message":"该地址已被使用","reason":"address_taken"}}"#
        let (controller, field, check, status) = try Self.makeController(transport)
        Self.type("taken", into: field)
        check.sendActions(for: .touchUpInside)
        await mailWaitUntil { status.text == "该地址已被使用" }
        #expect(controller.navigationItem.rightBarButtonItem?.isEnabled == false)
    }

    @Test func rateLimitedCheckDoesNotRetry() async throws {
        let transport = SeekMailRouteTransport()
        transport.status = 429
        transport.override = #"{"error":{"code":"AUTH_RATE_LIMITED","message":"认证失败次数过多，请稍后再试"}}"#
        // 持有页面，否则检查任务里的 weak self 会提前失效
        let (controller, field, check, status) = try Self.makeController(transport)
        Self.type("shop", into: field)
        check.sendActions(for: .touchUpInside)
        await mailWaitUntil { status.text == SeekMailL10n.text("请求太频繁，请稍后再试") }
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(Self.checkRequests(transport) == 1)
        #expect(check.isEnabled)
        withExtendedLifetime(controller) {}
    }

    @Test func modelAddsAndSelectsCreatedMailbox() async {
        let transport = SeekMailRouteTransport()
        let model = SeekMailInboxModel(
            provider: SeekMailProvider(apiKey: { "sk_live_ok" }, transport: transport.load),
            selectionStore: makeSelectionStore()
        )
        model.start()
        await mailWaitUntil { model.phase == .loaded }
        let mailbox = SeekMailbox(id: 9, address: "shop@seek.li", alias: nil, domainId: nil, status: nil, sendDisabled: nil, isPinned: nil, sortOrder: nil)
        model.addCreatedMailbox(mailbox)
        #expect(model.selectedMailboxID == 9)
        #expect(model.mailboxTags.contains { $0.id == 9 && $0.address == "shop@seek.li" })
        // 重复回调不会加出两个
        model.addCreatedMailbox(mailbox)
        #expect(model.mailboxes.filter { $0.id == 9 }.count == 1)
    }
}
