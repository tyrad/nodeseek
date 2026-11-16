//
//  SeekMailBindViewController.swift
//  nodeseek
//

import UIKit

enum SeekMailLinks {
    static let developerConsole = URL(string: "https://seek.li/manage/developer")!
    static let manage = URL(string: "https://seek.li/manage")!
}

/// 绑定 seek.li API Key：粘贴后先请求一次邮箱列表验证，成功才写入钥匙串。
final class SeekMailBindViewController: UIViewController, UITextFieldDelegate {
    typealias Verifier = @MainActor (String) async throws -> [SeekMailbox]

    private let keyStore: SeekMailAPIKeyStoring
    private let verify: Verifier
    private let onBound: @MainActor ([SeekMailbox]) -> Void
    private var verifyTask: Task<Void, Never>?
    /// 进入页面时就显示的提示，例如旧 Key 已失效。
    var initialErrorMessage: String?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let keyField = UITextField()
    private let errorLabel = UILabel()
    private let bottomStack = UIStackView()

    private lazy var saveButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = SeekMailL10n.text("验证并保存")
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .label
        configuration.baseForegroundColor = .systemBackground
        configuration.buttonSize = .large
        let button = UIButton(configuration: configuration)
        button.accessibilityIdentifier = "seek-mail-bind-save"
        button.configurationUpdateHandler = { [weak self] button in
            let verifying = self?.verifyTask != nil
            button.configuration?.showsActivityIndicator = verifying
            button.configuration?.title = verifying ? SeekMailL10n.text("正在验证") : SeekMailL10n.text("验证并保存")
        }
        button.addAction(UIAction { [weak self] _ in self?.saveTapped() }, for: .touchUpInside)
        return button
    }()

    init(
        keyStore: SeekMailAPIKeyStoring = SeekMailAPIKeyStore.shared,
        verify: Verifier? = nil,
        onBound: @escaping @MainActor ([SeekMailbox]) -> Void = { _ in }
    ) {
        self.keyStore = keyStore
        self.verify = verify ?? { key in
            try await SeekMailProvider<SeekMailAPI>(apiKey: { key }).mailboxes()
        }
        self.onBound = onBound
        super.init(nibName: nil, bundle: nil)
        title = SeekMailL10n.text("邮箱")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { verifyTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        setupContent()
        setupBottomBar()
        showError(initialErrorMessage)
        updateSaveButton()
    }

    // MARK: - 布局

    private func setupContent() {
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        let iconView = UIImageView(image: UIImage(systemName: "envelope"))
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        iconView.tintColor = .systemBackground
        iconView.contentMode = .center
        let iconTile = UIView()
        iconTile.backgroundColor = .label
        iconTile.layer.cornerRadius = 16
        iconTile.layer.cornerCurve = .continuous
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(iconView)
        let iconRow = UIView()
        iconRow.addSubview(iconTile)
        NSLayoutConstraint.activate([
            iconTile.leadingAnchor.constraint(equalTo: iconRow.leadingAnchor, constant: 4),
            iconTile.topAnchor.constraint(equalTo: iconRow.topAnchor),
            iconTile.bottomAnchor.constraint(equalTo: iconRow.bottomAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 60),
            iconTile.heightAnchor.constraint(equalToConstant: 60),
            iconView.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor)
        ])

        let titleLabel = UILabel()
        titleLabel.text = SeekMailL10n.text("连接 seek.li 邮箱")
        titleLabel.font = .systemFont(ofSize: 26, weight: .heavy)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0

        let descLabel = UILabel()
        descLabel.text = SeekMailL10n.text("用 seek.li 控制台里创建的 API Key 在 App 里收发邮件、看验证码。Key 只保存在本机钥匙串。")
        descLabel.font = .preferredFont(forTextStyle: .subheadline)
        descLabel.adjustsFontForContentSizeCategory = true
        descLabel.textColor = .secondaryLabel
        descLabel.numberOfLines = 0

        let fieldHeader = Self.makeSectionHeader("API KEY")

        keyField.placeholder = "sk_live_…"
        keyField.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        keyField.autocapitalizationType = .none
        keyField.autocorrectionType = .no
        keyField.spellCheckingType = .no
        keyField.smartQuotesType = .no
        keyField.returnKeyType = .done
        keyField.clearButtonMode = .whileEditing
        keyField.delegate = self
        keyField.accessibilityIdentifier = "seek-mail-bind-key-field"
        keyField.addAction(UIAction { [weak self] _ in self?.keyDidChange() }, for: .editingChanged)

        var pasteConfiguration = UIButton.Configuration.gray()
        pasteConfiguration.title = SeekMailL10n.text("粘贴")
        pasteConfiguration.cornerStyle = .capsule
        pasteConfiguration.baseForegroundColor = .label
        pasteConfiguration.buttonSize = .small
        let pasteButton = UIButton(configuration: pasteConfiguration)
        pasteButton.accessibilityIdentifier = "seek-mail-bind-paste"
        pasteButton.addAction(UIAction { [weak self] _ in self?.pasteTapped() }, for: .touchUpInside)
        pasteButton.setContentHuggingPriority(.required, for: .horizontal)
        // Key 有七十多个字符，输入框要让位，不能把「粘贴」挤出卡片
        pasteButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        keyField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let fieldRow = UIStackView(arrangedSubviews: [keyField, pasteButton])
        fieldRow.spacing = 10
        fieldRow.alignment = .center
        let fieldCard = Self.makeCard(containing: fieldRow, insets: UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 10))
        fieldRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true

        errorLabel.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        errorLabel.accessibilityIdentifier = "seek-mail-bind-error"

        let helpButton = Self.makeDisclosureButton(title: SeekMailL10n.text("如何获取 Key、需要哪些权限"), symbolName: "key")
        helpButton.accessibilityIdentifier = "seek-mail-bind-help"
        helpButton.addAction(UIAction { [weak self] _ in self?.showHelp() }, for: .touchUpInside)
        let helpCard = Self.makeCard(containing: helpButton, insets: .zero)

        [iconRow, titleLabel, descLabel, fieldHeader, fieldCard, errorLabel, helpCard].forEach(contentStack.addArrangedSubview)
        contentStack.setCustomSpacing(16, after: iconRow)
        contentStack.setCustomSpacing(6, after: titleLabel)
        contentStack.setCustomSpacing(24, after: descLabel)
        contentStack.setCustomSpacing(6, after: fieldHeader)
        contentStack.setCustomSpacing(12, after: fieldCard)
        contentStack.setCustomSpacing(12, after: errorLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24)
        ])
    }

    private func setupBottomBar() {
        var linkConfiguration = UIButton.Configuration.plain()
        linkConfiguration.title = SeekMailL10n.text("去 seek.li 创建 Key")
        linkConfiguration.image = UIImage(systemName: "arrow.up.right")
        linkConfiguration.imagePlacement = .trailing
        linkConfiguration.imagePadding = 4
        linkConfiguration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        linkConfiguration.baseForegroundColor = .label
        let linkButton = UIButton(configuration: linkConfiguration)
        linkButton.accessibilityIdentifier = "seek-mail-bind-open-console"
        linkButton.addAction(UIAction { [weak self] _ in self?.openConsole() }, for: .touchUpInside)

        bottomStack.axis = .vertical
        bottomStack.spacing = 6
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        bottomStack.addArrangedSubview(saveButton)
        bottomStack.addArrangedSubview(linkButton)
        view.addSubview(bottomStack)

        NSLayoutConstraint.activate([
            bottomStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            bottomStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            // 键盘弹出时按钮跟着上移，不会被挡住
            bottomStack.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
            bottomStack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: bottomStack.topAnchor, constant: -8)
        ])
        let preferredBottom = bottomStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        preferredBottom.priority = .defaultHigh
        preferredBottom.isActive = true
    }

    // MARK: - 交互

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        saveTapped()
        return true
    }

    private var normalizedKey: String {
        SeekMailAPIKeyStore.normalized(keyField.text ?? "")
    }

    private func keyDidChange() {
        showError(nil)
        updateSaveButton()
    }

    private func pasteTapped() {
        guard let text = UIPasteboard.general.string else { return }
        applyPasted(text)
    }

    /// 粘贴的内容像 Key 就直接验证保存，省掉再点一次按钮；不像的只填进去，让用户自己检查。
    func applyPasted(_ text: String) {
        keyField.text = SeekMailAPIKeyStore.normalized(text)
        keyDidChange()
        if normalizedKey.hasPrefix("sk_") { saveTapped() }
    }

    private func updateSaveButton() {
        saveButton.isEnabled = normalizedKey.isEmpty == false && verifyTask == nil
        saveButton.setNeedsUpdateConfiguration()
    }

    private func showError(_ message: String?) {
        errorLabel.text = message
        errorLabel.isHidden = message == nil
    }

    private func saveTapped() {
        let key = normalizedKey
        guard key.isEmpty == false, verifyTask == nil else { return }
        keyField.resignFirstResponder()
        showError(nil)
        verifyTask = Task { [weak self] in
            guard let self else { return }
            do {
                let mailboxes = try await verify(key)
                verifyTask = nil
                guard keyStore.save(apiKey: key) else {
                    showError(SeekMailL10n.text("Key 有效，但没能保存到本机钥匙串，请重试"))
                    updateSaveButton()
                    return
                }
                onBound(mailboxes)
            } catch is CancellationError {
                verifyTask = nil
            } catch {
                verifyTask = nil
                showError(Self.message(for: error))
            }
            updateSaveButton()
        }
        updateSaveButton()
    }

    static func message(for error: Error) -> String {
        switch error as? SeekMailError {
        case .unauthorized?: return SeekMailL10n.text("Key 无效或已失效，请检查后重新粘贴")
        case let mailError?: return mailError.userMessage
        case nil: return SeekMailL10n.text("验证失败，请稍后重试")
        }
    }

    private func showHelp() {
        navigationController?.pushViewController(SeekMailKeyHelpViewController(), animated: true)
    }

    private func openConsole() {
        // 用系统浏览器：控制台需要登录，Safari 里通常已有登录态，也方便复制 Key 后切回来
        UIApplication.shared.open(SeekMailLinks.developerConsole)
    }

    // MARK: - 小组件

    private static func makeSectionHeader(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        return label
    }

    private static func makeCard(containing content: UIView, insets: UIEdgeInsets) -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -insets.right),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: insets.top),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -insets.bottom)
        ])
        return card
    }

    private static func makeDisclosureButton(title: String, symbolName: String) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: symbolName)
        configuration.imagePadding = 10
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 36)
        let button = UIButton(configuration: configuration)
        button.contentHorizontalAlignment = .leading
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.isUserInteractionEnabled = false
        button.addSubview(chevron)
        NSLayoutConstraint.activate([
            chevron.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -14),
            chevron.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        return button
    }
}

/// 获取 Key 的步骤和需要勾选的权限，从绑定页推入。
final class SeekMailKeyHelpViewController: UITableViewController {
    private struct Scope {
        let title: String
        let scope: String
        let required: Bool
    }

    private let steps = [
        SeekMailL10n.text("登录 seek.li 控制台"),
        SeekMailL10n.text("进入「开发者」，新建 API Key"),
        SeekMailL10n.text("按下方勾选权限后创建，复制 sk_live_ 开头的 Key"),
        SeekMailL10n.text("回到 App 粘贴并保存")
    ]

    private let scopes = [
        Scope(title: SeekMailL10n.text("读取邮箱"), scope: "mailbox:read", required: true),
        Scope(title: SeekMailL10n.text("读取邮件"), scope: "mail:read", required: true),
        Scope(title: SeekMailL10n.text("已读、星标、移动、删除"), scope: "mail:manage", required: true),
        Scope(title: SeekMailL10n.text("下载附件"), scope: "attachment:read", required: true),
        Scope(title: SeekMailL10n.text("读取文件夹"), scope: "folder:read", required: true),
        Scope(title: SeekMailL10n.text("查看存储用量"), scope: "storage:read", required: true),
        Scope(title: SeekMailL10n.text("写信和回复（可选，只有 seek.li 地址能发信）"), scope: "mail:send", required: false),
        Scope(title: SeekMailL10n.text("新建邮箱（可选）"), scope: "mailbox:write", required: false)
    ]

    init() {
        super.init(style: .insetGrouped)
        title = SeekMailL10n.text("获取 API Key")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return steps.count
        case 1: return scopes.count
        default: return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return SeekMailL10n.text("步骤")
        case 1: return SeekMailL10n.text("需要勾选的权限")
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 1 ? SeekMailL10n.text("不需要勾选全部权限。少勾的权限对应功能会提示无法使用，例如不勾 mail:send 只是不能写信；可随时在 seek.li 重新创建 Key。") : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        var content = UIListContentConfiguration.valueCell()
        switch indexPath.section {
        case 0:
            content = .cell()
            content.text = steps[indexPath.row]
            content.image = UIImage(systemName: "\(indexPath.row + 1).circle")
            content.imageProperties.tintColor = .label
            cell.selectionStyle = .none
        case 1:
            let scope = scopes[indexPath.row]
            content.text = scope.title
            content.secondaryText = scope.scope
            content.secondaryTextProperties.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            content.image = UIImage(systemName: scope.required ? "checkmark.circle.fill" : "circle")
            content.imageProperties.tintColor = scope.required ? .label : .tertiaryLabel
            content.textProperties.color = scope.required ? .label : .secondaryLabel
            cell.selectionStyle = .none
        default:
            content = .cell()
            content.text = SeekMailL10n.text("打开 seek.li 开发者页面")
            content.textProperties.color = .label
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.image = UIImage(systemName: "safari")
            content.imageProperties.tintColor = .label
            cell.accessoryType = .disclosureIndicator
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 2 else { return }
        UIApplication.shared.open(SeekMailLinks.developerConsole)
    }
}
