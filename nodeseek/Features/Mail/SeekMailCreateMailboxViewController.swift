//
//  SeekMailCreateMailboxViewController.swift
//  nodeseek
//

import UIKit

/// 新建邮箱：输入前缀、选域名，点「检查」确认地址可用后才能创建。
/// 只在用户点检查时请求，不随输入自动检查：seek.li 额度很紧，逐字检查容易被限流。
/// 注册新网站时给它单独建一个地址，创建成功由列表页复制地址并切过去。
final class SeekMailCreateMailboxViewController: UIViewController, UITextFieldDelegate {
    /// OpenAPI 没有域名列表接口，这两个域名实测可创建；nodeseek.org 不能发信。
    static let domains = ["seek.li", "nodeseek.org"]

    private let provider: SeekMailProvider<SeekMailAPI>
    private let onCreated: (SeekMailbox) -> Void

    private let prefixField = UITextField()
    private let checkButton = UIButton(type: .system)
    private let domainControl = UISegmentedControl(items: SeekMailCreateMailboxViewController.domains.map { "@\($0)" })
    private let statusLabel = UILabel()
    private let noteLabel = UILabel()
    private lazy var createItem = UIBarButtonItem(title: SeekMailL10n.text("创建"), primaryAction: UIAction { [weak self] _ in
        self?.create()
    })
    private var checkTask: Task<Void, Never>?
    private var createTask: Task<Void, Never>?
    /// 最近一次检查通过的地址；输入变了就作废。
    private var availableAddress: String?
    /// 显示的是检查结果（而不是格式提示）时，改输入才提示重新检查。
    private var showsCheckResult = false

    init(provider: SeekMailProvider<SeekMailAPI>, onCreated: @escaping (SeekMailbox) -> Void) {
        self.provider = provider
        self.onCreated = onCreated
        super.init(nibName: nil, bundle: nil)
        title = SeekMailL10n.text("新建邮箱")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        checkTask?.cancel()
        createTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        createItem.style = .done
        createItem.tintColor = .label
        createItem.isEnabled = false
        createItem.accessibilityIdentifier = "seek-mail-create-submit"
        navigationItem.rightBarButtonItem = createItem
        setupLayout()
        updateNote()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        prefixField.becomeFirstResponder()
    }

    var address: String? {
        let prefix = (prefixField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard prefix.isEmpty == false, prefix.contains("@") == false else { return nil }
        return "\(prefix)@\(Self.domains[max(domainControl.selectedSegmentIndex, 0)])"
    }

    /// 粘贴完整地址时拆成前缀和域名；域名不在可选范围内返回 nil 域名。
    static func split(_ text: String) -> (prefix: String, domainIndex: Int?)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = trimmed.firstIndex(of: "@") else { return nil }
        let domain = trimmed[trimmed.index(after: at)...].lowercased()
        return (String(trimmed[..<at]), domains.firstIndex(of: domain))
    }

    // MARK: - 布局

    private func setupLayout() {
        prefixField.placeholder = SeekMailL10n.text("地址前缀，例如 shop-2026")
        prefixField.font = SeekMailFont.of(.body)
        prefixField.autocapitalizationType = .none
        prefixField.autocorrectionType = .no
        prefixField.spellCheckingType = .no
        prefixField.keyboardType = .asciiCapable
        prefixField.clearButtonMode = .whileEditing
        prefixField.returnKeyType = .done
        prefixField.delegate = self
        prefixField.accessibilityIdentifier = "seek-mail-create-prefix"
        prefixField.addAction(UIAction { [weak self] _ in self?.inputChanged() }, for: .editingChanged)

        var checkConfiguration = UIButton.Configuration.plain()
        checkConfiguration.baseForegroundColor = .label
        var checkTitle = AttributedString(SeekMailL10n.text("检查"))
        checkTitle.font = SeekMailFont.of(.body, weight: .semibold)
        checkConfiguration.attributedTitle = checkTitle
        checkButton.configuration = checkConfiguration
        checkButton.isEnabled = false
        checkButton.accessibilityIdentifier = "seek-mail-create-check"
        checkButton.setContentHuggingPriority(.required, for: .horizontal)
        checkButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        checkButton.addAction(UIAction { [weak self] _ in self?.check() }, for: .touchUpInside)

        domainControl.selectedSegmentIndex = 0
        domainControl.selectedSegmentTintColor = .label
        domainControl.setTitleTextAttributes([.foregroundColor: UIColor.systemBackground], for: .selected)
        domainControl.accessibilityIdentifier = "seek-mail-create-domain"
        domainControl.addAction(UIAction { [weak self] _ in
            self?.updateNote()
            self?.inputChanged()
        }, for: .valueChanged)

        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 12
        card.layer.cornerCurve = .continuous
        prefixField.translatesAutoresizingMaskIntoConstraints = false
        checkButton.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(prefixField)
        card.addSubview(checkButton)

        statusLabel.font = SeekMailFont.of(.footnote)
        statusLabel.numberOfLines = 0
        statusLabel.accessibilityIdentifier = "seek-mail-create-status"
        noteLabel.font = SeekMailFont.of(.footnote)
        noteLabel.textColor = .secondaryLabel
        noteLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [card, domainControl, statusLabel, noteLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(16, after: card)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            prefixField.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            checkButton.leadingAnchor.constraint(equalTo: prefixField.trailingAnchor, constant: 4),
            checkButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -4),
            checkButton.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            prefixField.topAnchor.constraint(equalTo: card.topAnchor),
            prefixField.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            prefixField.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            domainControl.heightAnchor.constraint(greaterThanOrEqualToConstant: 32)
        ])
    }

    private func updateNote() {
        let domain = Self.domains[max(domainControl.selectedSegmentIndex, 0)]
        noteLabel.text = domain == "nodeseek.org"
            ? SeekMailL10n.text("nodeseek.org 地址只能收信，不能发信。创建后可在网页中设置别名。")
            : SeekMailL10n.text("创建后会自动复制地址并切换到这个邮箱，可在网页中设置别名。")
    }

    // MARK: - 检查与创建

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        check()
        return false
    }

    /// 输入变了只作废上次的检查结果，不发请求。
    private func inputChanged() {
        checkTask?.cancel()
        checkTask = nil
        let hadResult = showsCheckResult
        showsCheckResult = false
        availableAddress = nil
        if let parts = Self.split(prefixField.text ?? "") {
            guard let index = parts.domainIndex else {
                showStatus(SeekMailL10n.text("只能使用 seek.li 或 nodeseek.org"), color: .systemRed)
                updateButtons()
                return
            }
            prefixField.text = parts.prefix
            if domainControl.selectedSegmentIndex != index {
                domainControl.selectedSegmentIndex = index
                updateNote()
            }
        }
        showStatus(hadResult && address != nil ? SeekMailL10n.text("地址已修改，请重新检查") : nil)
        updateButtons()
    }

    private func check() {
        guard let address, checkTask == nil, createTask == nil else { return }
        showStatus(SeekMailL10n.text("正在检查…"), color: .secondaryLabel)
        checkTask = Task { [weak self] in
            guard let self else { return }
            updateButtons()
            do {
                let result = try await provider.checkMailbox(address: address)
                guard Task.isCancelled == false, address == self.address else { return }
                showsCheckResult = true
                if result.available {
                    availableAddress = address
                    showStatus(SeekMailL10n.format("%@ 可以使用", address), color: .label)
                } else {
                    showStatus(result.message ?? SeekMailL10n.text("这个地址不可用"), color: .systemRed)
                }
            } catch {
                guard Task.isCancelled == false, address == self.address else { return }
                // 被限流也只提示，不自动重试，免得偷偷耗掉额度
                showStatus(SeekMailBindViewController.message(for: error), color: .systemRed)
            }
            checkTask = nil
            updateButtons()
        }
    }

    private func create() {
        guard let address = availableAddress, createTask == nil else { return }
        prefixField.resignFirstResponder()
        createTask = Task { [weak self] in
            guard let self else { return }
            setBusy(true)
            do {
                let mailbox = try await provider.createMailbox(address: address)
                onCreated(mailbox)
                dismiss(animated: true)
            } catch {
                createTask = nil
                setBusy(false)
                showStatus(SeekMailBindViewController.message(for: error), color: .systemRed)
            }
        }
    }

    private func setBusy(_ busy: Bool) {
        prefixField.isEnabled = busy == false
        domainControl.isEnabled = busy == false
        checkButton.isEnabled = busy == false && address != nil
        isModalInPresentation = busy
        if busy {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
        } else {
            navigationItem.rightBarButtonItem = createItem
            updateButtons()
        }
    }

    private func updateButtons() {
        createItem.isEnabled = availableAddress != nil && availableAddress == address
        checkButton.isEnabled = address != nil && checkTask == nil && createTask == nil
    }

    private func showStatus(_ text: String?, color: UIColor = .secondaryLabel) {
        statusLabel.text = text
        statusLabel.textColor = color
        statusLabel.isHidden = text == nil
    }
}
