//
//  ProfileEditViewController.swift
//  nodeseek
//

import PhotosUI
import UIKit

/// 原生的个人信息编辑页：头像、Bio、签名、Readme。每一项单独保存，签名和 Readme 复用发帖编辑器。
final class ProfileEditViewController: UIViewController {
    private enum Row: Int, CaseIterable {
        case bio
        case signature
        case readme
    }

    private enum LoadState {
        case loading
        case loaded(ProfileIntroduction)
        case failed(String)
    }

    private let uid: Int
    private let account: AccountResponse
    private let client: ProfileEditClienting
    private let avatarUploader: ProfileAvatarUploading
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let headerView = ProfileEditAvatarHeaderView()
    private let statusView = ProfileEditStatusView()
    private var loadState = LoadState.loading
    private var loadTask: Task<Void, Never>?
    private var isSavingBio = false
    /// 从网页编辑返回后重新读取，网页里的修改才能显示出来。
    private var needsReloadOnAppear = false

    init(
        uid: Int,
        account: AccountResponse,
        client: ProfileEditClienting? = nil,
        avatarUploader: ProfileAvatarUploading? = nil
    ) {
        self.uid = uid
        self.account = account
        self.client = client ?? NodeSeekProfileEditClient()
        self.avatarUploader = avatarUploader ?? WebViewProfileAvatarUploader()
        super.init(nibName: nil, bundle: nil)
        title = Self.text("编辑资料")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        view.accessibilityIdentifier = "profile-edit-page"
        setupNavigationItem()
        setupTableView()
        client.prepareForSaving()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appTextSizeDidChange),
            name: AppTextSizeSettings.didChangeNotification,
            object: nil
        )
        load()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if needsReloadOnAppear {
            needsReloadOnAppear = false
            load()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 表头不走自动布局，宽度或字号变化后按内容重新算高度。
        let size = headerView.systemLayoutSizeFitting(
            CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        if headerView.frame.size != size {
            headerView.frame.size = size
            tableView.tableHeaderView = headerView
        }
    }

    // MARK: - 布局

    private func setupNavigationItem() {
        let webAction = UIAction(
            title: Self.text("在网页中编辑"),
            image: UIImage(systemName: "safari")
        ) { [weak self] _ in
            self?.openWebSettings()
        }
        let moreItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: UIMenu(children: [webAction]))
        moreItem.accessibilityLabel = Self.text("更多")
        navigationItem.rightBarButtonItem = moreItem
    }

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        headerView.configure(account: account)
        headerView.onChangeAvatar = { [weak self] in self?.pickAvatar() }
        tableView.tableHeaderView = headerView

        statusView.onRetry = { [weak self] in self?.load() }
        statusView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusView)
        NSLayoutConstraint.activate([
            statusView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 32),
            statusView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])
    }

    @objc private func appTextSizeDidChange() {
        headerView.updateTextSize()
        view.setNeedsLayout()
        tableView.reloadData()
    }

    // MARK: - 读取

    private var introduction: ProfileIntroduction? {
        if case .loaded(let introduction) = loadState { return introduction }
        return nil
    }

    private func load() {
        loadTask?.cancel()
        loadState = .loading
        render()
        loadTask = Task { @MainActor [weak self, client, uid] in
            do {
                let introduction = try await client.loadIntroduction(uid: uid)
                guard !Task.isCancelled else { return }
                self?.loadState = .loaded(introduction)
            } catch {
                guard !Task.isCancelled else { return }
                self?.loadState = .failed(error.localizedDescription)
            }
            self?.render()
        }
    }

    private func render() {
        switch loadState {
        case .loading:
            statusView.showLoading()
        case .loaded:
            statusView.isHidden = true
        case .failed(let message):
            statusView.showFailure(title: Self.text("资料加载失败"), message: message, retryTitle: Self.text("重试"))
        }
        // 表头头像一直显示，读取中和失败时只是没有资料行。
        tableView.reloadData()
    }

    // MARK: - 编辑

    private func edit(_ row: Row) {
        guard let introduction, !isSavingBio else { return }
        switch row {
        case .bio:
            editBio(current: introduction)
        case .signature, .readme:
            let editor = ProfileFieldEditorPresenter.createModule(
                field: row == .signature ? .signature : .readme,
                original: introduction,
                client: client
            ) { [weak self] saved in
                self?.didSave(saved)
            }
            present(editor, animated: true)
        }
    }

    /// Bio 只有一句话，用系统输入框改，不进全屏编辑器。
    private func editBio(current: ProfileIntroduction) {
        let alert = UIAlertController(title: "Bio", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = current.bio
            field.placeholder = Self.text("请用一句话介绍自己")
            field.clearButtonMode = .whileEditing
            field.returnKeyType = .done
        }
        let save = UIAlertAction(title: Self.text("保存"), style: .default) { [weak self, weak alert] _ in
            let bio = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard bio != current.bio else { return }
            var updated = current
            updated.bio = bio
            self?.saveBio(updated)
        }
        alert.addAction(UIAlertAction(title: Self.text("取消"), style: .cancel))
        alert.addAction(save)
        alert.preferredAction = save
        alert.view.tintColor = .label
        present(alert, animated: true)
    }

    /// 先显示新内容，后台保存；失败时恢复原内容并提示。
    private func saveBio(_ updated: ProfileIntroduction) {
        let previous = introduction
        isSavingBio = true
        loadState = .loaded(updated)
        tableView.reloadData()
        Task { @MainActor [weak self, client] in
            do {
                try await client.saveIntroduction(updated)
                self?.isSavingBio = false
                self?.didSave(updated)
            } catch {
                guard let self else { return }
                isSavingBio = false
                if let previous { loadState = .loaded(previous) }
                tableView.reloadData()
                let alert = UIAlertController(title: Self.text("保存失败"), message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: Self.text("好"), style: .cancel))
                present(alert, animated: true)
            }
        }
    }

    private func didSave(_ introduction: ProfileIntroduction) {
        loadState = .loaded(introduction)
        render()
        BottomToast.show(Self.text("已保存"), in: view)
    }

    // MARK: - 头像

    private func pickAvatar() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    func showAvatarCrop(for image: UIImage) {
        let crop = ProfileAvatarCropViewController(image: image) { [weak self] cropped in
            self?.uploadAvatar(cropped)
        }
        present(crop, animated: true)
    }

    private func uploadAvatar(_ image: UIImage) {
        guard let data = image.pngData() else { return }
        headerView.setUploading(true, preview: image)
        Task { @MainActor [weak self, avatarUploader] in
            do {
                try await avatarUploader.upload(pngData: data)
                guard let self else { return }
                await AvatarImageLoadingOptions.refreshAfterUpload(url: account.avatarURL)
                headerView.setUploading(false, preview: image)
                BottomToast.show(Self.text("头像已更新"), in: view)
            } catch {
                guard let self else { return }
                headerView.setUploading(false, preview: nil)
                headerView.configure(account: account)
                let alert = UIAlertController(title: Self.text("头像上传失败"), message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: Self.text("好"), style: .cancel))
                present(alert, animated: true)
            }
        }
    }

    private func openWebSettings() {
        needsReloadOnAppear = true
        navigationController?.pushViewController(NodeSeekWebViewController(url: NodeSeekSite.profileSettingsURL), animated: true)
    }

    // MARK: - 文案

    private static func text(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Me", comment: "")
    }

    private func title(for row: Row) -> String {
        switch row {
        case .bio: return "Bio"
        case .signature: return Self.text("签名")
        case .readme: return "Readme"
        }
    }

    private func value(for row: Row, in introduction: ProfileIntroduction) -> String {
        switch row {
        case .bio: return introduction.bio
        case .signature: return introduction.signature
        case .readme: return introduction.readme
        }
    }
}

// MARK: - PHPickerViewControllerDelegate

extension ProfileEditViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
            picker.dismiss(animated: true)
            return
        }
        provider.loadObject(ofClass: UIImage.self) { object, _ in
            DispatchQueue.main.async { [weak self] in
                // 等选图页收起后再弹裁剪页，避免两个全屏页叠在一起转场。
                picker.dismiss(animated: true) {
                    guard let image = object as? UIImage else { return }
                    self?.showAvatarCrop(for: image)
                }
            }
        }
    }
}

// MARK: - UITableViewDataSource, UITableViewDelegate

extension ProfileEditViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        introduction == nil ? 0 : 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Row.allCases.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        guard let row = Row(rawValue: indexPath.row), let introduction else { return cell }
        let value = value(for: row, in: introduction).trimmingCharacters(in: .whitespacesAndNewlines)

        var content = UIListContentConfiguration.subtitleCell()
        content.text = title(for: row)
        content.textProperties.font = AppTypography.font(basePointSize: 17)
        content.secondaryText = value.isEmpty ? Self.text("未填写") : value
        content.secondaryTextProperties.font = AppTypography.font(basePointSize: 15)
        content.secondaryTextProperties.color = value.isEmpty ? .tertiaryLabel : .secondaryLabel
        // 签名和 Readme 只露出开头，完整内容进编辑页看。
        content.secondaryTextProperties.numberOfLines = row == .bio ? 0 : 3
        content.textToSecondaryTextVerticalPadding = 4
        content.directionalLayoutMargins.top = 12
        content.directionalLayoutMargins.bottom = 12
        cell.contentConfiguration = content

        if row == .bio && isSavingBio {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            cell.accessoryView = spinner
        } else {
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
        }
        cell.accessibilityIdentifier = "profile-edit-row-\(row)"
        return cell
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        Self.text("签名显示在你的帖子和评论下方，Readme 显示在个人主页。")
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let row = Row(rawValue: indexPath.row) else { return }
        edit(row)
    }
}

/// 表头：居中的大头像和昵称，点头像更换。
final class ProfileEditAvatarHeaderView: UIView {
    var onChangeAvatar: (() -> Void)?

    private let avatarControl = UIControl()
    private let avatarImageView = UIImageView()
    /// 右下角相机标记，提示头像可以点。
    private let badgeView = UIImageView()
    private let uploadingOverlay = UIView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let nameLabel = UILabel()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupAvatar()

        nameLabel.textColor = .label
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 0

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.addArrangedSubview(avatarControl)
        stack.addArrangedSubview(nameLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
        updateTextSize()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(account: AccountResponse) {
        nameLabel.text = account.displayName
        ImageLoad.url(account.avatarURL)
            .toAvatar(requestID: account.profileURL?.lastPathComponent ?? account.displayName)
            .into(avatarImageView)
    }

    func updateTextSize() {
        nameLabel.font = AppTypography.font(basePointSize: 20, weight: .semibold)
    }

    /// 上传中头像上转圈且不可点；成功后直接显示裁好的图，失败由页面恢复原头像。
    func setUploading(_ isUploading: Bool, preview: UIImage?) {
        if let preview {
            AvatarImageLoader.shared.cancel(on: avatarImageView)
            avatarImageView.image = preview
        }
        uploadingOverlay.isHidden = !isUploading
        isUploading ? spinner.startAnimating() : spinner.stopAnimating()
        avatarControl.isEnabled = !isUploading
        avatarControl.accessibilityLabel = NSLocalizedString(isUploading ? "正在上传头像" : "更换头像", tableName: "Me", comment: "")
    }

    private func setupAvatar() {
        let size: CGFloat = 88
        avatarControl.translatesAutoresizingMaskIntoConstraints = false
        avatarControl.isAccessibilityElement = true
        avatarControl.accessibilityTraits = .button
        avatarControl.accessibilityLabel = NSLocalizedString("更换头像", tableName: "Me", comment: "")
        avatarControl.accessibilityIdentifier = "profile-edit-change-avatar"
        avatarControl.addAction(UIAction { [weak self] _ in self?.onChangeAvatar?() }, for: .touchUpInside)

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = size / 2
        avatarImageView.backgroundColor = .secondarySystemFill
        avatarImageView.accessibilityIgnoresInvertColors = true
        avatarImageView.isUserInteractionEnabled = false

        uploadingOverlay.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.5)
        uploadingOverlay.layer.cornerRadius = size / 2
        uploadingOverlay.isHidden = true
        uploadingOverlay.isUserInteractionEnabled = false
        spinner.hidesWhenStopped = true

        // 反色圆底 + 背景色描边，浅色深色下都和头像分得开。
        badgeView.image = UIImage(
            systemName: "camera.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        )
        badgeView.contentMode = .center
        badgeView.tintColor = .systemBackground
        badgeView.backgroundColor = .label
        badgeView.layer.cornerRadius = 14
        badgeView.layer.borderWidth = 2
        badgeView.layer.borderColor = UIColor.systemGroupedBackground.cgColor
        badgeView.isUserInteractionEnabled = false

        for subview in [avatarImageView, uploadingOverlay, spinner, badgeView] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            avatarControl.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            avatarControl.widthAnchor.constraint(equalToConstant: size),
            avatarControl.heightAnchor.constraint(equalToConstant: size),
            avatarImageView.topAnchor.constraint(equalTo: avatarControl.topAnchor),
            avatarImageView.leadingAnchor.constraint(equalTo: avatarControl.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: avatarControl.trailingAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: avatarControl.bottomAnchor),
            uploadingOverlay.topAnchor.constraint(equalTo: avatarControl.topAnchor),
            uploadingOverlay.leadingAnchor.constraint(equalTo: avatarControl.leadingAnchor),
            uploadingOverlay.trailingAnchor.constraint(equalTo: avatarControl.trailingAnchor),
            uploadingOverlay.bottomAnchor.constraint(equalTo: avatarControl.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: avatarControl.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: avatarControl.centerYAnchor),
            badgeView.widthAnchor.constraint(equalToConstant: 28),
            badgeView.heightAnchor.constraint(equalToConstant: 28),
            badgeView.trailingAnchor.constraint(equalTo: avatarControl.trailingAnchor, constant: 2),
            badgeView.bottomAnchor.constraint(equalTo: avatarControl.bottomAnchor, constant: 2)
        ])
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // CALayer 的颜色不会自动跟随深浅色。
        badgeView.layer.borderColor = UIColor.systemGroupedBackground.resolvedColor(with: traitCollection).cgColor
    }
}

/// 资料还没读到时显示在表头下方：读取中转圈，失败时给出原因和重试。
final class ProfileEditStatusView: UIView {
    var onRetry: (() -> Void)?

    private let spinner = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private lazy var retryButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .label
        configuration.baseForegroundColor = .systemBackground
        let button = UIButton(configuration: configuration)
        button.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .secondaryLabel
        [titleLabel, messageLabel].forEach {
            $0.numberOfLines = 0
            $0.textAlignment = .center
        }
        let stack = UIStackView(arrangedSubviews: [spinner, titleLabel, messageLabel, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.setCustomSpacing(16, after: messageLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showLoading() {
        isHidden = false
        spinner.startAnimating()
        spinner.isHidden = false
        [titleLabel, messageLabel, retryButton].forEach { $0.isHidden = true }
    }

    func showFailure(title: String, message: String, retryTitle: String) {
        isHidden = false
        spinner.stopAnimating()
        spinner.isHidden = true
        titleLabel.text = title
        messageLabel.text = message
        retryButton.configuration?.title = retryTitle
        [titleLabel, messageLabel, retryButton].forEach { $0.isHidden = false }
    }
}
