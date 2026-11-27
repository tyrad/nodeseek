import UIKit
import WebKit

/// 官网付款页要求由原帖打开，并通过 opener 回传结果。保留真正的网页父子窗口。
final class StardustPaymentViewController: BaseWebViewController {
    private let receipt: StardustReceipt
    private var paymentWindow: WKWebView?
    override var usesCustomUserAgent: Bool { false }

    init(postURL: URL, receipt: StardustReceipt) {
        self.receipt = receipt
        super.init(initialURL: postURL, pageTitle: DetailListStrings.text("stardust-payment"))
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        super.webView(webView, didFinish: navigation)
        guard webView === self.webView, paymentWindow == nil,
              webView.url?.host == initialURL.host, webView.url?.scheme == "https",
              webView.url?.path == initialURL.path else { return }
        Task {
            do {
                // 官网会在初始化后把正文链接替换成收款卡。只点收款卡，确认转账由用户在子窗口操作。
                _ = try await webView.callAsyncJavaScript(Self.openCard, arguments: [
                    "member": String(receipt.memberID), "ref": String(receipt.referenceID)
                ], in: nil, contentWorld: .page)
            } catch {
                navigationItem.prompt = DetailListStrings.text("stardust-card-unavailable")
                AppLog.warning(.webView, "打开官网收款卡失败：\(error.localizedDescription)")
            }
        }
    }

    private static let openCard = """
    const find = () => Array.from(document.querySelectorAll('.stardust-panel svg.stardust-pay-abstract')).find(svg =>
        svg.querySelector('image')?.getAttribute('href') === '/avatar/' + member + '.png' &&
        Array.from(svg.querySelectorAll('text')).some(text => text.textContent.trim() === 'Ref ID ' + ref)
    );
    const card = find() || await new Promise(resolve => {
        const observer = new MutationObserver(() => {
            const svg = find();
            if (svg) { clearTimeout(timer); observer.disconnect(); resolve(svg); }
        });
        const timer = setTimeout(() => { observer.disconnect(); resolve(null); }, 10000);
        observer.observe(document.body, {childList: true, subtree: true, attributes: true});
    });
    if (!card) throw new Error('Stardust card unavailable');
    card.parentElement.click();
    return true;
    """

    override func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                          for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard webView === self.webView, paymentWindow == nil, navigationAction.targetFrame == nil,
              navigationAction.sourceFrame.isMainFrame, let url = navigationAction.request.url,
              receipt.matchesPayment(url) else { return nil }
        let child = WKWebView(frame: .zero, configuration: configuration)
        child.uiDelegate = self
        child.navigationDelegate = self
        child.translatesAutoresizingMaskIntoConstraints = false
        paymentWindow = child
        webView.isHidden = true
        view.addSubview(child)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: safe.leadingAnchor), child.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            child.topAnchor.constraint(equalTo: safe.topAnchor), child.bottomAnchor.constraint(equalTo: safe.bottomAnchor)
        ])
        navigationItem.rightBarButtonItem = nil
        return child
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard webView === paymentWindow else { return }
        if navigationController?.viewControllers.first === self {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
}
