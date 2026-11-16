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
        await waitUntil { boundCount == 1 }

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
        await waitUntil { error.isHidden == false }

        #expect(error.text == "Key 无效或已失效，请检查后重新粘贴")
        #expect(store.apiKey() == nil)
        // 改动输入后错误提示消失，可重新验证
        field.text = "sk_live_bad2"
        field.sendActions(for: .editingChanged)
        #expect(error.isHidden)
        #expect(save.isEnabled)
    }

    @Test func missingScopeExplainsWhichPermission() {
        let message = SeekMailBindViewController.message(for: SeekMailError.forbidden(scope: "mailbox:read", message: nil))
        #expect(message == "API Key 缺少 mailbox:read 权限，请在 seek.li 重新创建 Key")
    }

    // MARK: - 入口页

    @Test func homeSwitchesBetweenBindAndInboxWhenKeyChanges() async throws {
        let store = InMemorySeekMailKeyStore()
        let transport = MailboxTransport(status: 200, body: #"{"data":[{"id":1,"address":"a@seek.li"},{"id":2,"address":"b@seek.li"}]}"#)
        let home = SeekMailHomeViewController(keyStore: store, transport: transport.load)
        home.loadViewIfNeeded()

        #expect(home.children.first is SeekMailBindViewController)
        #expect(home.navigationItem.rightBarButtonItems?.isEmpty ?? true)

        store.save(apiKey: "sk_live_ok")
        #expect(home.children.first is SeekMailInboxViewController)
        #expect(home.children.count == 1)
        #expect(home.navigationItem.rightBarButtonItems?.first?.accessibilityIdentifier == "seek-mail-more")

        let detail = try #require(home.view.mailTestView(id: "seek-mail-inbox-detail") as? UILabel)
        await waitUntil { detail.text != nil }
        #expect(detail.text == "共 2 个邮箱")
        #expect(transport.authorization == "Bearer sk_live_ok")

        store.clear()
        #expect(home.children.first is SeekMailBindViewController)
        #expect(home.children.count == 1)
    }

    @Test func expiredKeyReturnsToBindWithReason() async throws {
        let store = InMemorySeekMailKeyStore(key: "sk_live_expired")
        let transport = MailboxTransport(status: 401, body: #"{"error":{"code":"UNAUTHORIZED","message":"无效的 API Key"}}"#)
        let home = SeekMailHomeViewController(keyStore: store, transport: transport.load)
        home.loadViewIfNeeded()
        #expect(home.children.first is SeekMailInboxViewController)

        await waitUntil { home.children.first is SeekMailBindViewController }

        #expect(store.apiKey() == nil)
        let error = try #require(home.view.mailTestView(id: "seek-mail-bind-error") as? UILabel)
        #expect(error.isHidden == false)
        #expect(error.text == "之前保存的 Key 已失效，请重新粘贴")
    }

    // MARK: - 辅助

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where condition() == false {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

/// 内存版 Key 存储；和钥匙串实现一样在变化时发通知，入口页靠它切换。
@MainActor
private final class InMemorySeekMailKeyStore: SeekMailAPIKeyStoring {
    private var key: String?

    init(key: String? = nil) {
        self.key = key
    }

    func apiKey() -> String? { key }

    func save(apiKey: String) {
        key = SeekMailAPIKeyStore.normalized(apiKey)
        NotificationCenter.default.post(name: SeekMailAPIKeyStore.didChangeNotification, object: self)
    }

    func clear() {
        key = nil
        NotificationCenter.default.post(name: SeekMailAPIKeyStore.didChangeNotification, object: self)
    }
}

@MainActor
private final class MailboxTransport {
    let status: Int
    let body: Data
    private(set) var authorization: String?

    init(status: Int, body: String) {
        self.status = status
        self.body = Data(body.utf8)
    }

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        authorization = request.value(forHTTPHeaderField: "Authorization")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (body, response)
    }
}

private extension UIView {
    func mailTestView(id: String) -> UIView? {
        if accessibilityIdentifier == id { return self }
        for subview in subviews {
            if let match = subview.mailTestView(id: id) { return match }
        }
        return nil
    }
}
