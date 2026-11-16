import Foundation
import Testing
import UIKit
@testable import nodeseek

/// 在有尺寸的界面里真正生成单元格，覆盖骨架行、邮件行和验证码卡片的布局。
@MainActor
struct SeekMailInboxViewTests {
    @Test func rendersSkeletonThenRowsAndCodeCard() async throws {
        let transport = SeekMailRouteTransport()
        transport.delayNanoseconds = 150_000_000
        let received = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-90))
        transport.mailPages = [#"{"data":[{"id":21,"mailboxId":1,"fromAddress":"noreply@example.com","fromName":"GitHub","subject":"Verify","bodyText":"Your code is 482913","verificationCode":"482913","receivedAt":"\#(received)"},{"id":22,"mailboxId":2,"fromAddress":"bill@example.com","subject":"Invoice","bodyText":"Paid","isRead":true,"hasAttachments":true}],"pagination":{"total":2,"limit":20,"offset":0}}"#]
        let inbox = SeekMailInboxViewController(
            keyStore: InMemorySeekMailKeyStore(key: "sk_live_ok"),
            transport: transport.load,
            selectionStore: makeSelectionStore()
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = inbox
        window.isHidden = false
        defer { window.isHidden = true }
        inbox.view.layoutIfNeeded()

        let table = try #require(inbox.view.mailTestView(id: "seek-mail-list") as? UITableView)
        #expect(table.visibleCells.contains { $0 is SeekMailSkeletonCell })

        await mailWaitUntil { inbox.model.phase == .loaded }
        table.layoutIfNeeded()
        #expect(table.visibleCells.contains { $0 is SeekMailSkeletonCell } == false)
        #expect(table.visibleCells.filter { $0 is SeekMailCell }.count == 2)
        let card = try #require(table.visibleCells.first { $0 is SeekMailCodeCell })
        #expect((card.mailTestView(id: "seek-mail-code-card-code") as? UILabel)?.text == "482913")
        // 「全部邮箱」时摘要开头标出收件邮箱，行内也显示验证码
        let row = try #require(table.visibleCells.first { $0.accessibilityIdentifier == "seek-mail-row-21" })
        #expect(row.mailTestView(id: "seek-mail-row-code")?.isHidden == false)
        #expect(row.accessibilityLabel?.contains("验证码 482913") == true)
        let tabs = try #require(inbox.view.mailTestView(id: "seek-mail-folder-tabs"))
        #expect(tabs.mailTestView(id: "seek-mail-folder-inbox") != nil)
        let allTag = try #require(inbox.view.mailTestView(id: "seek-mail-tag-all") as? UIButton)
        #expect(allTag.configuration?.attributedTitle.map { String($0.characters) }?.hasPrefix("全部") == true)
        #expect(allTag.accessibilityTraits.contains(.selected))
    }

    @Test func emptyTrashShowsReadOnlyNotice() async throws {
        let transport = SeekMailRouteTransport()
        transport.mailPages = [#"{"data":null,"pagination":{"total":0,"limit":20,"offset":0}}"#]
        let selection = makeSelectionStore()
        selection.scope = .trash
        let inbox = SeekMailInboxViewController(
            keyStore: InMemorySeekMailKeyStore(key: "sk_live_ok"), transport: transport.load, selectionStore: selection
        )
        inbox.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        inbox.loadViewIfNeeded()
        await mailWaitUntil { inbox.model.phase == .loaded }
        inbox.view.layoutIfNeeded()

        #expect((inbox.view.mailTestView(id: "seek-mail-notice") as? UILabel)?.text == "回收站只能查看 · 网页中恢复")
        #expect((inbox.view.mailTestView(id: "seek-mail-state-message") as? UILabel)?.text == "回收站是空的")
    }

    @Test func bottomSearchRequestsOnlyOnSubmitAndClearsOnCancel() async throws {
        let transport = SeekMailRouteTransport()
        let inbox = SeekMailInboxViewController(
            keyStore: InMemorySeekMailKeyStore(key: "sk_live_ok"), transport: transport.load, selectionStore: makeSelectionStore()
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = inbox
        window.isHidden = false
        defer { window.isHidden = true }
        await mailWaitUntil { inbox.model.phase == .loaded }
        inbox.view.layoutIfNeeded()

        let field = try #require(inbox.view.mailTestView(id: "seek-mail-search") as? UITextField)
        let table = try #require(inbox.view.mailTestView(id: "seek-mail-list") as? UITableView)
        #expect(table.contentInset.bottom > 0)
        let before = transport.requests.count

        // 输入时不发请求
        field.text = "invoice"
        field.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(transport.requests.count == before)
        #expect(inbox.model.isSearching == false)

        // 点键盘「搜索」才请求
        _ = field.delegate?.textFieldShouldReturn?(field)
        await mailWaitUntil { transport.requests.last?.url?.query?.contains("search=invoice") == true }
        #expect(inbox.model.isSearching)

        // 取消后回到普通列表
        inbox.searchBar.cancel()
        #expect(inbox.model.isSearching == false)
        #expect(field.text?.isEmpty ?? true)
    }

    @Test func mailboxTagsCollapseToTwoRowsAndKeepSelectionVisible() async throws {
        let transport = SeekMailRouteTransport()
        let boxes = (1...12).map { #"{"id":\#($0),"address":"box\#($0)@seek.li"}"# }.joined(separator: ",")
        transport.mailboxes = #"{"data":[\#(boxes)]}"#
        transport.details["/openapi/v1/mails/counts"] = #"{"data":{"mailboxes":{"3":4},"total":4}}"#
        let selection = makeSelectionStore()
        let inbox = SeekMailInboxViewController(
            keyStore: InMemorySeekMailKeyStore(key: "sk_live_ok"), transport: transport.load, selectionStore: selection
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = inbox
        window.isHidden = false
        defer { window.isHidden = true }
        await mailWaitUntil { inbox.model.phase == .loaded && inbox.model.unreadTotal == 4 }
        // 选中排在最后的邮箱，折叠后也要看得到
        inbox.model.selectMailbox(12)
        await mailWaitUntil { inbox.model.phase == .loaded }
        inbox.view.layoutIfNeeded()

        let tagsView = try #require(inbox.view.mailTestView(id: "seek-mail-tags"))
        let toggle = try #require(tagsView.mailTestView(id: "seek-mail-tags-toggle") as? UIButton)
        func title(_ button: UIButton?) -> String? { button?.configuration?.attributedTitle.map { String($0.characters) } }
        func visibleTags() -> [UIButton] {
            tagsView.subviews.flatMap(\.subviews).compactMap { $0 as? UIButton }
                .filter { $0.isHidden == false && $0.accessibilityIdentifier?.hasPrefix("seek-mail-tag-") == true }
        }

        // 折叠：最多两行，末尾「展开 N 个」，选中的邮箱虽然排在最后也要看得到
        #expect(toggle.isHidden == false)
        #expect(title(toggle)?.hasPrefix("展开") == true)
        #expect(visibleTags().allSatisfy { $0.frame.maxY <= 8 + 30 * 2 + 8 })
        #expect(visibleTags().contains { $0.accessibilityIdentifier == "seek-mail-tag-12" })
        // 有未读的邮箱排在前面，标签带未读数
        #expect(title(tagsView.mailTestView(id: "seek-mail-tag-3") as? UIButton) == "box3 (4)")
        #expect(title(tagsView.mailTestView(id: "seek-mail-tag-all") as? UIButton) == "全部 (4)")

        // 展开后显示全部，状态记住
        toggle.sendActions(for: .touchUpInside)
        inbox.view.layoutIfNeeded()
        #expect(visibleTags().count == 13)
        #expect(title(toggle) == "收起")
        #expect(selection.tagsExpanded)

        // 点标签切换邮箱
        (tagsView.mailTestView(id: "seek-mail-tag-3") as? UIButton)?.sendActions(for: .touchUpInside)
        #expect(inbox.model.selectedMailboxID == 3)
    }
}
