import Foundation
import Testing
import UIKit
@testable import nodeseek

@MainActor
struct SeekMailDetailTests {
    // MARK: - 纯逻辑

    @Test func authFailureDetectsFailedChecksAndMismatch() {
        let pass = #"{"auth":{"spf":{"status":"pass"},"dkim":{"status":"pass"},"dmarc":{"status":"none"},"fromMismatch":false}}"#
        let softfail = #"{"auth":{"spf":{"status":"SoftFail"},"dkim":{"status":"pass"}}}"#
        let mismatch = #"{"auth":{"spf":{"status":"pass"},"fromMismatch":true}}"#
        #expect(SeekMailDetailContent.hasAuthFailure(scoreDetails: pass) == false)
        #expect(SeekMailDetailContent.hasAuthFailure(scoreDetails: softfail))
        #expect(SeekMailDetailContent.hasAuthFailure(scoreDetails: mismatch))
        #expect(SeekMailDetailContent.hasAuthFailure(scoreDetails: nil) == false)
        #expect(SeekMailDetailContent.hasAuthFailure(scoreDetails: "not json") == false)
    }

    @Test func countsOnlyRemoteImages() {
        let html = #"""
        <img src="https://a.example/x.png"><IMG alt="b" SRC='http://b.example/y.gif'>
        <img src="cid:inline-1"><img src="data:image/png;base64,AAAA"><a href="https://c.example">c</a>
        """#
        #expect(SeekMailDetailContent.remoteImageCount(in: html) == 2)
        #expect(SeekMailDetailContent.wrappedHTML("<p>x</p>").contains(#"<meta name="color-scheme" content="light dark">"#))
        // 正文默认字号跟随 App 的「字体大小」
        #expect(SeekMailDetailContent.wrappedHTML("<p>x</p>", fontSize: 21).contains("font-size: 21px"))
    }

    // MARK: - 页面

    @Test func detailRendersHeaderCodeAttachmentsAndMarksRead() async throws {
        let (model, transport) = try await loadedModel()
        let detail = SeekMailDetailViewController(mailID: 11, model: model) { _ in }
        let navigation = UINavigationController(rootViewController: UIViewController())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = navigation
        window.isHidden = false
        defer { window.isHidden = true }
        navigation.pushViewController(detail, animated: false)
        detail.view.layoutIfNeeded()

        await mailWaitUntil { detail.view.mailTestView(id: "seek-mail-detail-attachment-0") != nil }
        #expect((detail.view.mailTestView(id: "seek-mail-detail-subject") as? UILabel)?.text == "Your code")
        #expect((detail.view.mailTestView(id: "seek-mail-detail-recipient") as? UILabel)?.text == "发给 alpha@seek.li")
        #expect((detail.view.mailTestView(id: "seek-mail-detail-code") as? UILabel)?.text == "482913")
        #expect(detail.view.mailTestView(id: "seek-mail-detail-auth-warning") != nil)
        #expect(detail.view.mailTestView(id: "seek-mail-detail-text") != nil)
        // 内嵌图片不算附件
        #expect(detail.view.mailTestView(id: "seek-mail-detail-attachment-1") == nil)
        // 打开即标已读，本地列表同步更新
        #expect(model.mail(id: 11)?.isRead == true)
        #expect(transport.requests.contains { $0.httpMethod == "PUT" && $0.url?.path == "/openapi/v1/mails/11/read" })
        #expect(detail.toolbarItems?.contains { $0.accessibilityIdentifier == "seek-mail-detail-delete" } == true)
    }

    @Test func htmlMailShowsBlockedImageBanner() async throws {
        let (model, _) = try await loadedModel(html: #"<p>Hi</p><img src="https://track.example/p.gif"><img src="https://cdn.example/logo.png">"#)
        let detail = SeekMailDetailViewController(mailID: 11, model: model) { _ in }
        detail.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        detail.loadViewIfNeeded()
        await mailWaitUntil { detail.view.mailTestView(id: "seek-mail-detail-load-images") != nil }

        let banner = try #require(detail.view.mailTestView(id: "seek-mail-detail-load-images") as? UIButton)
        #expect(banner.configuration?.title == "已阻止 2 张远程图片 · 加载")
        #expect(detail.view.mailTestView(id: "seek-mail-detail-web") != nil)
        banner.sendActions(for: .touchUpInside)
        #expect(detail.view.mailTestView(id: "seek-mail-detail-load-images") == nil)
        #expect(detail.view.mailTestView(id: "seek-mail-detail-web") != nil)
    }

    @Test func deleteFromDetailHandsBackToList() async throws {
        let (model, _) = try await loadedModel()
        var deleted: [Int64] = []
        let detail = SeekMailDetailViewController(mailID: 11, model: model) { deleted.append($0) }
        detail.loadViewIfNeeded()
        let delete = try #require(detail.toolbarItems?.first { $0.accessibilityIdentifier == "seek-mail-detail-delete" })
        let action = try #require(delete.primaryAction)
        guard #available(iOS 16.0, *) else { return }
        action.performWithSender(nil, target: nil)
        #expect(deleted == [11])
    }

    // MARK: - 辅助

    private func loadedModel(html: String = "") async throws -> (SeekMailInboxModel, SeekMailRouteTransport) {
        let transport = SeekMailRouteTransport()
        let htmlField = html.isEmpty ? "" : #","bodyHtml":"\#(html.replacingOccurrences(of: "\"", with: "\\\""))""#
        transport.details["/openapi/v1/mails/11"] = #"{"data":{"mail":{"id":11,"mailboxId":1,"fromAddress":"noreply@example.com","fromName":"Example","toAddress":"alpha@seek.li","subject":"Your code","bodyText":"Your code is 482913","verificationCode":"482913","hasAttachments":true,"scoreDetails":"{\"auth\":{\"spf\":{\"status\":\"fail\"}}}"\#(htmlField)},"tags":[]}}"#
        transport.details["/openapi/v1/mails/11/attachments"] = #"{"data":[{"id":1,"mailId":11,"filename":"invoice.pdf","contentType":"application/pdf","size":2048,"isInline":false,"index":0},{"id":2,"mailId":11,"filename":"logo.png","contentType":"image/png","size":10,"isInline":true,"index":1}]}"#
        let provider = SeekMailProvider<SeekMailAPI>(apiKey: { "sk_live_test" }, plugins: [], transport: transport.load)
        let model = SeekMailInboxModel(provider: provider, selectionStore: makeSelectionStore())
        model.start()
        await mailWaitUntil { model.phase == .loaded }
        return (model, transport)
    }

    @Test func mailFontsFollowAppTextSizeOffset() {
        #expect(SeekMailFont.of(.body, pointOffset: 0).pointSize == 17)
        #expect(SeekMailFont.of(.subheadline, pointOffset: 4).pointSize == 19)
        #expect(SeekMailFont.of(.footnote, pointOffset: -4).pointSize == 9)
        #expect(SeekMailFont.of(.title2, pointOffset: 8).pointSize == 30)
    }
}
