//
//  SeekMailDetailViewController.swift
//  nodeseek
//

import QuickLook
import UIKit
import WebKit

/// 邮件详情：头部、正文（HTML 或纯文本）、附件；底部工具栏放移动、标为未读、删除。
final class SeekMailDetailViewController: UIViewController {
    private let mailID: Int64
    private let model: SeekMailInboxModel
    /// 删除交给列表页处理，回到列表后显示可撤销的 toast。
    private let onDelete: (Int64) -> Void
    /// 回复由列表页弹出写信页，发送结果也在列表页提示。
    private let onReply: ((SeekMailComposeContent) -> Void)?

    private var mail: SeekMail?
    private var attachments: [SeekMailAttachment] = []
    private var loadTask: Task<Void, Never>?
    private var previewURL: URL?
    private var allowsRemoteImages = false

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let errorView = UIStackView()
    private var webView: WKWebView?
    private var webHeight: NSLayoutConstraint?
    private var contentSizeObservation: NSKeyValueObservation?
    private let imageBanner = UIButton(type: .system)
    private lazy var starItem = UIBarButtonItem(image: UIImage(systemName: "star"), primaryAction: UIAction { [weak self] _ in
        self?.toggleFlag()
    })

    init(mailID: Int64, model: SeekMailInboxModel, onDelete: @escaping (Int64) -> Void,
         onReply: ((SeekMailComposeContent) -> Void)? = nil) {
        self.mailID = mailID
        self.model = model
        self.onDelete = onDelete
        self.onReply = onReply
        super.init(nibName: nil, bundle: nil)
        mail = model.mail(id: mailID)
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        loadTask?.cancel()
        if let previewURL { try? FileManager.default.removeItem(at: previewURL.deletingLastPathComponent()) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        starItem.accessibilityIdentifier = "seek-mail-detail-star"
        navigationItem.rightBarButtonItem = starItem
        setupLayout()
        updateToolbar()
        load()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
    }

    // MARK: - 加载

    /// 打开就标已读，失败不提示；一封邮件只发详情 + 标已读两个请求，有附件时再多一个。
    private func load() {
        spinner.startAnimating()
        errorView.isHidden = true
        model.markOpened(mailID)
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let detail = try await model.provider.mail(id: mailID)
                mail = detail.mail
                render(detail.mail)
                if detail.mail.hasAttachments {
                    attachments = (try? await model.provider.attachments(mailID: mailID))?.filter { $0.isInline != true } ?? []
                    renderAttachments()
                }
            } catch is CancellationError {
            } catch {
                spinner.stopAnimating()
                showError(error)
            }
        }
    }

    private func showError(_ error: Error) {
        if case .unauthorized? = error as? SeekMailError {
            model.onUnauthorized?()
            return
        }
        let label = errorView.arrangedSubviews.first as? UILabel
        label?.text = (error as? SeekMailError)?.userMessage ?? "加载失败，请稍后重试"
        errorView.isHidden = false
    }

    // MARK: - 布局

    private func setupLayout() {
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        let errorLabel = UILabel()
        errorLabel.font = .preferredFont(forTextStyle: .subheadline)
        errorLabel.textColor = .secondaryLabel
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        errorLabel.accessibilityIdentifier = "seek-mail-detail-error"
        var retry = UIButton.Configuration.filled()
        retry.baseBackgroundColor = .label
        retry.baseForegroundColor = .systemBackground
        retry.cornerStyle = .capsule
        retry.title = "重试"
        let retryButton = UIButton(configuration: retry, primaryAction: UIAction { [weak self] _ in self?.load() })
        [errorLabel, retryButton].forEach(errorView.addArrangedSubview)
        errorView.axis = .vertical
        errorView.alignment = .center
        errorView.spacing = 12
        errorView.isHidden = true
        errorView.translatesAutoresizingMaskIntoConstraints = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(errorView)
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            errorView.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            errorView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 24),
            errorView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -24)
        ])
    }

    private func render(_ mail: SeekMail) {
        spinner.stopAnimating()
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        updateStar()
        updateToolbar()

        stack.addArrangedSubview(makeHeader(mail))
        if SeekMailDetailContent.hasAuthFailure(scoreDetails: mail.scoreDetails) {
            stack.addArrangedSubview(makeNotice("发件人未通过验证，请留意邮件里的链接", symbol: "exclamationmark.shield"))
        }
        if let code = mail.verificationCode {
            stack.addArrangedSubview(makeCodeBar(code))
        }
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.heightAnchor.constraint(equalToConstant: 1 / max(view.traitCollection.displayScale, 1)).isActive = true
        stack.addArrangedSubview(separator)

        if mail.bodyHtml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            renderHTML(mail.bodyHtml)
        } else {
            stack.addArrangedSubview(makeTextBody(mail.bodyText))
        }
    }

    private func makeHeader(_ mail: SeekMail) -> UIView {
        let subject = UILabel()
        subject.text = mail.subject.isEmpty ? "（无主题）" : mail.subject
        subject.font = UIFont.preferredFont(forTextStyle: .title2).withSymbolicTraits(.traitBold)
        subject.adjustsFontForContentSizeCategory = true
        subject.numberOfLines = 0
        subject.accessibilityIdentifier = "seek-mail-detail-subject"

        let sender = UILabel()
        let name = mail.fromName ?? mail.fromAddress
        var senderText = AttributedString(name)
        senderText.font = UIFont.preferredFont(forTextStyle: .subheadline).withSymbolicTraits(.traitBold)
        senderText.foregroundColor = .label
        if mail.fromName != nil {
            var address = AttributedString("  \(mail.fromAddress)")
            address.font = UIFont.preferredFont(forTextStyle: .subheadline)
            address.foregroundColor = .secondaryLabel
            senderText += address
        }
        sender.attributedText = NSAttributedString(senderText)
        sender.numberOfLines = 0

        let time = UILabel()
        time.text = SeekMailFormat.detailTime(mail.receivedAt)
        time.font = .preferredFont(forTextStyle: .footnote)
        time.textColor = .secondaryLabel

        // 收件地址始终显示完整地址，长按复制
        let recipient = UILabel()
        let address = mail.toAddress ?? model.mailboxes.first { $0.id == mail.mailboxId }?.address ?? ""
        recipient.text = "发给 \(address)"
        recipient.font = .preferredFont(forTextStyle: .footnote)
        recipient.textColor = .secondaryLabel
        recipient.lineBreakMode = .byTruncatingMiddle
        recipient.isUserInteractionEnabled = true
        recipient.accessibilityIdentifier = "seek-mail-detail-recipient"
        recipient.accessibilityHint = "长按复制收件地址"
        recipient.addGestureRecognizer(SeekMailLongPress { [weak self] in
            UIPasteboard.general.string = address
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self?.showToast("已复制收件地址")
        })

        let header = UIStackView(arrangedSubviews: [subject, sender, time, recipient])
        header.axis = .vertical
        header.spacing = 4
        header.setCustomSpacing(10, after: subject)
        return header
    }

    private func makeNotice(_ text: String, symbol: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = .secondaryLabel
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.spacing = 6
        row.alignment = .center
        row.accessibilityIdentifier = "seek-mail-detail-auth-warning"
        return row
    }

    /// 验证码反色条，一键复制。
    private func makeCodeBar(_ code: String) -> UIView {
        let bar = UIView()
        bar.backgroundColor = .label
        bar.layer.cornerRadius = 12
        bar.layer.cornerCurve = .continuous
        let title = UILabel()
        title.text = "验证码"
        title.font = .preferredFont(forTextStyle: .footnote)
        title.textColor = .systemBackground.withAlphaComponent(0.7)
        let codeLabel = UILabel()
        codeLabel.text = code
        codeLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .bold)
        codeLabel.textColor = .systemBackground
        codeLabel.adjustsFontSizeToFitWidth = true
        codeLabel.accessibilityIdentifier = "seek-mail-detail-code"
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = .systemBackground
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .capsule
        configuration.title = "复制"
        let copy = UIButton(configuration: configuration)
        copy.accessibilityIdentifier = "seek-mail-detail-copy-code"
        copy.setContentHuggingPriority(.required, for: .horizontal)
        copy.addAction(UIAction { [weak copy] _ in
            guard let copy else { return }
            UIPasteboard.general.string = code
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            copy.configuration?.title = "已复制"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak copy] in copy?.configuration?.title = "复制" }
        }, for: .touchUpInside)
        let text = UIStackView(arrangedSubviews: [title, codeLabel])
        text.axis = .vertical
        let row = UIStackView(arrangedSubviews: [text, copy])
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: bar.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -10)
        ])
        return bar
    }

    private func makeTextBody(_ text: String) -> UIView {
        let textView = UITextView()
        textView.text = text
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.dataDetectorTypes = [.link, .phoneNumber]
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.accessibilityIdentifier = "seek-mail-detail-text"
        return textView
    }

    // MARK: - HTML 正文

    /// index 用于加载远程图片后原位替换，正文不能跑到附件后面。
    private func renderHTML(_ html: String, at index: Int? = nil) {
        let remoteImages = SeekMailDetailContent.remoteImageCount(in: html)
        if remoteImages > 0, allowsRemoteImages == false {
            var configuration = UIButton.Configuration.gray()
            configuration.baseForegroundColor = .label
            configuration.cornerStyle = .medium
            configuration.image = UIImage(systemName: "photo")
            configuration.imagePadding = 6
            configuration.title = "已阻止 \(remoteImages) 张远程图片 · 加载"
            configuration.titleLineBreakMode = .byTruncatingTail
            imageBanner.configuration = configuration
            imageBanner.contentHorizontalAlignment = .leading
            imageBanner.accessibilityIdentifier = "seek-mail-detail-load-images"
            imageBanner.removeTarget(nil, action: nil, for: .allEvents)
            imageBanner.addAction(UIAction { [weak self] _ in self?.loadRemoteImages() }, for: .touchUpInside)
            stack.addArrangedSubview(imageBanner)
        }

        let configuration = WKWebViewConfiguration()
        // 邮件里的脚本一律不执行
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        configuration.dataDetectorTypes = [.link, .phoneNumber]
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = self
        webView.accessibilityIdentifier = "seek-mail-detail-web"
        let height = webView.heightAnchor.constraint(equalToConstant: 200)
        height.isActive = true
        webHeight = height
        contentSizeObservation = webView.scrollView.observe(\.contentSize, options: [.new]) { [weak self] scrollView, _ in
            MainActor.assumeIsolated {
                let newHeight = max(scrollView.contentSize.height, 40)
                guard let self, abs((self.webHeight?.constant ?? 0) - newHeight) > 1 else { return }
                self.webHeight?.constant = newHeight
            }
        }
        if let index, index <= stack.arrangedSubviews.count {
            stack.insertArrangedSubview(webView, at: index)
        } else {
            stack.addArrangedSubview(webView)
        }
        self.webView = webView

        let wrapped = SeekMailDetailContent.wrappedHTML(html)
        guard allowsRemoteImages == false else {
            webView.loadHTMLString(wrapped, baseURL: nil)
            return
        }
        Self.remoteImageRule { [weak webView] rule in
            guard let webView else { return }
            if let rule { webView.configuration.userContentController.add(rule) }
            webView.loadHTMLString(wrapped, baseURL: nil)
        }
    }

    /// 只对这一封生效：重新渲染时不再加拦截规则。
    private func loadRemoteImages() {
        guard let mail else { return }
        allowsRemoteImages = true
        imageBanner.removeFromSuperview()
        let index = webView.flatMap { stack.arrangedSubviews.firstIndex(of: $0) }
        webView?.removeFromSuperview()
        contentSizeObservation = nil
        renderHTML(mail.bodyHtml, at: index)
    }

    private static var cachedRule: WKContentRuleList?

    private static func remoteImageRule(_ completion: @escaping @MainActor (WKContentRuleList?) -> Void) {
        if let cachedRule { return completion(cachedRule) }
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "seek-mail-block-remote-images",
            encodedContentRuleList: SeekMailDetailContent.blockRemoteImagesRule
        ) { rule, error in
            MainActor.assumeIsolated {
                if let error { AppLog.warning(.service, "邮件远程图片拦截规则编译失败: \(error)") }
                cachedRule = rule
                completion(rule)
            }
        }
    }

    // MARK: - 附件

    private func renderAttachments() {
        guard attachments.isEmpty == false else { return }
        let header = UILabel()
        header.text = "附件 \(attachments.count)"
        header.font = .preferredFont(forTextStyle: .footnote)
        header.textColor = .secondaryLabel
        stack.addArrangedSubview(header)
        stack.setCustomSpacing(6, after: header)
        for attachment in attachments {
            var configuration = UIButton.Configuration.gray()
            configuration.baseForegroundColor = .label
            configuration.cornerStyle = .medium
            configuration.image = UIImage(systemName: Self.symbol(for: attachment))
            configuration.imagePadding = 10
            configuration.title = attachment.filename
            configuration.subtitle = attachment.size.map { SeekMailFormat.bytes($0) }
            configuration.titleLineBreakMode = .byTruncatingMiddle
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
            let button = UIButton(configuration: configuration)
            button.contentHorizontalAlignment = .leading
            button.accessibilityIdentifier = "seek-mail-detail-attachment-\(attachment.index)"
            button.addAction(UIAction { [weak self, weak button] _ in
                guard let button else { return }
                self?.openAttachment(attachment, button: button)
            }, for: .touchUpInside)
            stack.addArrangedSubview(button)
            stack.setCustomSpacing(8, after: button)
        }
    }

    private static func symbol(for attachment: SeekMailAttachment) -> String {
        let type = attachment.contentType?.lowercased() ?? ""
        if type.hasPrefix("image/") { return "photo" }
        if type.contains("pdf") { return "doc.richtext" }
        if type.contains("zip") || type.contains("compressed") { return "doc.zipper" }
        return "doc"
    }

    /// 先下载到临时目录，再用系统预览打开，可以分享。
    private func openAttachment(_ attachment: SeekMailAttachment, button: UIButton) {
        button.configuration?.showsActivityIndicator = true
        button.isEnabled = false
        Task { [weak self] in
            defer {
                button.configuration?.showsActivityIndicator = false
                button.isEnabled = true
            }
            guard let self else { return }
            do {
                let file = try await model.provider.downloadAttachment(mailID: mailID, index: attachment.index)
                let url = try Self.writeTemporary(file, fallbackName: attachment.filename)
                if let previewURL { try? FileManager.default.removeItem(at: previewURL.deletingLastPathComponent()) }
                previewURL = url
                let preview = QLPreviewController()
                preview.dataSource = self
                present(preview, animated: true)
            } catch {
                showToast((error as? SeekMailError)?.userMessage ?? "附件下载失败")
            }
        }
    }

    private static func writeTemporary(_ file: SeekMailFile, fallbackName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("seek-mail-attachments", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // 文件名来自服务端，去掉路径分隔符，防止写到目录外
        let rawName = (file.filename?.isEmpty == false ? file.filename! : fallbackName)
        let name = rawName.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let url = directory.appendingPathComponent(name.isEmpty ? "attachment" : name)
        try file.data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - 工具栏和操作

    private func updateStar() {
        let flagged = model.mail(id: mailID)?.isFlagged ?? mail?.isFlagged ?? false
        starItem.image = UIImage(systemName: flagged ? "star.fill" : "star")
        starItem.tintColor = flagged ? .systemOrange : .label
        starItem.accessibilityLabel = flagged ? "去掉星标" : "加星标"
    }

    private func toggleFlag() {
        let flagged = model.mail(id: mailID)?.isFlagged ?? mail?.isFlagged ?? false
        model.setFlagged(mailID, flagged: flagged == false)
        updateStar()
    }

    private func updateToolbar() {
        let unread = UIBarButtonItem(image: UIImage(systemName: "envelope.badge"), primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            model.setRead(mailID, read: false)
            navigationController?.popViewController(animated: true)
        })
        unread.accessibilityLabel = "标为未读"
        unread.accessibilityIdentifier = "seek-mail-detail-unread"
        let flexible = UIBarButtonItem(systemItem: .flexibleSpace)
        var replyItems: [UIBarButtonItem] = []
        if let onReply, model.canCompose, let mail {
            let reply = UIBarButtonItem(image: UIImage(systemName: "arrowshape.turn.up.left"), primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                onReply(SeekMailComposeContent.reply(to: mail, mailboxes: model.mailboxes))
            })
            reply.accessibilityLabel = "回复"
            reply.accessibilityIdentifier = "seek-mail-detail-reply"
            replyItems = [flexible, reply]
        }
        // 回收站只读：不移动、不删除
        guard model.isTrash == false else {
            toolbarItems = [flexible, unread] + replyItems + [flexible]
            return
        }
        var targets: [(String, Int64?, SeekMailFolderScope)] = [("收件箱", nil, .inbox)]
        targets += model.folders.map { (model.title(for: .custom($0.id)), $0.id, .custom($0.id)) }
        let moveActions = targets.filter { $0.2 != model.scope }.map { title, folderID, _ in
            UIAction(title: title) { [weak self] _ in
                guard let self else { return }
                model.move(mailID, toFolderID: folderID)
                navigationController?.popViewController(animated: true)
            }
        }
        let move = UIBarButtonItem(image: UIImage(systemName: "folder"), menu: UIMenu(title: "移动到…", children: moveActions))
        move.accessibilityLabel = "移动到"
        move.isEnabled = moveActions.isEmpty == false
        let delete = UIBarButtonItem(image: UIImage(systemName: "trash"), primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            navigationController?.popViewController(animated: true)
            onDelete(mailID)
        })
        delete.accessibilityLabel = "删除"
        delete.accessibilityIdentifier = "seek-mail-detail-delete"
        toolbarItems = [move, flexible, unread] + replyItems + [flexible, delete]
    }

    private func showToast(_ message: String) {
        SeekMailUndoToast().showMessage(message, in: view)
    }
}

extension SeekMailDetailViewController: WKNavigationDelegate {
    /// 点链接用系统方式打开：很多验证邮件给的是登录链接，这样才能跳回对应的 App。
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        // 只允许加载邮件正文本身，不让正文里的跳转把页面带走
        let isInitialLoad = navigationAction.request.url?.absoluteString == "about:blank"
        decisionHandler(isInitialLoad || navigationAction.targetFrame?.isMainFrame == false ? .allow : .cancel)
    }
}

extension SeekMailDetailViewController: QLPreviewControllerDataSource {
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        (previewURL ?? URL(fileURLWithPath: "/")) as NSURL
    }
}

/// 收件地址的长按复制。
private final class SeekMailLongPress: UILongPressGestureRecognizer {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(fire))
    }

    @objc private func fire() {
        if state == .began { handler() }
    }
}

private extension UIFont {
    func withSymbolicTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
