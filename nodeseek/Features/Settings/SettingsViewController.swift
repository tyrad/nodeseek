//
//  SettingsViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/5/2.
//

import UIKit

struct SettingsBuildInfo: Equatable {
    let appVersion: String
    let buildNumber: String
    let gitSHA: String?
    let workflowName: String?
    let githubRunID: String?
    let githubRunURL: URL?

    init(
        appVersion: String,
        buildNumber: String,
        gitSHA: String? = nil,
        workflowName: String? = nil,
        githubRunID: String? = nil,
        githubRunURL: URL? = nil
    ) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.gitSHA = gitSHA
        self.workflowName = workflowName
        self.githubRunID = githubRunID
        self.githubRunURL = githubRunURL
    }

    init(bundle: Bundle = .main) {
        let info = bundle.infoDictionary ?? [:]
        self.init(
            appVersion: Self.stringValue(info["CFBundleShortVersionString"]) ?? "未知",
            buildNumber: Self.stringValue(info["CFBundleVersion"]) ?? "未知",
            gitSHA: Self.stringValue(info["Build Git SHA"]),
            workflowName: Self.stringValue(info["Build Workflow"]),
            githubRunID: Self.stringValue(info["Build GitHub Run ID"]),
            githubRunURL: Self.urlValue(info["Build GitHub Run URL"])
        )
    }

    var shortGitSHA: String {
        guard let gitSHA, gitSHA.isEmpty == false else {
            return "未注入"
        }
        return String(gitSHA.prefix(7))
    }

    var workflowDisplayText: String {
        switch (workflowName, githubRunID) {
        case let (workflow?, runID?) where !workflow.isEmpty && !runID.isEmpty:
            return "\(workflow) #\(runID)"
        case let (workflow?, _) where !workflow.isEmpty:
            return workflow
        case let (_, runID?) where !runID.isEmpty:
            return "Run #\(runID)"
        default:
            return "本地构建"
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        return string.isEmpty ? nil : string
    }

    private static func urlValue(_ value: Any?) -> URL? {
        guard let string = stringValue(value) else { return nil }
        return URL(string: string)
    }
}

@MainActor
protocol NodeImageAuthorizationPresenting: AnyObject {
    func presentAuthorization(
        from presentingViewController: UIViewController,
        onAPIKey: @escaping @MainActor (String) -> Void
    )
}

@MainActor
final class DefaultNodeImageAuthorizationPresenter: NodeImageAuthorizationPresenting {
    func presentAuthorization(
        from presentingViewController: UIViewController,
        onAPIKey: @escaping @MainActor (String) -> Void
    ) {
        let authViewController = NodeImageAuthViewController { [weak presentingViewController] apiKey in
            presentingViewController?.dismiss(animated: true) {
                Task { @MainActor in
                    onAPIKey(apiKey)
                }
            }
        }
        presentingViewController.present(UINavigationController(rootViewController: authViewController), animated: true)
    }
}

class SettingsViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case reading
        case features
        case storage
        case debug
        case about
        case account
    }

    private enum ReadingRow: Int, CaseIterable {
        case categoryPreferences
        case adjustment
        case preview
        case signatureDisplay
    }

    private enum FeatureRow: Int, CaseIterable {
        case nodeImage
        case specialFollow
    }

    private enum BuildRow: Int, CaseIterable {
        case appVersion
        case buildNumber
        case gitSHA
        case repository
        case workflow
        case githubURL
    }

    private enum DebugRow: Int, CaseIterable {
        case fileLogging
        case logFile
        case detailTest
        #if DEBUG
        case debugLinks
        #endif

        static var visibleRows: [DebugRow] {
            var rows: [DebugRow] = [.fileLogging, .logFile]
            #if DEBUG
            if NodeSeekDebugConfig.enablePostDetailTestEntry {
                rows.append(.detailTest)
                rows.append(.debugLinks)
            }
            #endif
            return rows
        }
    }

    private let cacheManager: SettingsCacheManaging
    private let repositoryURL = URL(string: "https://github.com/tyrad/nodeseek")!
    private let sessionManager: SettingsSessionManaging
    private let currentAccountStore: CurrentAccountStore
    private let buildInfo: SettingsBuildInfo
    private let nodeImageAPIKeyStore: NodeImageAPIKeyStoring
    private let nodeImageAuthorizationPresenter: NodeImageAuthorizationPresenting
    private let textSizeSettings: AppTextSizeSettings
    private let signatureDisplaySettings: PostSignatureDisplaySettings
    private let categoryPreferenceStore: PostCategoryPreferenceStore
    private let specialFollowKeywordStore: SpecialFollowKeywordStore
    private let confirmsActionsImmediately: Bool
    private let onLogout: @MainActor () -> Void
    private let onLogFile: @MainActor () -> Void
    private let onDetailTest: (@MainActor () -> Void)?
    private var cacheByteSize: UInt64?
    private var isLoggedIn = false
    private var isClearingCache = false
    private var isLoggingOut = false

    init(
        cacheManager: SettingsCacheManaging? = nil,
        sessionManager: SettingsSessionManaging? = nil,
        currentAccountStore: CurrentAccountStore = .shared,
        buildInfo: SettingsBuildInfo = SettingsBuildInfo(),
        nodeImageAPIKeyStore: NodeImageAPIKeyStoring = KeychainNodeImageAPIKeyStore(),
        nodeImageAuthorizationPresenter: NodeImageAuthorizationPresenting? = nil,
        textSizeSettings: AppTextSizeSettings = .shared,
        signatureDisplaySettings: PostSignatureDisplaySettings = .shared,
        categoryPreferenceStore: PostCategoryPreferenceStore = .shared,
        specialFollowKeywordStore: SpecialFollowKeywordStore = .shared,
        confirmsActionsImmediately: Bool = false,
        onLogout: @escaping @MainActor () -> Void = {},
        onLogFile: @escaping @MainActor () -> Void = {},
        onDetailTest: (@MainActor () -> Void)? = nil
    ) {
        self.cacheManager = cacheManager ?? DefaultSettingsCacheManager()
        self.sessionManager = sessionManager ?? DefaultSettingsSessionManager()
        self.currentAccountStore = currentAccountStore
        self.buildInfo = buildInfo
        self.nodeImageAPIKeyStore = nodeImageAPIKeyStore
        self.nodeImageAuthorizationPresenter = nodeImageAuthorizationPresenter ?? DefaultNodeImageAuthorizationPresenter()
        self.textSizeSettings = textSizeSettings
        self.signatureDisplaySettings = signatureDisplaySettings
        self.categoryPreferenceStore = categoryPreferenceStore
        self.specialFollowKeywordStore = specialFollowKeywordStore
        self.confirmsActionsImmediately = confirmsActionsImmediately
        self.onLogout = onLogout
        self.onLogFile = onLogFile
        self.onDetailTest = onDetailTest
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        tableView.accessibilityIdentifier = "settings-table-view"
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SettingsCell")
        tableView.register(
            SettingsTextSizeAdjustmentCell.self,
            forCellReuseIdentifier: "SettingsTextSizeAdjustmentCell"
        )
        tableView.register(
            SettingsTextSizePreviewCell.self,
            forCellReuseIdentifier: "SettingsTextSizePreviewCell"
        )
        refreshCacheSize()
        refreshAccountState()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(specialFollowKeywordsDidChange(_:)),
            name: SpecialFollowKeywordStore.didChangeNotification,
            object: specialFollowKeywordStore
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(postCategoryPreferencesDidChange(_:)),
            name: PostCategoryPreferenceStore.didChangeNotification,
            object: categoryPreferenceStore
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .reading:
            return ReadingRow.allCases.count
        case .features:
            return FeatureRow.allCases.count
        case .storage:
            return 1
        case .debug:
            return DebugRow.visibleRows.count
        case .about:
            return BuildRow.allCases.count
        case .account:
            return isLoggedIn ? 1 : 0
        case .none:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .reading:
            return "阅读"
        case .features:
            return "功能"
        case .storage:
            return "存储"
        case .debug:
            return "调试"
        case .about:
            return "关于"
        case .account:
            return isLoggedIn ? "账号" : nil
        case .none:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .reading:
            return readingCell(for: indexPath)
        case .features:
            return featureCell(for: indexPath)
        case .storage:
            return cacheCell(for: indexPath)
        case .debug:
            return debugCell(for: indexPath)
        case .about:
            return buildCell(for: indexPath)
        case .account:
            return logoutCell(for: indexPath)
        case .none:
            return UITableViewCell()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .reading:
            handleReadingSelection(at: indexPath)
        case .features:
            handleFeatureSelection(at: indexPath)
        case .storage:
            confirmClearCache()
        case .debug:
            handleDebugSelection(at: indexPath)
        case .about:
            handleBuildSelection(at: indexPath)
        case .account:
            guard isLoggedIn else { return }
            confirmLogout()
        case .none:
            break
        }
    }

    private func cacheCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = isClearingCache ? "正在清除缓存..." : "清除缓存"
        cell.detailTextLabel?.text = cacheDetailText
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = isClearingCache ? .none : .default
        cell.isUserInteractionEnabled = !isClearingCache
        cell.accessibilityIdentifier = "settings-clear-cache-cell"
        return cell
    }

    private func readingCell(for indexPath: IndexPath) -> UITableViewCell {
        switch ReadingRow(rawValue: indexPath.row) {
        case .adjustment:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: "SettingsTextSizeAdjustmentCell",
                for: indexPath
            ) as? SettingsTextSizeAdjustmentCell else {
                return UITableViewCell()
            }
            cell.configure(pointOffset: textSizeSettings.pointOffset)
            cell.onPointOffsetChanged = { [weak self] pointOffset in
                self?.updateTextSize(pointOffset: pointOffset)
            }
            return cell
        case .preview:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: "SettingsTextSizePreviewCell",
                for: indexPath
            ) as? SettingsTextSizePreviewCell else {
                return UITableViewCell()
            }
            cell.configure(pointOffset: textSizeSettings.pointOffset)
            return cell
        case .categoryPreferences:
            return categoryPreferencesCell(for: indexPath)
        case .signatureDisplay:
            return signatureDisplayCell(for: indexPath)
        case .none:
            return UITableViewCell()
        }
    }

    private func featureCell(for indexPath: IndexPath) -> UITableViewCell {
        switch FeatureRow(rawValue: indexPath.row) {
        case .nodeImage:
            return nodeImageAuthorizationCell(for: indexPath)
        case .specialFollow:
            return specialFollowCell(for: indexPath)
        case .none:
            return UITableViewCell()
        }
    }

    private func nodeImageAuthorizationCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        if hasNodeImageAuthorization {
            cell.textLabel?.text = "取消 NodeImage 授权"
            cell.textLabel?.textColor = .systemRed
            cell.imageView?.image = UIImage(systemName: "xmark.circle")
            cell.accessoryType = .none
        } else {
            cell.textLabel?.text = "NodeImage 授权"
            cell.textLabel?.textColor = .label
            cell.imageView?.image = UIImage(systemName: "photo.badge.plus")
            cell.accessoryType = .disclosureIndicator
        }
        cell.accessibilityIdentifier = "settings-nodeimage-authorization-cell"
        return cell
    }

    private func signatureDisplayCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = "显示帖子签名"
        cell.imageView?.image = UIImage(systemName: "signature")
        let signatureSwitch = UISwitch()
        signatureSwitch.isOn = signatureDisplaySettings.showsSignatures
        signatureSwitch.accessibilityIdentifier = "settings-post-signature-switch"
        signatureSwitch.addTarget(self, action: #selector(signatureDisplaySwitchChanged(_:)), for: .valueChanged)
        cell.accessoryView = signatureSwitch
        cell.selectionStyle = .none
        cell.accessibilityIdentifier = "settings-post-signature-cell"
        return cell
    }

    private func categoryPreferencesCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = "首页分类"
        cell.detailTextLabel?.text = categoryPreferenceDetailText
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 2
        cell.imageView?.image = UIImage(systemName: "list.bullet.rectangle")
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "settings-post-category-preferences-cell"
        return cell
    }

    private func specialFollowCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = "特别关注"
        cell.detailTextLabel?.text = specialFollowDetailText
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 2
        cell.imageView?.image = UIImage(systemName: "star.circle")
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "settings-special-follow-cell"
        return cell
    }

    private func logoutCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = isLoggingOut ? "正在退出登录..." : "退出登录"
        cell.textLabel?.textColor = .systemRed
        cell.textLabel?.textAlignment = .center
        cell.selectionStyle = isLoggingOut ? .none : .default
        cell.isUserInteractionEnabled = !isLoggingOut
        cell.accessibilityIdentifier = "settings-logout-cell"
        return cell
    }

    private func buildCell(for indexPath: IndexPath) -> UITableViewCell {
        let buildRow = BuildRow(rawValue: indexPath.row)
        let usesSubtitle = buildRow == .repository || buildRow == .githubURL
        let cell = UITableViewCell(style: usesSubtitle ? .subtitle : .value1, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = usesSubtitle ? 2 : 1
        switch buildRow {
        case .appVersion:
            cell.textLabel?.text = "版本"
            cell.detailTextLabel?.text = buildInfo.appVersion
            cell.accessibilityIdentifier = "settings-version-cell"
        case .buildNumber:
            cell.textLabel?.text = "Build"
            cell.detailTextLabel?.text = buildInfo.buildNumber
            cell.accessibilityIdentifier = "settings-build-number-cell"
        case .gitSHA:
            cell.textLabel?.text = "Git"
            cell.detailTextLabel?.text = buildInfo.shortGitSHA
            cell.accessibilityIdentifier = "settings-git-sha-cell"
        case .repository:
            cell.textLabel?.text = "仓库"
            cell.detailTextLabel?.text = repositoryURL.absoluteString
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            cell.accessibilityIdentifier = "settings-github-repository-cell"
        case .workflow:
            cell.textLabel?.text = "Workflow"
            cell.detailTextLabel?.text = buildInfo.workflowDisplayText
            cell.accessoryType = buildInfo.githubRunURL == nil ? .none : .disclosureIndicator
            cell.selectionStyle = buildInfo.githubRunURL == nil ? .none : .default
            cell.accessibilityIdentifier = "settings-workflow-cell"
        case .githubURL:
            cell.textLabel?.text = "GitHub"
            cell.detailTextLabel?.text = buildInfo.githubRunURL?.absoluteString ?? "未注入"
            cell.accessibilityIdentifier = "settings-github-run-url-cell"
        case .none:
            break
        }
        return cell
    }

    private func debugCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        switch DebugRow.visibleRows[indexPath.row] {
        case .fileLogging:
            cell.textLabel?.text = "记录日志"
            let loggingSwitch = UISwitch()
            loggingSwitch.isOn = NodeSeekDebugConfig.enableFileLogging
            loggingSwitch.accessibilityIdentifier = "settings-file-logging-switch"
            loggingSwitch.addTarget(self, action: #selector(fileLoggingSwitchChanged(_:)), for: .valueChanged)
            cell.accessoryView = loggingSwitch
            cell.selectionStyle = .none
            cell.accessibilityIdentifier = "settings-file-logging-cell"
            return cell
        case .logFile:
            cell.textLabel?.text = "日志文件"
            cell.imageView?.image = UIImage(systemName: "doc.text")
            cell.accessibilityIdentifier = "settings-log-file-cell"
        case .detailTest:
            cell.textLabel?.text = "详情测试"
            cell.imageView?.image = UIImage(systemName: "doc.text.magnifyingglass")
            cell.accessibilityIdentifier = "settings-detail-test-cell"
        #if DEBUG
        case .debugLinks:
            cell.textLabel?.text = "调试链接"
            cell.imageView?.image = UIImage(systemName: "link")
            cell.accessibilityIdentifier = "settings-debug-links-cell"
        #endif
        }
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private var cacheDetailText: String {
        guard let cacheByteSize else {
            return "计算中"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(cacheByteSize), countStyle: .file)
    }

    private var hasNodeImageAuthorization: Bool {
        nodeImageAPIKeyStore.apiKey()?.isEmpty == false
    }

    private var specialFollowDetailText: String {
        let count = specialFollowKeywordStore.count
        guard count > 0 else {
            return "帖子列表关键字高亮展示"
        }
        return "帖子列表关键字高亮展示 · \(count) 个"
    }

    private var categoryPreferenceDetailText: String {
        let visible = categoryPreferenceStore.visibleCategoryItems
        let hiddenCount = categoryPreferenceStore.hiddenCategoryItems.count
        guard hiddenCount == 0 else {
            return "显示 \(visible.count) 个，隐藏 \(hiddenCount) 个"
        }

        let prefix = visible.prefix(3).map(\.title).joined(separator: "、")
        if visible.count > 3 {
            return "\(prefix)等 \(visible.count) 个"
        }
        return prefix
    }

    private func refreshCacheSize() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            cacheByteSize = await cacheManager.cacheByteSize()
            tableView.reloadSections(IndexSet(integer: Section.storage.rawValue), with: .none)
        }
    }

    private func refreshAccountState() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = await currentAccountStore.snapshot()
            isLoggedIn = snapshot?.account.isLoggedIn == true
            tableView.reloadSections(IndexSet(integer: Section.account.rawValue), with: .none)
        }
    }

    private func updateTextSize(pointOffset: CGFloat) {
        textSizeSettings.setPointOffset(pointOffset)
        let previewIndexPath = IndexPath(row: ReadingRow.preview.rawValue, section: Section.reading.rawValue)
        if let previewCell = tableView.cellForRow(at: previewIndexPath) as? SettingsTextSizePreviewCell {
            previewCell.configure(pointOffset: textSizeSettings.pointOffset)
            UIView.performWithoutAnimation {
                tableView.beginUpdates()
                tableView.endUpdates()
            }
        } else {
            tableView.reloadRows(at: [previewIndexPath], with: .none)
        }
    }

    private func handleFeatureSelection(at indexPath: IndexPath) {
        switch FeatureRow(rawValue: indexPath.row) {
        case .nodeImage:
            handleNodeImageAuthorizationSelection()
        case .specialFollow:
            showSpecialFollowKeywords()
        case .none:
            break
        }
    }

    private func handleReadingSelection(at indexPath: IndexPath) {
        switch ReadingRow(rawValue: indexPath.row) {
        case .categoryPreferences:
            showPostCategoryPreferences()
        case .adjustment, .preview, .signatureDisplay, .none:
            break
        }
    }

    private func confirmClearCache() {
        guard !isClearingCache else { return }
        guard !confirmsActionsImmediately else {
            performClearCache()
            return
        }

        let alert = UIAlertController(
            title: "清除缓存",
            message: "将清除图片、网页和网络缓存，但会保留登录状态。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { [weak self] _ in
            self?.performClearCache()
        })
        present(alert, animated: true)
    }

    private func handleNodeImageAuthorizationSelection() {
        if hasNodeImageAuthorization {
            confirmCancelNodeImageAuthorization()
        } else {
            presentNodeImageAuthorization()
        }
    }

    private func showSpecialFollowKeywords() {
        let viewController = SpecialFollowKeywordsViewController(store: specialFollowKeywordStore)
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func showPostCategoryPreferences() {
        let viewController = PostCategoryPreferencesViewController(store: categoryPreferenceStore)
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func confirmCancelNodeImageAuthorization() {
        guard !confirmsActionsImmediately else {
            performCancelNodeImageAuthorization()
            return
        }

        let alert = UIAlertController(
            title: "取消 NodeImage 授权",
            message: "将清除本机保存的 NodeImage API Key，不会退出 NodeSeek。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "取消授权", style: .destructive) { [weak self] _ in
            self?.performCancelNodeImageAuthorization()
        })
        present(alert, animated: true)
    }

    private func performCancelNodeImageAuthorization() {
        nodeImageAPIKeyStore.clear()
        tableView.reloadSections(IndexSet(integer: Section.features.rawValue), with: .none)
        showAlert(title: "已取消 NodeImage 授权", message: "之后上传图片时需要重新授权。")
    }

    private func presentNodeImageAuthorization() {
        nodeImageAuthorizationPresenter.presentAuthorization(from: self) { [weak self] apiKey in
            guard let self else { return }
            nodeImageAPIKeyStore.save(apiKey: apiKey)
            tableView.reloadSections(IndexSet(integer: Section.features.rawValue), with: .none)
        }
    }

    private func confirmLogout() {
        guard !isLoggingOut else { return }
        guard !confirmsActionsImmediately else {
            performLogout()
            return
        }

        let alert = UIAlertController(
            title: "退出登录",
            message: "将清除 NodeSeek 登录 Cookie 和本地账号状态。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "退出登录", style: .destructive) { [weak self] _ in
            self?.performLogout()
        })
        present(alert, animated: true)
    }

    private func handleDebugSelection(at indexPath: IndexPath) {
        switch DebugRow.visibleRows[indexPath.row] {
        case .fileLogging:
            break
        case .logFile:
            onLogFile()
        case .detailTest:
            guard let onDetailTest else { return }
            onDetailTest()
        #if DEBUG
        case .debugLinks:
            guard NodeSeekDebugConfig.enablePostDetailTestEntry else { return }
            navigationController?.pushViewController(PostDetailDebugLinksViewController(), animated: true)
        #endif
        }
    }

    private func handleBuildSelection(at indexPath: IndexPath) {
        switch BuildRow(rawValue: indexPath.row) {
        case .repository:
            UIApplication.shared.open(repositoryURL)
        case .workflow:
            guard let githubRunURL = buildInfo.githubRunURL else { return }
            UIApplication.shared.open(githubRunURL)
        case .appVersion, .buildNumber, .gitSHA, .githubURL, .none:
            return
        }
    }

    @objc private func fileLoggingSwitchChanged(_ sender: UISwitch) {
        NodeSeekDebugConfig.enableFileLogging = sender.isOn
    }

    @objc private func signatureDisplaySwitchChanged(_ sender: UISwitch) {
        signatureDisplaySettings.setShowsSignatures(sender.isOn)
    }

    @objc private func specialFollowKeywordsDidChange(_ notification: Notification) {
        tableView.reloadSections(IndexSet(integer: Section.features.rawValue), with: .none)
    }

    @objc private func postCategoryPreferencesDidChange(_ notification: Notification) {
        let indexPath = IndexPath(row: ReadingRow.categoryPreferences.rawValue, section: Section.reading.rawValue)
        tableView.reloadRows(at: [indexPath], with: .none)
    }

    private func performClearCache() {
        isClearingCache = true
        tableView.reloadRows(at: [IndexPath(row: 0, section: Section.storage.rawValue)], with: .none)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await cacheManager.clearPreservingCookies()
                cacheByteSize = await cacheManager.cacheByteSize()
                isClearingCache = false
                tableView.reloadSections(IndexSet(integer: Section.storage.rawValue), with: .none)
                showAlert(title: "已清除缓存", message: "登录状态已保留。")
            } catch {
                isClearingCache = false
                tableView.reloadSections(IndexSet(integer: Section.storage.rawValue), with: .none)
                showAlert(title: "清除失败", message: error.localizedDescription)
            }
        }
    }

    private func performLogout() {
        isLoggingOut = true
        tableView.reloadRows(at: [IndexPath(row: 0, section: Section.account.rawValue)], with: .none)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await sessionManager.logout()
            isLoggingOut = false
            isLoggedIn = false
            tableView.reloadSections(IndexSet(integer: Section.account.rawValue), with: .none)
            onLogout()
            navigationController?.popViewController(animated: true)
        }
    }

    private func showAlert(title: String, message: String) {
        guard !confirmsActionsImmediately else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

#if DEBUG
final class PostDetailDebugLinksViewController: UITableViewController {
    private let links: [PostDetailDebugLink]
    private let onSelectTarget: @MainActor (PostDetailTestTarget, UIViewController) -> Void

    init(
        links: [PostDetailDebugLink] = PostDetailDebugLink.allCases,
        onSelectTarget: (@MainActor (PostDetailTestTarget, UIViewController) -> Void)? = nil
    ) {
        self.links = links
        self.onSelectTarget = onSelectTarget ?? { target, viewController in
            let detailViewController = PostDetailRouter.createModule(
                post: target.post,
                page: target.page,
                initialAnchorID: target.anchorID
            )
            viewController.navigationController?.pushViewController(detailViewController, animated: true)
        }
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "调试链接"
        tableView.accessibilityIdentifier = "post-detail-debug-links-table-view"
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        links.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let link = links[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = link.title
        cell.detailTextLabel?.text = link.url.absoluteString
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 2
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "post-detail-debug-link-cell-\(indexPath.row)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let target = links[indexPath.row].target else { return }
        onSelectTarget(target, self)
    }
}
#endif
