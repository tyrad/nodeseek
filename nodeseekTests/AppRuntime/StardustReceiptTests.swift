import UIKit
import XCTest
@testable import nodeseek

@MainActor
final class StardustReceiptTests: XCTestCase {
    private let source = "nsapp://stardust-receive?member_id=32297&ref_id=48395171&description=C%2B%2B%20%26%20VPS&diff=100&onetime=true"

    func testHTMLAndRoutesPreserveReceiptFields() throws {
        let receipt = try XCTUnwrap(StardustReceipt(url: XCTUnwrap(URL(string: source))))
        XCTAssertEqual(receipt.note, "C++ & VPS")
        XCTAssertTrue(receipt.paymentURL.absoluteString.contains("C%2B%2B"))
        XCTAssertEqual(receipt.ledgerURL.query, "member_id=32297&ref_id=48395171")
        let popup = try XCTUnwrap(URL(string: receipt.paymentURL.absoluteString.replacingOccurrences(of: "%20", with: "+") + "&nonce=example"))
        XCTAssertTrue(receipt.matchesPayment(popup))
        XCTAssertFalse(receipt.matchesPayment(try XCTUnwrap(URL(string: popup.absoluteString + "&diff=10"))))
        guard case .stardust(let targetReceipt) = PostDetailLinkResolver.destination(for: receipt.sourceURL, baseURL: NodeSeekSite.baseURL) else {
            return XCTFail("收款卡应通过官网原帖打开确认窗口")
        }
        XCTAssertEqual(targetReceipt, receipt)
        guard case .web(let ledger) = PostDetailLinkResolver.destination(for: receipt.ledgerURL, baseURL: NodeSeekSite.baseURL) else {
            return XCTFail("流水应在官网 WebView 打开")
        }
        XCTAssertEqual(ledger, receipt.ledgerURL)
        let escaped = source.replacingOccurrences(of: "&", with: "&amp;")
        let html = "<blockquote><p><a href='javascript://void(0)' data-href='\(escaped)'>收款</a></p></blockquote>"
        let blocks = DTCoreTextHTMLContentRenderer().render(fragment: html, baseURL: NodeSeekSite.baseURL)
        guard case .quote(let quote) = blocks.first, case .stardust(let embedded) = quote.children.first else {
            return XCTFail("HTML 中的收款卡应保留引用结构")
        }
        XCTAssertEqual(embedded, receipt)
        XCTAssertEqual(CommentCopyTextFormatter.plainText(from: blocks), source)
        for invalid in [source + "&diff=1", source.replacingOccurrences(of: "diff=100", with: "diff=-1")] {
            XCTAssertNil(StardustReceipt(url: try XCTUnwrap(URL(string: invalid))))
        }
    }

    func testCardActionsRefreshAfterReturnAndFitNarrowWidth() async throws {
        let receipt = try XCTUnwrap(StardustReceipt(url: XCTUnwrap(URL(string: source))))
        var visits = [URL]()
        var loads = 0
        let card = DetailStardustView(receipt: receipt, open: { visits.append($0) }) { _ in
            loads += 1
            return .init(paid: loads > 1, count: loads - 1, total: (loads - 1) * 100)
        }
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.addSubview(card)
        card.frame = CGRect(x: 16, y: 48, width: 268, height: 120)
        card.layoutIfNeeded()
        let payment = try XCTUnwrap(card.arrangedSubviews.first as? UIButton)
        let ledger = try XCTUnwrap(card.arrangedSubviews.last as? UIButton)
        await Task.yield()
        XCTAssertLessThanOrEqual(payment.bounds.width, 268)
        XCTAssertGreaterThanOrEqual(payment.bounds.height, 70)
        payment.sendActions(for: .touchUpInside)
        ledger.sendActions(for: .touchUpInside)
        XCTAssertEqual(visits, [receipt.sourceURL, receipt.ledgerURL])
        card.removeFromSuperview()
        controller.view.addSubview(card)
        await Task.yield()
        XCTAssertEqual(loads, 2)
        XCTAssertTrue(ledger.attributedTitle(for: .normal)?.string.contains("100") == true)
    }
}
