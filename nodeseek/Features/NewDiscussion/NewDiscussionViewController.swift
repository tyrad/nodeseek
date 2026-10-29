//
//  NewDiscussionViewController.swift
//  nodeseek
//

import UIKit

final class NewDiscussionViewController: UIViewController {
    private let presenter: NewDiscussionPresenterProtocol

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let draftStrip = NewDiscussionDraftStripView()
    /// 给草稿卡片留左右边距，显隐都切这个容器。
    private let draftBannerContainer = UIView()
    /// 细条只在旧草稿变化时重新配置，避免每次输入都收起展开状态。
    private var configuredPendingDraft: NewDiscussionDraft?
    private let titleTextView = UITextView()
    private let titlePlaceholder = UILabel()
    private let bodyTextView = UITextView()
    private let bodyPlaceholder = UILabel()
    private let feeNoticeLabel = UILabel()
    /// 保存和上传状态，放在标题分隔线右端，不占工具栏位置。
    private let statusLabel = UILabel()

    private let toolbar = NewDiscussionToolbarView()
    private let linkBar = NewDiscussionLinkBarView()
    /// 打字键盘连同工具条的高度；表情、格式面板按它对齐，切换时工具条不上下跳。
    private var typingKeyboardHeight: CGFloat?
    private var stickerPanelHeight: NSLayoutConstraint?
    private lazy var formatPanel: NewDiscussionFormatPanelView = {
        let panel = NewDiscussionFormatPanelView()
        panel.onSelect = { [weak self] snippet in self?.applySnippet(snippet) }
        return panel
    }()
    private lazy var stickerPanel: UIInputView = makeStickerPanel()
    private let stickerCookieSession = NodeSeekCookieSession()
    private lazy var imageUploader: NewDiscussionImageUploader = makeImageUploader()

    private lazy var settingsButton: UIButton = {
        var configuration = UIButton.Configuration.gray()
        configuration.cornerStyle = .capsule
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 4
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 12)
        configuration.titleLineBreakMode = .byTruncatingTail
        let button = UIButton(configuration: configuration)
        // 交给自动布局按内容算宽度，切换板块后胶囊才会跟着变宽。
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "new-discussion-settings-button"
        button.addAction(UIAction { [weak self] _ in self?.presentSettings() }, for: .touchUpInside)
        return button
    }()

    private lazy var publishButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "发布"
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .label
        configuration.baseForegroundColor = .systemBackground
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        let button = UIButton(configuration: configuration)
        button.accessibilityIdentifier = "new-discussion-publish-button"
        button.addAction(UIAction { [weak self] _ in self?.publishTapped() }, for: .touchUpInside)
        return button
    }()

    private weak var settingsViewController: NewDiscussionSettingsViewController?
    private var lastState: NewDiscussionViewState?

    init(presenter: NewDiscussionPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupNavigationBar()
        setupContent()
        setupToolbar()
        setupLinkBar()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        presenter.viewDidLoad()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 关闭时输入框还在编辑的话，键盘上方的工具条会残留在下层页面上，先统一收起。
        if navigationController?.isBeingDismissed == true || isBeingDismissed {
            view.endEditing(true)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // 整个发帖页被关掉时停掉上传，草稿保存时已去掉占位。
        if navigationController?.isBeingDismissed == true || isBeingDismissed {
            imageUploader.cancelAll()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if titleTextView.text.isEmpty && bodyTextView.text.isEmpty {
            titleTextView.becomeFirstResponder()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            MarkdownEditorStyler.apply(to: bodyTextView)
        }
    }

    // MARK: - 布局

    private func setupNavigationBar() {
        let closeItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            primaryAction: UIAction { [weak self] _ in self?.closeTapped() }
        )
        closeItem.accessibilityLabel = "关闭"
        navigationItem.leftBarButtonItem = closeItem
        navigationItem.titleView = settingsButton
        let publishItem = UIBarButtonItem(customView: publishButton)
        if #available(iOS 26.0, *) {
            // 发布按钮自带实心胶囊，不再套系统玻璃底，避免出现双层边框。
            publishItem.hidesSharedBackground = true
        }
        navigationItem.rightBarButtonItem = publishItem
    }

    private func setupContent() {
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        feeNoticeLabel.font = .preferredFont(forTextStyle: .footnote)
        feeNoticeLabel.adjustsFontForContentSizeCategory = true
        feeNoticeLabel.textColor = .systemOrange
        feeNoticeLabel.textAlignment = .center
        feeNoticeLabel.isHidden = true

        setupDraftBanner()
        setupTitle()

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        let separatorContainer = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separatorContainer.addSubview(separator)
        statusLabel.font = .preferredFont(forTextStyle: .caption2)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .tertiaryLabel
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        separatorContainer.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: separatorContainer.leadingAnchor, constant: 20),
            separator.trailingAnchor.constraint(equalTo: statusLabel.leadingAnchor, constant: -8),
            separator.centerYAnchor.constraint(equalTo: separatorContainer.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: separatorContainer.trailingAnchor, constant: -20),
            statusLabel.topAnchor.constraint(equalTo: separatorContainer.topAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: separatorContainer.bottomAnchor),
            separatorContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 9)
        ])

        setupBody()

        [feeNoticeLabel, draftBannerContainer, titleTextView, separatorContainer, bodyTextView].forEach(contentStack.addArrangedSubview)
        contentStack.setCustomSpacing(8, after: feeNoticeLabel)
        contentStack.setCustomSpacing(8, after: draftBannerContainer)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            // 正文至少占满一屏，点空白处也能开始输入。
            bodyTextView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor, multiplier: 0.6)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(blankAreaTapped))
        tap.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(tap)
    }

    private func setupDraftBanner() {
        draftStrip.onRestore = { [weak self] in self?.presenter.restorePendingDraft() }
        draftStrip.onDiscard = { [weak self] in self?.presenter.discardPendingDraft() }
        draftStrip.translatesAutoresizingMaskIntoConstraints = false
        draftBannerContainer.addSubview(draftStrip)
        draftBannerContainer.isHidden = true
        NSLayoutConstraint.activate([
            draftStrip.topAnchor.constraint(equalTo: draftBannerContainer.topAnchor),
            draftStrip.leadingAnchor.constraint(equalTo: draftBannerContainer.leadingAnchor, constant: 16),
            draftStrip.trailingAnchor.constraint(equalTo: draftBannerContainer.trailingAnchor, constant: -16),
            draftStrip.bottomAnchor.constraint(equalTo: draftBannerContainer.bottomAnchor)
        ])
    }

    private func setupTitle() {
        titleTextView.font = .preferredFont(forTextStyle: .title2).withWeight(.bold)
        titleTextView.adjustsFontForContentSizeCategory = true
        titleTextView.textColor = .label
        titleTextView.backgroundColor = .clear
        titleTextView.isScrollEnabled = false
        titleTextView.textContainerInset = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        titleTextView.returnKeyType = .next
        titleTextView.delegate = self
        titleTextView.accessibilityIdentifier = "new-discussion-title"
        titleTextView.accessibilityLabel = "标题"

        titlePlaceholder.text = "标题"
        titlePlaceholder.font = titleTextView.font
        titlePlaceholder.adjustsFontForContentSizeCategory = true
        titlePlaceholder.textColor = .placeholderText
        addPlaceholder(titlePlaceholder, to: titleTextView)
    }

    private func setupBody() {
        bodyTextView.font = MarkdownEditorStyler.baseFont()
        bodyTextView.adjustsFontForContentSizeCategory = true
        bodyTextView.typingAttributes = MarkdownEditorStyler.baseAttributes()
        bodyTextView.backgroundColor = .clear
        bodyTextView.isScrollEnabled = false
        bodyTextView.textContainerInset = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        bodyTextView.autocapitalizationType = .none
        bodyTextView.smartQuotesType = .no
        bodyTextView.smartDashesType = .no
        bodyTextView.delegate = self
        bodyTextView.accessibilityIdentifier = "new-discussion-body"
        bodyTextView.accessibilityLabel = "正文"

        bodyPlaceholder.text = "鼓励友善发言，禁止人身攻击"
        bodyPlaceholder.font = bodyTextView.font
        bodyPlaceholder.adjustsFontForContentSizeCategory = true
        bodyPlaceholder.textColor = .placeholderText
        addPlaceholder(bodyPlaceholder, to: bodyTextView)
    }

    private func addPlaceholder(_ label: UILabel, to textView: UITextView) {
        label.numberOfLines = 0
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(label)
        let padding = textView.textContainer.lineFragmentPadding
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: textView.topAnchor, constant: textView.textContainerInset.top),
            label.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: textView.textContainerInset.left + padding),
            label.widthAnchor.constraint(equalTo: textView.widthAnchor, constant: -(textView.textContainerInset.left + textView.textContainerInset.right + padding * 2))
        ])
    }

    private func setupToolbar() {
        toolbar.onTap = { [weak self] item in self?.toolbarTapped(item) }
        toolbar.setActive(.keyboard)
        titleTextView.inputAccessoryView = toolbar
        bodyTextView.inputAccessoryView = toolbar
    }

    private func makeStickerPanel() -> UIInputView {
        let panel = UIInputView(frame: CGRect(x: 0, y: 0, width: 0, height: 300), inputViewStyle: .keyboard)
        panel.allowsSelfSizing = true
        let picker = NodeSeekStickerPickerView()
        picker.onSelectSticker = { [weak self] item in self?.insertSticker(item.token) }
        // 回复区的贴纸视图默认隐藏、带卡片底色；放进键盘面板时直接显示并融入键盘背景。
        picker.isHidden = false
        picker.backgroundColor = .clear
        picker.layer.cornerRadius = 0
        picker.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: panel.topAnchor),
            picker.leadingAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.trailingAnchor),
            picker.bottomAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.bottomAnchor)
        ])
        let height = panel.heightAnchor.constraint(equalToConstant: panelHeight)
        height.isActive = true
        stickerPanelHeight = height
        return panel
    }

    private func setupLinkBar() {
        linkBar.isHidden = true
        linkBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(linkBar)
        NSLayoutConstraint.activate([
            linkBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            linkBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            linkBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -6)
        ])
    }

    // MARK: - 面板高度

    /// 还没见过键盘时先用常见高度。
    private var panelHeight: CGFloat {
        guard let typingKeyboardHeight else { return 300 }
        return max(216, typingKeyboardHeight - toolbar.intrinsicContentSize.height)
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let window = view.window else { return }
        let height = window.bounds.maxY - window.convert(frame, from: nil).minY
        // 外接键盘或收起时只剩工具条，不拿来对齐。
        guard height > toolbar.intrinsicContentSize.height + 100 else { return }

        let isTyping = titleTextView.isFirstResponder || (bodyTextView.isFirstResponder && bodyTextView.inputView == nil)
        if isTyping {
            typingKeyboardHeight = height
            applyPanelHeight(panelHeight)
        } else if bodyTextView.isFirstResponder, bodyTextView.inputView != nil, let typingKeyboardHeight, abs(typingKeyboardHeight - height) > 0.5 {
            // 估算和系统实际摆放有出入时校正一次，之后切换就一致了。
            applyPanelHeight(currentPanelHeight + typingKeyboardHeight - height)
            bodyTextView.reloadInputViews()
        }
    }

    private var currentPanelHeight: CGFloat {
        stickerPanelHeight?.constant ?? formatPanel.heightConstraint.constant
    }

    private func applyPanelHeight(_ height: CGFloat) {
        let height = max(216, height)
        formatPanel.heightConstraint.constant = height
        stickerPanelHeight?.constant = height
    }

    // MARK: - 插图

    private func makeImageUploader() -> NewDiscussionImageUploader {
        let uploader = NewDiscussionImageUploader()
        uploader.presentingViewController = self
        uploader.sourceView = toolbar
        uploader.onEnqueue = { [weak self] job in
            self?.applyBodyEditWhenNotComposing { text, selection in
                MarkdownSnippetInserter.apply(.uploadingImage(id: job.id), to: text, selection: selection)
            }
        }
        uploader.onSuccess = { [weak self] job, markdown in
            self?.applyBodyEditWhenNotComposing { text, selection in
                guard let updated = MarkdownImagePlaceholder.replacing(id: job.id, with: markdown, in: text) else { return nil }
                return Self.edit(from: text, to: updated, keeping: selection)
            }
        }
        uploader.onFailure = { [weak self] job, _ in
            self?.applyBodyEditWhenNotComposing { text, selection in
                let updated = MarkdownImagePlaceholder.removing(id: job.id, in: text)
                return updated == text ? nil : Self.edit(from: text, to: updated, keeping: selection)
            }
        }
        uploader.onRequestImageLink = { [weak self] in self?.showImageLinkInput() }
        uploader.onCountChange = { [weak self] count in
            guard let self else { return }
            presenter.didChangeUploadingImageCount(count)
            if count == 0 { showFailedUploadsIfNeeded() }
        }
        return uploader
    }

    /// 不走图床，直接插入已有的图片地址。
    private func showImageLinkInput() {
        let alert = UIAlertController(title: "粘贴图片链接", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "https://"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        let insert = UIAlertAction(title: "插入", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let url = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { return }
            applySnippet(.image(url: url))
        }
        insert.isEnabled = false
        alert.textFields?.first?.addAction(UIAction { [weak insert, weak alert] _ in
            insert?.isEnabled = !(alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }, for: .editingChanged)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(insert)
        alert.preferredAction = insert
        alert.view.tintColor = .label
        present(alert, animated: true)
    }

    private func showFailedUploadsIfNeeded() {
        let failedCount = imageUploader.failedJobs.count
        guard failedCount > 0, presentedViewController == nil else { return }
        let alert = UIAlertController(title: "\(failedCount) 张图片上传失败", message: "可以重试，或者先发不带这些图片的内容。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "放弃这些图片", style: .destructive) { [weak self] _ in
            self?.imageUploader.discardFailed()
        })
        alert.addAction(UIAlertAction(title: "重试", style: .default) { [weak self] _ in
            self?.imageUploader.retryFailed()
        })
        present(alert, animated: true)
    }

    /// 中文输入还在组字时不改正文，避免打断候选词；稍后再试。
    private func applyBodyEditWhenNotComposing(_ makeEdit: @escaping (String, NSRange) -> MarkdownEdit?) {
        guard bodyTextView.markedTextRange == nil else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.applyBodyEditWhenNotComposing(makeEdit)
            }
            return
        }
        guard let edit = makeEdit(bodyTextView.text, bodyTextView.selectedRange) else { return }
        replaceBodyText(with: edit)
    }

    /// 占位替换发生在光标之前时，光标跟着平移，不打断正在写的位置。
    private static func edit(from old: String, to new: String, keeping selection: NSRange) -> MarkdownEdit {
        let oldText = old as NSString
        let newText = new as NSString
        var prefix = 0
        while prefix < min(oldText.length, newText.length) && oldText.character(at: prefix) == newText.character(at: prefix) {
            prefix += 1
        }
        let delta = newText.length - oldText.length
        var location = selection.location
        if location > prefix {
            location = max(prefix, location + delta)
        }
        location = min(location, newText.length)
        return MarkdownEdit(text: new, selection: NSRange(location: location, length: 0))
    }

    /// 正文只在这段范围之外变化时返回平移后的范围；变化碰到了它就返回 nil。
    private static func range(_ range: NSRange, shiftedFrom old: String, to new: String) -> NSRange? {
        guard old != new else { return range }
        let oldText = old as NSString
        let newText = new as NSString
        let shorter = min(oldText.length, newText.length)
        var prefix = 0
        while prefix < shorter && oldText.character(at: prefix) == newText.character(at: prefix) {
            prefix += 1
        }
        var suffix = 0
        while suffix < shorter - prefix
            && oldText.character(at: oldText.length - 1 - suffix) == newText.character(at: newText.length - 1 - suffix) {
            suffix += 1
        }
        let changedEnd = oldText.length - suffix
        if changedEnd <= range.location {
            return NSRange(location: range.location + newText.length - oldText.length, length: range.length)
        }
        if prefix >= NSMaxRange(range) {
            return range
        }
        return nil
    }

    // MARK: - 工具条与面板

    private func toolbarTapped(_ item: NewDiscussionToolbarView.Item) {
        switch item {
        case .keyboard:
            // 在标题里时本来就是文字键盘。
            guard !titleTextView.isFirstResponder else { return }
            showKeyboard()
        case .photo:
            imageUploader.start()
        case .sticker:
            if bodyTextView.inputView === stickerPanel {
                showKeyboard()
            } else {
                Task { [weak self] in
                    guard let self else { return }
                    await stickerCookieSession.prepareMediaRequest()
                    switchBodyInput(to: stickerPanel, active: .sticker)
                }
            }
        case .format:
            if bodyTextView.inputView === formatPanel {
                showKeyboard()
            } else {
                formatPanel.setCurrentBlockStyle(
                    MarkdownSnippetInserter.blockStyle(at: bodyTextView.selectedRange.location, in: bodyTextView.text)
                )
                switchBodyInput(to: formatPanel, active: .format)
            }
        case .link:
            showLinkEditor()
        case .preview:
            showPreview()
        case .dismissKeyboard:
            view.endEditing(true)
        }
    }

    /// 表情、格式面板替换的是正文的键盘，所以先把焦点移到正文。
    private func switchBodyInput(to inputView: UIView?, active: NewDiscussionToolbarView.Item?) {
        bodyTextView.inputView = inputView
        toolbar.setActive(active)
        if bodyTextView.isFirstResponder {
            bodyTextView.reloadInputViews()
        } else {
            bodyTextView.becomeFirstResponder()
        }
    }

    private func showKeyboard() {
        switchBodyInput(to: nil, active: .keyboard)
    }

    private func applySnippet(_ snippet: MarkdownSnippet) {
        if !bodyTextView.isFirstResponder {
            bodyTextView.becomeFirstResponder()
        }
        let edit = MarkdownSnippetInserter.apply(snippet, to: bodyTextView.text, selection: bodyTextView.selectedRange)
        replaceBodyText(with: edit)
        if bodyTextView.inputView === formatPanel {
            formatPanel.setCurrentBlockStyle(MarkdownSnippetInserter.blockStyle(at: edit.selection.location, in: edit.text))
        }
    }

    private func insertSticker(_ token: String) {
        let result = StickerTokenInsertion.inserting(
            token: token,
            into: bodyTextView.text,
            selectedRange: bodyTextView.selectedRange
        )
        replaceBodyText(with: MarkdownEdit(text: result.text, selection: result.selectedRange))
    }

    /// 只替换变化的那一段，走系统输入通道，撤销和重做照常可用。
    private func replaceBodyText(with edit: MarkdownEdit) {
        let old = bodyTextView.text as NSString
        let new = edit.text as NSString
        var prefix = 0
        let maxPrefix = min(old.length, new.length)
        while prefix < maxPrefix && old.character(at: prefix) == new.character(at: prefix) {
            prefix += 1
        }
        var suffix = 0
        while suffix < min(old.length, new.length) - prefix
            && old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) {
            suffix += 1
        }
        let replacedRange = NSRange(location: prefix, length: old.length - prefix - suffix)
        let replacement = new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix))

        if let start = bodyTextView.position(from: bodyTextView.beginningOfDocument, offset: replacedRange.location),
           let end = bodyTextView.position(from: start, offset: replacedRange.length),
           let range = bodyTextView.textRange(from: start, to: end) {
            // 走输入通道会触发 textViewDidChange，那里已经处理高亮和保存。
            bodyTextView.replace(range, withText: replacement)
            bodyTextView.selectedRange = edit.selection
            if bodyTextView.isFirstResponder {
                scrollCaretToVisible(in: bodyTextView)
            }
        } else {
            bodyTextView.text = edit.text
            bodyTextView.selectedRange = edit.selection
            bodyDidChange()
        }
    }

    // MARK: - 文本变化

    private func bodyDidChange() {
        MarkdownEditorStyler.apply(to: bodyTextView)
        bodyPlaceholder.isHidden = !bodyTextView.text.isEmpty
        presenter.didChangeContent(bodyTextView.text)
        // 上传完成等程序替换正文时，用户可能正在改标题，不能把页面滚走。
        if bodyTextView.isFirstResponder {
            scrollCaretToVisible(in: bodyTextView)
        }
    }

    private func titleDidChange() {
        titlePlaceholder.isHidden = !titleTextView.text.isEmpty
        presenter.didChangeTitle(titleTextView.text)
    }

    private func scrollCaretToVisible(in textView: UITextView) {
        guard let end = textView.selectedTextRange?.end else { return }
        let caret = textView.convert(textView.caretRect(for: end), to: scrollView)
        scrollView.scrollRectToVisible(caret.insetBy(dx: 0, dy: -24), animated: false)
    }

    @objc private func blankAreaTapped(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: contentStack)
        guard point.y > bodyTextView.frame.minY, !bodyTextView.isFirstResponder else { return }
        bodyTextView.becomeFirstResponder()
    }

    // MARK: - 链接

    /// 名称、地址分开填；光标在已有链接里时改这个链接。
    private func showLinkEditor() {
        let text = bodyTextView.text ?? ""
        let selection = bodyTextView.selectedRange
        let existing = MarkdownLinkEditor.existingLink(around: selection, in: text)
        let selectedText = selection.length > 0 ? (text as NSString).substring(with: selection) : ""
        let replacingRange = existing?.range ?? selection

        linkBar.onConfirm = { [weak self] name, url in
            guard let self else { return }
            // 编辑期间图片可能传完改了正文，要替换的位置跟着平移。
            let range = Self.range(replacingRange, shiftedFrom: text, to: bodyTextView.text)
                ?? bodyTextView.selectedRange
            let edit = MarkdownLinkEditor.apply(name: name, url: url, replacing: range, in: bodyTextView.text)
            hideLinkBar()
            replaceBodyText(with: edit)
        }
        linkBar.onCancel = { [weak self] in self?.hideLinkBar() }
        linkBar.isHidden = false
        view.layoutIfNeeded()
        // 链接条盖在正文底部，留出位置让光标所在行不被挡住。
        scrollView.contentInset.bottom = linkBar.bounds.height + 6
        linkBar.begin(name: existing?.name ?? selectedText, url: existing?.url ?? "", isEditing: existing != nil)
    }

    /// 收起链接条，回到正文接着写。
    private func hideLinkBar() {
        guard !linkBar.isHidden else { return }
        linkBar.isHidden = true
        scrollView.contentInset.bottom = 0
        bodyTextView.becomeFirstResponder()
    }

    // MARK: - 预览

    private func showPreview() {
        view.endEditing(true)
        let state = presenter.state
        let draft = NewDiscussionDraft(
            // 评论没有标题，预览标题栏标出是哪一楼。
            title: state.editingCommentFloor.map { "#\($0) 评论" } ?? titleTextView.text,
            content: bodyTextView.text,
            category: state.category,
            rank: state.rank
        )
        let preview = NewDiscussionPreviewViewController(
            draft: draft,
            publishTitle: state.isEditing ? "保存" : "发布"
        ) { [weak self] in
            guard let self else { return }
            navigationController?.popViewController(animated: true)
            // 校验失败会弹提示，要等返回动画结束再发布，否则提示弹不出来。
            if let coordinator = navigationController?.transitionCoordinator {
                coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                    self?.presenter.didTapPublish()
                }
            } else {
                presenter.didTapPublish()
            }
        }
        navigationController?.pushViewController(preview, animated: true)
    }

    // MARK: - 发布设置

    private func presentSettings() {
        let state = presenter.state
        let settings = NewDiscussionSettingsViewController(
            category: state.category,
            rank: state.rank,
            userLevel: state.userLevel,
            rankOptions: presenter.rankOptions,
            isCategoryLocked: state.isEditing
        )
        settings.onSelectCategory = { [weak self] category in self?.presenter.didSelectCategory(category) }
        settings.onSelectRank = { [weak self] rank in self?.presenter.didSelectRank(rank) }
        settings.onRetryUserLevel = { [weak self] in self?.presenter.retryLoadingUserLevel() }
        settings.configureSheet()
        settingsViewController = settings
        present(settings, animated: true)
    }

    // MARK: - 关闭与发布

    private func closeTapped() {
        // 还在撤销窗口里的丢弃先执行，关闭判断才基于最新状态。
        draftStrip.commitPendingDiscard()
        switch presenter.closeDecision() {
        case .blocked:
            return
        case .close:
            presenter.close(savingDraft: false)
        case .askSaveOrDiscard:
            let sheet = UIAlertController(title: nil, message: "草稿会保存在本机，下次打开发帖页时可以恢复", preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: "保存草稿并关闭", style: .default) { [weak self] _ in
                self?.presenter.close(savingDraft: true)
            })
            sheet.addAction(UIAlertAction(title: "放弃草稿", style: .destructive) { [weak self] _ in
                self?.presenter.close(savingDraft: false)
            })
            sheet.addAction(UIAlertAction(title: "继续编辑", style: .cancel))
            presentActionSheet(sheet)
        case .askSaveEdit:
            let sheet = UIAlertController(title: nil, message: "修改还没有保存", preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: "保存修改", style: .default) { [weak self] _ in
                self?.presenter.didTapPublish()
            })
            sheet.addAction(UIAlertAction(title: "留着下次继续", style: .default) { [weak self] _ in
                self?.presenter.close(savingDraft: true)
            })
            sheet.addAction(UIAlertAction(title: "放弃修改", style: .destructive) { [weak self] _ in
                self?.presenter.close(savingDraft: false)
            })
            sheet.addAction(UIAlertAction(title: "继续编辑", style: .cancel))
            presentActionSheet(sheet)
        case .askReplaceOldDraft:
            let sheet = UIAlertController(title: nil, message: "本机只保存一份草稿，上次的草稿还没有处理", preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: "保存新内容（替换旧草稿）", style: .default) { [weak self] _ in
                self?.presenter.close(savingDraft: true)
            })
            sheet.addAction(UIAlertAction(title: "保留旧草稿", style: .destructive) { [weak self] _ in
                self?.presenter.closeKeepingPendingDraft()
            })
            sheet.addAction(UIAlertAction(title: "继续编辑", style: .cancel))
            presentActionSheet(sheet)
        }
    }

    private func presentActionSheet(_ sheet: UIAlertController) {
        view.endEditing(true)
        sheet.popoverPresentationController?.barButtonItem = navigationItem.leftBarButtonItem
        present(sheet, animated: true)
    }

    private func publishTapped() {
        view.endEditing(true)
        presenter.didTapPublish()
    }

    private func showMessage(title: String?, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .cancel))
        present(alert, animated: true)
    }

    private func settingsTitle(for state: NewDiscussionViewState) -> AttributedString {
        var result = AttributedString()
        var primary = AttributeContainer()
        primary.font = UIFont.preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        var secondary = AttributeContainer()
        secondary.font = UIFont.preferredFont(forTextStyle: .subheadline)
        secondary.foregroundColor = .secondaryLabel

        guard let category = state.category else {
            if state.isEditing {
                result.append(AttributedString(state.rank.title, attributes: primary))
            } else {
                result.append(AttributedString("选择板块", attributes: primary))
            }
            return result
        }
        result.append(AttributedString(category.title, attributes: primary))
        result.append(AttributedString(" · \(state.rank.title)", attributes: secondary))
        return result
    }
}

// MARK: - NewDiscussionViewProtocol

extension NewDiscussionViewController: NewDiscussionViewProtocol {
    func render(_ state: NewDiscussionViewState) {
        lastState = state

        var settingsConfiguration = settingsButton.configuration
        settingsConfiguration?.attributedTitle = settingsTitle(for: state)
        // 编辑时板块固定；站点新增、App 不认识的板块也不再提示去选。
        let needsCategory = state.category == nil && !state.isEditing
        let settingsSymbol: String
        if needsCategory {
            settingsSymbol = "plus"
        } else if state.isEditing || state.category == .inside {
            // 编辑时板块已锁定，用锁提示这里只能改阅读限制。
            settingsSymbol = "lock.fill"
        } else {
            settingsSymbol = "chevron.down"
        }
        settingsConfiguration?.image = UIImage(
            systemName: settingsSymbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        )
        // 没选板块时用描边提示还差这一步，选了之后是普通灰底胶囊。
        settingsConfiguration?.background.backgroundColor = needsCategory ? .clear : .secondarySystemFill
        settingsConfiguration?.background.strokeColor = needsCategory ? .label : nil
        settingsConfiguration?.background.strokeWidth = needsCategory ? 1.5 : 0
        settingsConfiguration?.baseForegroundColor = state.category == .inside ? .systemOrange : .label
        if let floor = state.editingCommentFloor {
            // 评论没有板块和阅读限制，中间只标出在编辑哪一楼。
            var title = AttributedString("编辑评论")
            title.font = UIFont.preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
            var floorText = AttributedString("  #\(floor)")
            floorText.font = UIFont.preferredFont(forTextStyle: .subheadline)
            floorText.foregroundColor = .secondaryLabel
            settingsConfiguration?.attributedTitle = title + floorText
            settingsConfiguration?.image = nil
            settingsConfiguration?.background.backgroundColor = .clear
        }
        settingsButton.configuration = settingsConfiguration
        settingsButton.isEnabled = !state.isSubmitting
        settingsButton.isUserInteractionEnabled = state.editingCommentFloor == nil
        titleTextView.isHidden = state.editingCommentFloor != nil

        var publishConfiguration = publishButton.configuration
        publishConfiguration?.showsActivityIndicator = state.isSubmitting
        publishConfiguration?.title = state.isSubmitting ? nil : (state.isEditing ? "保存" : "发布")
        // 编辑时没改动就没什么可保存，按钮置灰。
        let isUnchanged = state.saveStatus == .unchanged
        publishConfiguration?.baseBackgroundColor = isUnchanged ? .tertiarySystemFill : .label
        publishConfiguration?.baseForegroundColor = isUnchanged ? .tertiaryLabel : .systemBackground
        publishButton.configuration = publishConfiguration
        // 发布按钮始终可点，缺什么由点击时的校验提示，避免用户不知道为什么点不了。
        publishButton.isUserInteractionEnabled = !state.isSubmitting && !isUnchanged
        navigationItem.leftBarButtonItem?.isEnabled = !state.isSubmitting

        if let fee = state.category?.chickenLegFee {
            feeNoticeLabel.text = "发到\(state.category?.title ?? "")将收取 \(fee) 鸡腿"
            feeNoticeLabel.isHidden = false
        } else {
            feeNoticeLabel.isHidden = true
        }

        if let pending = state.pendingDraft {
            if pending != configuredPendingDraft {
                configuredPendingDraft = pending
                let title = pending.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = [title.isEmpty ? "无标题" : title, Self.relativeFormatter.localizedString(for: pending.updatedAt, relativeTo: Date())]
                let preview = pending.content
                    .components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .prefix(3)
                    .joined(separator: "\n")
                draftStrip.configure(
                    title: state.isEditing ? "上次没保存的修改" : "上次的草稿",
                    summary: parts.joined(separator: " · "),
                    preview: preview
                )
            }
            draftBannerContainer.isHidden = false
        } else {
            configuredPendingDraft = nil
            draftBannerContainer.isHidden = true
        }

        switch state.saveStatus {
        case .empty: statusLabel.text = nil
        case .unchanged: statusLabel.text = "未修改"
        case .saved: statusLabel.text = state.isEditing ? "已修改 · 已存本机" : "已存本机"
        case .waitingForDraftDecision: statusLabel.text = "未保存"
        }
        if imageUploader.activeCount > 0 {
            statusLabel.text = "上传中 \(imageUploader.activeCount) 张"
        }

        titleTextView.isEditable = !state.isSubmitting
        bodyTextView.isEditable = !state.isSubmitting
        toolbar.setEnabled(!state.isSubmitting)
        scrollView.alpha = state.isSubmitting ? 0.45 : 1

        settingsViewController?.update(userLevel: state.userLevel, rankOptions: presenter.rankOptions)
    }

    func fill(_ draft: NewDiscussionDraft) {
        titleTextView.text = draft.title
        titlePlaceholder.isHidden = !draft.title.isEmpty
        bodyTextView.text = draft.content
        bodyPlaceholder.isHidden = !draft.content.isEmpty
        MarkdownEditorStyler.apply(to: bodyTextView)
    }

    func showValidationMessage(_ message: String) {
        showMessage(title: nil, message: message)
    }

    func confirmChickenLegFee(_ fee: Int, onConfirm: @escaping () -> Void) {
        let alert = UIAlertController(title: "确认", message: "发内版需要收取\(fee)鸡腿手续费，是否继续？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "继续", style: .default) { _ in onConfirm() })
        present(alert, animated: true)
    }

    func confirmPrivateRankFee(_ fee: Int, onConfirm: @escaping () -> Void) {
        let alert = UIAlertController(title: "确认", message: "公开帖子设为私有需要收取\(fee)鸡腿手续费，是否继续？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "继续", style: .default) { _ in onConfirm() })
        present(alert, animated: true)
    }

    func showSubmitFailure(title: String, message: String, allowsRetry: Bool) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        if allowsRetry {
            alert.addAction(UIAlertAction(title: "重试", style: .default) { [weak self] _ in
                self?.presenter.didTapPublish()
            })
            // 网页兜底只对发新帖有意义，编辑时直接重试。
            if lastState?.isEditing != true {
                alert.addAction(UIAlertAction(title: "用网页发帖", style: .default) { [weak self] _ in
                    guard let self else { return }
                    // 网页编辑器不会读 App 草稿，先把正文放进剪贴板方便粘贴。
                    UIPasteboard.general.string = bodyTextView.text
                    presenter.didTapOpenWebFallback()
                })
            }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        } else {
            alert.addAction(UIAlertAction(title: "好", style: .cancel))
        }
        present(alert, animated: true)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter
    }()
}

// MARK: - UITextViewDelegate

extension NewDiscussionViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // 标题不换行：回车跳到正文。
        if textView === titleTextView, text == "\n" {
            bodyTextView.becomeFirstResponder()
            return false
        }
        // 正文列表、引用里回车自动续行；组字中不处理，交给输入法。
        if textView === bodyTextView, text == "\n", textView.markedTextRange == nil,
           let edit = MarkdownListContinuation.edit(forNewlineAt: range, in: textView.text) {
            replaceBodyText(with: edit)
            return false
        }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        if textView === titleTextView {
            titleDidChange()
        } else {
            bodyDidChange()
        }
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard textView === bodyTextView else { return }
        if bodyTextView.inputView === formatPanel {
            formatPanel.setCurrentBlockStyle(
                MarkdownSnippetInserter.blockStyle(at: bodyTextView.selectedRange.location, in: bodyTextView.text)
            )
        }
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        // 点回正文或标题就算放弃这次链接编辑。
        if !linkBar.isHidden {
            linkBar.isHidden = true
            scrollView.contentInset.bottom = 0
        }
        // 标题没有表情和格式面板，回到标题时工具条恢复普通态。
        if textView === titleTextView {
            toolbar.setActive(.keyboard)
            if bodyTextView.inputView != nil {
                bodyTextView.inputView = nil
            }
        }
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        return UIFont(descriptor: descriptor, size: 0)
    }
}
