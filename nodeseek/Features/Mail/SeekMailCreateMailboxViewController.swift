//
//  SeekMailCreateMailboxViewController.swift
//  nodeseek
//

import UIKit

/// 新建邮箱：输入前缀、选域名，停顿后检查地址是否可用，可用才能创建。
/// 注册新网站时给它单独建一个地址，创建成功由列表页复制地址并切过去。
final class SeekMailCreateMailboxViewController: UIViewController {
    /// OpenAPI 没有域名列表接口，这两个域名实测可创建；nodeseek.org 不能发信。
    static let domains = ["seek.li", "nodeseek.org"]
    /// 停顿多久再检查，避免每输入一个字就发一次请求。
    var checkDelay: TimeInterval = 0.6

    private let provider: SeekMailProvider<SeekMailAPI>
    private let onCreated: (SeekMailbox) -> Void

    private let prefixField = UITextField()
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
        guard prefix.isEmpty == false else { return nil }
        return "\(prefix)@\(Self.domains[max(domainControl.selectedSegmentIndex, 0)])"
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
        prefixField.accessibilityIdentifier = "seek-mail-create-prefix"
        prefixField.addAction(UIAction { [weak self] _ in self?.inputChanged() }, for: .editingChanged)

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
        card.addSubview(prefixField)

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
            prefixField.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
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

    private func inputChanged() {
        checkTask?.cancel()
        availableAddress = nil
        updateCreateButton()
        guard let address else {
            showStatus(nil)
            return
        }
        showStatus(SeekMailL10n.text("正在检查…"), color: .secondaryLabel)
        let delay = checkDelay
        checkTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard Task.isCancelled == false, let self else { return }
            await check(address)
        }
    }

    private func check(_ address: String) async {
        do {
            let result = try await provider.checkMailbox(address: address)
            guard Task.isCancelled == false, address == self.address else { return }
            if result.available {
                availableAddress = address
                showStatus(SeekMailL10n.format("%@ 可以使用", address), color: .label)
            } else {
                showStatus(result.message ?? SeekMailL10n.text("这个地址不可用"), color: .systemRed)
            }
        } catch is CancellationError {
        } catch {
            guard address == self.address else { return }
            showStatus(SeekMailBindViewController.message(for: error), color: .systemRed)
        }
        updateCreateButton()
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
        isModalInPresentation = busy
        if busy {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
        } else {
            navigationItem.rightBarButtonItem = createItem
            updateCreateButton()
        }
    }

    private func updateCreateButton() {
        createItem.isEnabled = availableAddress != nil && availableAddress == address
    }

    private func showStatus(_ text: String?, color: UIColor = .secondaryLabel) {
        statusLabel.text = text
        statusLabel.textColor = color
        statusLabel.isHidden = text == nil
    }
}
