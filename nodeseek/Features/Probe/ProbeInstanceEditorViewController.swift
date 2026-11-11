import UIKit

/// 添加 / 编辑探针：填写地址后自动测试连接，确认能读到服务器后才能保存。
final class ProbeInstanceEditorViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case panel, connection, servers, delete
    }

    private enum PanelRow: Int, CaseIterable {
        case type, url, name
    }

    private enum ConnectionState: Equatable {
        case idle
        case testing
        case success(version: String?, count: Int)
        case failure(ProbeFetchError)
        case invalidURL
    }

    private let store: ProbeInstanceStore
    private let service: ProbeFetching
    private let registry: ProbeAdapterRegistry
    private let existing: ProbeInstance?
    private var adapterID: String
    private var urlText: String
    private var nameText: String
    private var nodes: [ProbeNode] = []
    private var hiddenNodeIDs: Set<String>
    private var connection = ConnectionState.idle
    /// 测试成功时的地址；地址改动后需要重新测试。
    private var verifiedURL: URL?
    private var testTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    init(instance: ProbeInstance?, store: ProbeInstanceStore = .shared,
         service: ProbeFetching = ProbeService.shared, registry: ProbeAdapterRegistry = .shared) {
        self.existing = instance
        self.store = store
        self.service = service
        self.registry = registry
        adapterID = instance?.adapterID ?? registry.engines.first?.spec.id ?? "komari"
        urlText = instance?.baseURL.absoluteString ?? ""
        nameText = instance?.name ?? ""
        hiddenNodeIDs = instance?.hiddenNodeIDs ?? []
        super.init(style: .insetGrouped)
        title = instance == nil ? "添加探针" : "编辑探针"
        if let instance, let snapshot = store.snapshot(for: instance.id) {
            nodes = ProbeServer.ordered(
                snapshot: snapshot, instance: ProbeInstance(id: instance.id, name: instance.name, baseURL: instance.baseURL,
                                                            adapterID: instance.adapterID, nodeOrder: instance.nodeOrder)
            ).map(\.node)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(ProbeTextFieldCell.self, forCellReuseIdentifier: ProbeTextFieldCell.reuseIdentifier)
        tableView.keyboardDismissMode = .onDrag
        // 服务器分组始终可拖动排序。
        tableView.isEditing = true
        tableView.allowsSelectionDuringEditing = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        let save = UIBarButtonItem(title: "保存", primaryAction: UIAction { [weak self] _ in self?.save() })
        save.style = .done
        save.accessibilityIdentifier = "probe-editor-save"
        navigationItem.rightBarButtonItem = save
        isModalInPresentation = true
        if existing != nil {
            testConnection()
        }
        updateSaveButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if existing == nil, let cell = tableView.cellForRow(at: IndexPath(row: PanelRow.url.rawValue, section: Section.panel.rawValue)) as? ProbeTextFieldCell {
            cell.textField.becomeFirstResponder()
        }
    }

    // MARK: - 连接

    private var normalizedURL: URL? {
        ProbeAdapterEngine.normalizedBaseURL(urlText)
    }

    private func scheduleTest() {
        debounceTask?.cancel()
        testTask?.cancel()
        verifiedURL = nil
        connection = .idle
        reloadConnection()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.testConnection()
        }
    }

    private func testConnection() {
        testTask?.cancel()
        guard let url = normalizedURL else {
            connection = urlText.trimmingCharacters(in: .whitespaces).isEmpty ? .idle : .invalidURL
            reloadConnection()
            return
        }
        connection = .testing
        reloadConnection()
        let adapterID = adapterID
        let service = service
        testTask = Task { [weak self] in
            do {
                let info = try await service.testConnection(baseURL: url, adapterID: adapterID)
                guard !Task.isCancelled, let self else { return }
                verifiedURL = url
                connection = .success(version: info.version, count: info.nodes.count)
                if nameText.trimmingCharacters(in: .whitespaces).isEmpty, let host = url.host {
                    nameText = host
                    // 直接改输入框，不重载这一行，避免打断正在编辑的地址输入。
                    let nameIndex = IndexPath(row: PanelRow.name.rawValue, section: Section.panel.rawValue)
                    (tableView.cellForRow(at: nameIndex) as? ProbeTextFieldCell)?.textField.text = host
                }
                // 服务器数量会变，数据和表格刷新必须放在同一次更新里，否则行数校验会失败。
                applyNodes(info.nodes)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                connection = .failure(ProbeFetchError.from(error))
            }
            self?.reloadConnectionAndServers()
        }
    }

    /// 保留用户已排好的顺序，新出现的节点接在后面。
    private func applyNodes(_ fresh: [ProbeNode]) {
        let freshByID = Dictionary(fresh.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let kept = nodes.compactMap { freshByID[$0.id] }
        let keptIDs = Set(kept.map(\.id))
        nodes = kept + fresh.sorted { ($0.weight, $0.name) < ($1.weight, $1.name) }.filter { !keptIDs.contains($0.id) }
    }

    private func reloadConnectionAndServers() {
        tableView.reloadSections(IndexSet([Section.connection.rawValue, Section.servers.rawValue]), with: .automatic)
        updateSaveButton()
    }

    private func reloadConnection() {
        tableView.reloadSections(IndexSet(integer: Section.connection.rawValue), with: .none)
        updateSaveButton()
    }

    private func updateSaveButton() {
        navigationItem.rightBarButtonItem?.isEnabled = verifiedURL != nil && verifiedURL == normalizedURL
    }

    private func save() {
        guard let url = verifiedURL, url == normalizedURL else { return }
        let name = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let panelOrder = nodes.map(\.id)
        var instance = existing ?? ProbeInstance(name: name, baseURL: url, adapterID: adapterID)
        instance.name = name.isEmpty ? (url.host ?? "探针") : name
        if instance.baseURL != url {
            // 换了面板地址，旧的别名和顺序不再对应。
            instance.aliases = [:]
        }
        instance.baseURL = url
        if existing?.adapterID != adapterID {
            // 换了探针类型后，节点 ID 对不上，旧别名不再使用。
            instance.aliases = [:]
        }
        instance.adapterID = adapterID
        instance.hiddenNodeIDs = hiddenNodeIDs.intersection(panelOrder)
        instance.nodeOrder = panelOrder
        store.upsert(instance)
        Task { [service] in await service.forget(instanceID: instance.id) }
        dismiss(animated: true)
    }

    /// 有多种内置探针时，让用户选择类型。换类型后节点 ID 不再对应，需要重新测试。
    private func presentTypePicker() {
        let engines = registry.engines
        guard engines.count > 1 else { return }
        let alert = UIAlertController(title: "探针类型", message: nil, preferredStyle: .actionSheet)
        for engine in engines {
            let id = engine.spec.id
            alert.addAction(UIAlertAction(title: engine.spec.name, style: .default) { [weak self] _ in
                self?.selectAdapter(id)
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        let typeIndex = IndexPath(row: PanelRow.type.rawValue, section: Section.panel.rawValue)
        if let cell = tableView.cellForRow(at: typeIndex) {
            alert.popoverPresentationController?.sourceView = cell
            alert.popoverPresentationController?.sourceRect = cell.bounds
        } else {
            alert.popoverPresentationController?.sourceView = tableView
        }
        present(alert, animated: true)
    }

    func selectAdapter(_ id: String) {
        guard id != adapterID, registry.engine(id: id) != nil else { return }
        adapterID = id
        verifiedURL = nil
        nodes = []
        hiddenNodeIDs = []
        // 类型行和服务器列表一起刷新。只刷名称行时，服务器从有到无会触发表格行数校验失败。
        tableView.reloadSections(IndexSet([Section.panel.rawValue, Section.servers.rawValue]), with: .none)
        scheduleTest()
    }

    private func connectionDetail(version: String?, count: Int) -> String {
        let name = registry.engine(id: adapterID)?.spec.name
        let versionText = version.map { value in name.map { "\($0) \(value)" } ?? value }
        return [versionText, "\(count) 台服务器"].compactMap { $0 }.joined(separator: " · ")
    }

    private func confirmDelete() {
        guard let existing else { return }
        let alert = UIAlertController(title: "删除“\(existing.name)”？", message: "只删除本机的配置和缓存，不影响面板。", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "删除探针", style: .destructive) { [weak self] _ in
            guard let self else { return }
            store.remove(id: existing.id)
            Task { [service] in await service.forget(instanceID: existing.id) }
            dismiss(animated: true)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.popoverPresentationController?.sourceView = tableView
        present(alert, animated: true)
    }

    // MARK: - 表格

    override func numberOfSections(in tableView: UITableView) -> Int {
        existing == nil ? Section.allCases.count - 1 : Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .panel: return PanelRow.allCases.count
        case .connection: return 1
        case .servers: return nodes.count
        case .delete: return 1
        case .none: return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .servers: return nodes.isEmpty ? nil : "服务器 · 显示 \(nodes.count - hiddenNodeIDs.intersection(nodes.map(\.id)).count)/\(nodes.count)"
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .panel:
            let summary = registry.engine(id: adapterID)?.spec.summary ?? "只读取游客可见的数据，不需要账号密码。"
            return "\(summary)面板需要使用 HTTPS。"
        case .servers: return nodes.isEmpty ? nil : "点按切换是否显示，拖动调整顺序。"
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .panel: return panelCell(PanelRow(rawValue: indexPath.row) ?? .type, indexPath: indexPath)
        case .connection: return connectionCell()
        case .servers: return serverCell(nodes[indexPath.row])
        case .delete, .none:
            let cell = UITableViewCell()
            var content = cell.defaultContentConfiguration()
            content.text = "删除探针"
            content.textProperties.color = .systemRed
            content.textProperties.alignment = .center
            cell.contentConfiguration = content
            cell.accessibilityIdentifier = "probe-editor-delete"
            return cell
        }
    }

    private func panelCell(_ row: PanelRow, indexPath: IndexPath) -> UITableViewCell {
        switch row {
        case .type:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = "类型"
            cell.detailTextLabel?.text = registry.engine(id: adapterID)?.spec.name ?? adapterID
            cell.accessibilityIdentifier = "probe-editor-type"
            if registry.engines.count > 1 {
                cell.selectionStyle = .default
                cell.accessoryType = .disclosureIndicator
            } else {
                cell.selectionStyle = .none
            }
            return cell
        case .url, .name:
            let cell = tableView.dequeueReusableCell(withIdentifier: ProbeTextFieldCell.reuseIdentifier, for: indexPath) as! ProbeTextFieldCell
            if row == .url {
                cell.configure(title: "地址", text: urlText, placeholder: "probe.example.com", keyboard: .URL) { [weak self] text in
                    self?.urlText = text
                    self?.scheduleTest()
                }
                cell.textField.accessibilityIdentifier = "probe-editor-url"
            } else {
                cell.configure(title: "名称", text: nameText, placeholder: "默认使用域名", keyboard: .default) { [weak self] text in
                    self?.nameText = text
                }
                cell.textField.accessibilityIdentifier = "probe-editor-name"
            }
            return cell
        }
    }

    private func connectionCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.detailTextLabel?.numberOfLines = 0
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryView = nil
        switch connection {
        case .idle:
            cell.textLabel?.text = "测试连接"
            cell.textLabel?.textColor = .label
            cell.detailTextLabel?.text = "填写地址后会自动测试"
            cell.imageView?.image = UIImage(systemName: "bolt.horizontal.circle")
        case .testing:
            cell.textLabel?.text = "正在连接…"
            cell.textLabel?.textColor = .secondaryLabel
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            cell.accessoryView = spinner
            cell.imageView?.image = UIImage(systemName: "bolt.horizontal.circle")
        case .success(let version, let count):
            cell.textLabel?.text = "连接成功"
            cell.textLabel?.textColor = .label
            cell.detailTextLabel?.text = connectionDetail(version: version, count: count)
            cell.imageView?.image = UIImage(systemName: "checkmark.circle.fill")
            cell.imageView?.tintColor = .systemGreen
        case .failure(let error):
            cell.textLabel?.text = "连接失败，点按重试"
            cell.textLabel?.textColor = .systemRed
            cell.detailTextLabel?.text = error.message
            cell.imageView?.image = UIImage(systemName: "exclamationmark.triangle.fill")
            cell.imageView?.tintColor = .systemRed
        case .invalidURL:
            cell.textLabel?.text = "地址无效"
            cell.textLabel?.textColor = .systemRed
            cell.detailTextLabel?.text = "请填写 HTTPS 面板地址，例如 probe.example.com"
            cell.imageView?.image = UIImage(systemName: "link.badge.plus")
            cell.imageView?.tintColor = .systemRed
        }
        if case .success = connection {} else if case .failure = connection {} else {
            cell.imageView?.tintColor = .secondaryLabel
        }
        cell.accessibilityIdentifier = "probe-editor-connection"
        return cell
    }

    private func serverCell(_ node: ProbeNode) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let hidden = hiddenNodeIDs.contains(node.id)
        cell.textLabel?.text = [node.region, node.name].compactMap { $0 }.joined(separator: " ")
        cell.textLabel?.textColor = hidden ? .secondaryLabel : .label
        cell.detailTextLabel?.text = [node.group, node.os].compactMap { $0 }.joined(separator: " · ")
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.image = UIImage(systemName: hidden ? "circle" : "checkmark.circle.fill")
        cell.imageView?.tintColor = hidden ? .tertiaryLabel : .label
        cell.accessibilityTraits = hidden ? .button : [.button, .selected]
        cell.accessibilityHint = hidden ? "点按显示" : "点按隐藏"
        return cell
    }

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        switch Section(rawValue: indexPath.section) {
        case .panel:
            return indexPath.row == PanelRow.type.rawValue && registry.engines.count > 1
        case .connection:
            if case .testing = connection { return false }
            return true
        default: return true
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .panel:
            if indexPath.row == PanelRow.type.rawValue { presentTypePicker() }
        case .connection: testConnection()
        case .servers:
            let id = nodes[indexPath.row].id
            if hiddenNodeIDs.remove(id) == nil { hiddenNodeIDs.insert(id) }
            tableView.reloadSections(IndexSet(integer: Section.servers.rawValue), with: .none)
        case .delete: confirmDelete()
        default: break
        }
    }

    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        .none
    }

    override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        false
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == Section.servers.rawValue
    }

    override func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt source: IndexPath, toProposedIndexPath proposed: IndexPath) -> IndexPath {
        guard proposed.section == Section.servers.rawValue else {
            return IndexPath(row: proposed.section < Section.servers.rawValue ? 0 : nodes.count - 1, section: Section.servers.rawValue)
        }
        return proposed
    }

    override func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
        let node = nodes.remove(at: source.row)
        nodes.insert(node, at: destination.row)
    }
}

/// 标题 + 输入框的表单行。
final class ProbeTextFieldCell: UITableViewCell {
    static let reuseIdentifier = "ProbeTextFieldCell"

    let textField = UITextField()
    private let titleLabel = UILabel()
    private var onChange: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        textField.font = .preferredFont(forTextStyle: .body)
        textField.clearButtonMode = .whileEditing
        textField.addAction(UIAction { [weak self] _ in self?.onChange?(self?.textField.text ?? "") }, for: .editingChanged)
        textField.addAction(UIAction { [weak self] _ in self?.textField.resignFirstResponder() }, for: .editingDidEndOnExit)
        let stack = UIStackView(arrangedSubviews: [titleLabel, textField])
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 44),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, text: String, placeholder: String, keyboard: UIKeyboardType, onChange: @escaping (String) -> Void) {
        titleLabel.text = title
        textField.text = text
        textField.placeholder = placeholder
        textField.keyboardType = keyboard
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.textContentType = keyboard == .URL ? .URL : nil
        textField.returnKeyType = .done
        textField.accessibilityLabel = title
        self.onChange = onChange
    }
}
