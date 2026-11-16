import Foundation
import Testing
import UIKit
@testable import nodeseek

@MainActor
struct SeekMailBindTests {
    // MARK: - 绑定页

    @Test func savesNormalizedKeyAfterVerification() async throws {
        let store = InMemorySeekMailKeyStore()
        var verifiedKeys: [String] = []
        var boundCount = 0
        let bind = SeekMailBindViewController(
            keyStore: store,
            verify: { key in
                verifiedKeys.append(key)
                return []
            },
            onBound: { _ in boundCount += 1 }
        )
        bind.loadViewIfNeeded()

        let field = try #require(bind.view.mailTestView(id: "seek-mail-bind-key-field") as? UITextField)
        let save = try #require(bind.view.mailTestView(id: "seek-mail-bind-save") as? UIButton)
        #expect(save.isEnabled == false)

        field.text = "  Bearer sk_live_abc  "
        field.sendActions(for: .editingChanged)
        #expect(save.isEnabled)
        save.sendActions(for: .touchUpInside)
        await mailWaitUntil { boundCount == 1 }

        #expect(verifiedKeys == ["sk_live_abc"])
        #expect(store.apiKey() == "sk_live_abc")
    }

    @Test func invalidKeyShowsErrorAndIsNotSaved() async throws {
        let store = InMemorySeekMailKeyStore()
        let bind = SeekMailBindViewController(
            keyStore: store,
            verify: { _ in throw SeekMailError.unauthorized(message: "无效的 API Key") }
        )
        bind.loadViewIfNeeded()

        let field = try #require(bind.view.mailTestView(id: "seek-mail-bind-key-field") as? UITextField)
        let save = try #require(bind.view.mailTestView(id: "seek-mail-bind-save") as? UIButton)
        let error = try #require(bind.view.mailTestView(id: "seek-mail-bind-error") as? UILabel)
        #expect(error.isHidden)

        field.text = "sk_live_bad"
        field.sendActions(for: .editingChanged)
        save.sendActions(for: .touchUpInside)
        await mailWaitUntil { error.isHidden == false }

        #expect(error.text == "Key 无效或已失效，请检查后重新粘贴")
        #expect(store.apiKey() == nil)
        // 改动输入后错误提示消失，可重新验证
        field.text = "sk_live_bad2"
        field.sendActions(for: .editingChanged)
        #expect(error.isHidden)
        #expect(save.isEnabled)
    }

    @Test func longKeyDoesNotPushPasteButtonOutOfCard() throws {
        let bind = SeekMailBindViewController(keyStore: InMemorySeekMailKeyStore(), verify: { _ in [] })
        bind.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let field = try #require(bind.view.mailTestView(id: "seek-mail-bind-key-field") as? UITextField)
        let paste = try #require(bind.view.mailTestView(id: "seek-mail-bind-paste"))
        field.text = "sk_live_" + String(repeating: "0123456789abcdef", count: 4)
        field.sendActions(for: .editingChanged)
        bind.view.layoutIfNeeded()

        let pasteFrame = paste.convert(paste.bounds, to: bind.view)
        #expect(pasteFrame.maxX <= 390 - 16)
        #expect(pasteFrame.width > 30)
    }

    @Test func keychainFailureIsReported() async throws {
        let store = InMemorySeekMailKeyStore()
        store.failsToSave = true
        var boundCount = 0
        let bind = SeekMailBindViewController(keyStore: store, verify: { _ in [] }, onBound: { _ in boundCount += 1 })
        bind.loadViewIfNeeded()
        let field = try #require(bind.view.mailTestView(id: "seek-mail-bind-key-field") as? UITextField)
        let save = try #require(bind.view.mailTestView(id: "seek-mail-bind-save") as? UIButton)
        let error = try #require(bind.view.mailTestView(id: "seek-mail-bind-error") as? UILabel)
        field.text = "sk_live_ok"
        field.sendActions(for: .editingChanged)
        save.sendActions(for: .touchUpInside)
        await mailWaitUntil { error.isHidden == false }
        #expect(error.text == "Key 有效，但没能保存到本机钥匙串，请重试")
        #expect(boundCount == 0)
        #expect(save.isEnabled)
    }

    @Test func missingScopeExplainsWhichPermission() {
        let message = SeekMailBindViewController.message(for: SeekMailError.forbidden(scope: "mailbox:read", message: nil))
        #expect(message == "API Key 缺少 mailbox:read 权限，请在 seek.li 重新创建 Key")
    }

    // MARK: - 入口页

    @Test func homeSwitchesBetweenBindAndInboxWhenKeyChanges() async throws {
        let store = InMemorySeekMailKeyStore()
        let transport = SeekMailRouteTransport()
        let home = SeekMailHomeViewController(keyStore: store, transport: transport.load, selectionStore: makeSelectionStore(), cache: nil, memoryCache: nil)
        home.loadViewIfNeeded()

        #expect(home.children.first is SeekMailBindViewController)
        #expect(home.navigationItem.rightBarButtonItems?.isEmpty ?? true)

        store.save(apiKey: "sk_live_ok")
        let inbox = try #require(home.children.first as? SeekMailInboxViewController)
        #expect(home.children.count == 1)
        #expect(home.navigationItem.rightBarButtonItems?.first?.accessibilityIdentifier == "seek-mail-more")
        // 邮箱用页面顶部的标签切换，导航栏只显示标题
        #expect(home.navigationItem.titleView == nil)
        // 搜索框在页面底部，不挂到导航栏，避免返回时底部 Tab 跳动
        #expect(home.navigationItem.searchController == nil)
        #expect(inbox.view.mailTestView(id: "seek-mail-search") is UITextField)

        await mailWaitUntil { inbox.model.phase == .loaded }
        #expect(inbox.model.mails.map(\.id) == [11, 12])
        #expect(transport.authorizations.allSatisfy { $0 == "Bearer sk_live_ok" })
        home.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        home.view.layoutIfNeeded()
        #expect(home.view.mailTestView(id: "seek-mail-row-11") != nil)

        store.clear()
        #expect(home.children.first is SeekMailBindViewController)
        #expect(home.children.count == 1)
        #expect(home.navigationItem.titleView == nil)
    }

    @Test func expiredKeyReturnsToBindWithReason() async throws {
        let store = InMemorySeekMailKeyStore(key: "sk_live_expired")
        let transport = SeekMailRouteTransport()
        transport.status = 401
        transport.override = #"{"error":{"code":"UNAUTHORIZED","message":"无效的 API Key"}}"#
        let home = SeekMailHomeViewController(keyStore: store, transport: transport.load, selectionStore: makeSelectionStore(), cache: nil, memoryCache: nil)
        home.loadViewIfNeeded()
        #expect(home.children.first is SeekMailInboxViewController)

        await mailWaitUntil { home.children.first is SeekMailBindViewController }

        #expect(store.apiKey() == nil)
        let error = try #require(home.view.mailTestView(id: "seek-mail-bind-error") as? UILabel)
        #expect(error.isHidden == false)
        #expect(error.text == "之前保存的 Key 已失效，请重新粘贴")
    }

    }

/// 内存版 Key 存储；和钥匙串实现一样在变化时发通知，入口页靠它切换。
@MainActor
final class InMemorySeekMailKeyStore: SeekMailAPIKeyStoring {
    private var key: String?

    init(key: String? = nil) {
        self.key = key
    }

    func apiKey() -> String? { key }

    var failsToSave = false

    @discardableResult
    func save(apiKey: String) -> Bool {
        guard failsToSave == false else { return false }
        key = SeekMailAPIKeyStore.normalized(apiKey)
        NotificationCenter.default.post(name: SeekMailAPIKeyStore.didChangeNotification, object: self)
        return true
    }

    func clear() {
        key = nil
        NotificationCenter.default.post(name: SeekMailAPIKeyStore.didChangeNotification, object: self)
    }
}

extension UIView {
    func mailTestView(id: String) -> UIView? {
        if accessibilityIdentifier == id { return self }
        for subview in subviews {
            if let match = subview.mailTestView(id: id) { return match }
        }
        return nil
    }
}

/// 按路径返回假数据的 transport；样例里的地址都是假值。
@MainActor
final class SeekMailRouteTransport {
    var status = 200
    /// 不为 nil 时所有请求都返回这段内容。
    var override: String?
    var mailboxes = #"{"data":[{"id":1,"address":"alpha@seek.li"},{"id":2,"address":"beta@seek.li","alias":"账单"}]}"#
    var mailPages: [String] = [
        #"{"data":[{"id":11,"mailboxId":1,"fromAddress":"noreply@example.com","subject":"Hi","bodyText":"a","isRead":false},{"id":12,"mailboxId":2,"fromAddress":"bill@example.com","subject":"Bill","bodyText":"b","isRead":true}],"pagination":{"total":2,"limit":20,"offset":0}}"#
    ]
    /// 按完整路径返回的内容，例如详情和附件列表。
    var details: [String: String] = [:]
    /// 模拟网络耗时，用来看到加载中的骨架行。
    var delayNanoseconds: UInt64 = 0
    private(set) var requests: [URLRequest] = []
    var authorizations: [String?] { requests.map { $0.value(forHTTPHeaderField: "Authorization") } }

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        let path = request.url?.path ?? ""
        let body: String
        if let override {
            body = override
        } else if path.hasSuffix("/mailboxes") {
            body = mailboxes
        } else if path.hasSuffix("/folders") {
            body = #"{"data":null}"#
        } else if let detail = details[path] {
            body = detail
        } else if path.hasSuffix("/mails") {
            let index = min(requests.filter { $0.url?.path.hasSuffix("/mails") == true }.count - 1, mailPages.count - 1)
            body = mailPages[index]
        } else {
            body = #"{"data":{"success":true}}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: override == nil ? 200 : status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

@MainActor
func makeSelectionStore() -> SeekMailSelectionStore {
    let suite = "seek-mail-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return SeekMailSelectionStore(defaults: defaults)
}

@MainActor
func mailWaitUntil(_ condition: () -> Bool) async {
    for _ in 0..<300 where condition() == false {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}
