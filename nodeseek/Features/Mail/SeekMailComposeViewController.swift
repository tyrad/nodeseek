//
//  SeekMailComposeViewController.swift
//  nodeseek
//

import UIKit

/// 写信和回复。只支持纯文本，接口不支持附件，所以不放附件按钮。
final class SeekMailComposeViewController: UIViewController {
    private let provider: SeekMailProvider<SeekMailAPI>
    private let mailboxes: [SeekMailbox]
    private let names: [Int64: SeekMailboxDisplay]
    private var content: SeekMailComposeContent
    private let initialContent: SeekMailComposeContent
    /// 发送成功后回调，由列表页提示「已提交发送」。
    private let onSent: () -> Void
    private var sendTask: Task<Void, Never>?

    private let scrollView = UIScrollView()
    private let senderButton = UIButton(type: .system)
    private let toField = UITextField()
    private let ccField = UITextField()
    private let ccRow = UIView()
    private let ccToggle = UIButton(type: .system)
    private let subjectField = UITextField()
    private let bodyView = UITextView()
    private let errorLabel = UILabel()
    private lazy var sendItem = UIBarButtonItem(title: "发送", primaryAction: UIAction { [weak self] _ in self?.send() })

    init(provider: SeekMailProvider<SeekMailAPI>, mailboxes: [SeekMailbox], names: [Int64: SeekMailboxDisplay],
         content: SeekMailComposeContent, onSent: @escaping () -> Void) {
        self.provider = provider
        self.mailboxes = mailboxes
        self.names = names
        var content = content
        content.mailboxID = SeekMailComposeContent.defaultSender(in: mailboxes, preferred: content.mailboxID)
        self.content = content
        initialContent = content
        self.onSent = onSent
        super.init(nibName: nil, bundle: nil)
        title = content.subject.isEmpty ? "写信" : "回复"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { sendTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.cancelTapped()
        })
        sendItem.style = .done
        // 黑白主题：主按钮用文字色，不用系统蓝
        sendItem.tintColor = .label
        sendItem.accessibilityIdentifier = "seek-mail-compose-send"
        navigationItem.rightBarButtonItem = sendItem
        setupLayout()
        fill()
        updateSender()
        updateSendButton()
        // 有草稿时：回复把光标放在正文开头，写新信放在收件人
        if content.to.isEmpty { toField.becomeFirstResponder() } else { bodyView.becomeFirstResponder() }
        bodyView.selectedRange = NSRange(location: 0, length: 0)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.presentationController?.delegate = self
    }

    // MARK: - 布局

    private func setupLayout() {
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        var senderConfiguration = UIButton.Configuration.plain()
        senderConfiguration.baseForegroundColor = .label
        senderConfiguration.image = UIImage(systemName: "chevron.up.chevron.down")
        senderConfiguration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        senderConfiguration.imagePlacement = .trailing
        senderConfiguration.imagePadding = 4
        senderConfiguration.contentInsets = .zero
        senderConfiguration.titleLineBreakMode = .byTruncatingMiddle
        senderButton.configuration = senderConfiguration
        senderButton.showsMenuAsPrimaryAction = true
        senderButton.contentHorizontalAlignment = .leading
        senderButton.accessibilityIdentifier = "seek-mail-compose-sender"

        configure(toField, placeholder: "多个地址用逗号分隔", identifier: "seek-mail-compose-to", keyboard: .emailAddress)
        configure(ccField, placeholder: "抄送地址", identifier: "seek-mail-compose-cc", keyboard: .emailAddress)
        configure(subjectField, placeholder: "主题", identifier: "seek-mail-compose-subject", keyboard: .default)
        subjectField.autocapitalizationType = .sentences

        var ccConfiguration = UIButton.Configuration.plain()
        ccConfiguration.title = "抄送"
        ccConfiguration.baseForegroundColor = .secondaryLabel
        ccConfiguration.contentInsets = .zero
        ccToggle.configuration = ccConfiguration
        ccToggle.accessibilityIdentifier = "seek-mail-compose-cc-toggle"
        ccToggle.setContentHuggingPriority(.required, for: .horizontal)
        ccToggle.addAction(UIAction { [weak self] _ in self?.showCC() }, for: .touchUpInside)

        bodyView.font = SeekMailFont.of(.body)
        bodyView.textColor = .label
        bodyView.backgroundColor = .clear
        bodyView.isScrollEnabled = false
        bodyView.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        bodyView.textContainer.lineFragmentPadding = 0
        bodyView.delegate = self
        bodyView.accessibilityIdentifier = "seek-mail-compose-body"
        bodyView.accessibilityLabel = "正文"

        errorLabel.font = SeekMailFont.of(.footnote)
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        errorLabel.accessibilityIdentifier = "seek-mail-compose-error"

        let senderRow = makeRow(title: "发件人", content: senderButton)
        let toRow = makeRow(title: "收件人", content: toField, trailing: ccToggle)
        let ccContent = makeRow(title: "抄送", content: ccField)
        ccContent.translatesAutoresizingMaskIntoConstraints = false
        ccRow.addSubview(ccContent)
        NSLayoutConstraint.activate([
            ccContent.topAnchor.constraint(equalTo: ccRow.topAnchor),
            ccContent.bottomAnchor.constraint(equalTo: ccRow.bottomAnchor),
            ccContent.leadingAnchor.constraint(equalTo: ccRow.leadingAnchor),
            ccContent.trailingAnchor.constraint(equalTo: ccRow.trailingAnchor)
        ])
        ccRow.isHidden = true
        let subjectRow = makeRow(title: "主题", content: subjectField)

        let stack = UIStackView(arrangedSubviews: [senderRow, toRow, ccRow, subjectRow, errorLabel, bodyView])
        stack.axis = .vertical
        stack.setCustomSpacing(8, after: subjectRow)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            bodyView.heightAnchor.constraint(greaterThanOrEqualToConstant: 240)
        ])
    }

    private func configure(_ field: UITextField, placeholder: String, identifier: String, keyboard: UIKeyboardType) {
        field.placeholder = placeholder
        field.font = SeekMailFont.of(.body)
        field.keyboardType = keyboard
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.clearButtonMode = .whileEditing
        field.accessibilityIdentifier = identifier
        field.addAction(UIAction { [weak self] _ in self?.fieldsChanged() }, for: .editingChanged)
    }

    /// 一行：灰色标题 + 输入内容 + 底部细分割线。
    private func makeRow(title: String, content: UIView, trailing: UIView? = nil) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = SeekMailFont.of(.body)
        label.textColor = .secondaryLabel
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        content.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [label, content] + (trailing.map { [$0] } ?? []))
        row.spacing = 10
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        return row
    }

    private func fill() {
        toField.text = content.to
        ccField.text = content.cc
        subjectField.text = content.subject
        bodyView.text = content.body
        if content.cc.isEmpty == false { showCC() }
    }

    private func showCC() {
        ccRow.isHidden = false
        ccToggle.isHidden = true
        ccField.becomeFirstResponder()
    }

    // MARK: - 发件邮箱

    /// nodeseek.org 的邮箱显示为禁用，并说明原因。
    private func updateSender() {
        let actions = mailboxes.map { mailbox in
            let display = names[mailbox.id]
            let title = display.map { $0.title + ($0.domainSuffix ?? "") } ?? mailbox.address
            return UIAction(
                title: title,
                subtitle: mailbox.canSendMail ? (display?.hasAlias == true ? mailbox.address : nil) : "该域名不支持发信",
                attributes: mailbox.canSendMail ? [] : .disabled,
                state: mailbox.id == content.mailboxID ? .on : .off
            ) { [weak self] _ in
                self?.content.mailboxID = mailbox.id
                self?.updateSender()
                self?.updateSendButton()
            }
        }
        senderButton.menu = UIMenu(children: actions)
        let selected = mailboxes.first { $0.id == content.mailboxID }
        senderButton.configuration?.title = selected?.address ?? "没有可用的发件邮箱"
    }

    // MARK: - 发送

    private func fieldsChanged() {
        content.to = toField.text ?? ""
        content.cc = ccField.text ?? ""
        content.subject = subjectField.text ?? ""
        content.body = bodyView.text ?? ""
        errorLabel.isHidden = true
        // 有改动时禁止下滑直接关掉，改为走放弃确认
        navigationController?.isModalInPresentation = hasEdits
        updateSendButton()
    }

    private func updateSendButton() {
        sendItem.isEnabled = sendTask == nil && content.mailboxID != nil
            && SeekMailComposeContent.addresses(from: content.to).isEmpty == false
    }

    private func showError(_ message: String) {
        errorLabel.text = message
        errorLabel.isHidden = false
    }

    private func send() {
        fieldsChanged()
        if let problem = content.problem {
            showError(problem.message)
            return
        }
        guard let draft = content.draft, sendTask == nil else { return }
        view.endEditing(true)
        // 发送中按钮变成菊花，防止重复提交
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
        sendTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await provider.send(draft)
                sendTask = nil
                onSent()
                dismiss(animated: true)
            } catch is CancellationError {
                sendTask = nil
            } catch {
                // 失败时保留草稿，显示服务端给的原因
                sendTask = nil
                navigationItem.rightBarButtonItem = sendItem
                updateSendButton()
                showError((error as? SeekMailError)?.userMessage ?? "发送失败，请稍后重试")
            }
        }
        updateSendButton()
    }

    private var hasEdits: Bool {
        var current = content
        current.to = toField.text ?? ""
        current.cc = ccField.text ?? ""
        current.subject = subjectField.text ?? ""
        current.body = bodyView.text ?? ""
        return current != initialContent
    }

    private func cancelTapped() {
        guard hasEdits, sendTask == nil else {
            dismiss(animated: true)
            return
        }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "放弃这封邮件", style: .destructive) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        sheet.addAction(UIAlertAction(title: "继续编辑", style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.leftBarButtonItem
        present(sheet, animated: true)
    }
}

extension SeekMailComposeViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        cancelTapped()
    }
}

extension SeekMailComposeViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        fieldsChanged()
    }
}
