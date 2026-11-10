import UIKit

/// 底部悬浮搜索框。不用系统的 searchController：iOS 26 把它放到底部后会占用导航栈的底部安全区，
/// 返回时底栏会跟着上移一下。
final class ProbeSearchBarView: UIView, UITextFieldDelegate {
    var onChange: ((String) -> Void)?
    var text: String { textField.text ?? "" }

    let textField = UITextField()
    private let capsule = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let cancelButton = UIButton(type: .system)
    private var cancelVisibleConstraint: NSLayoutConstraint!
    private var cancelHiddenConstraint: NSLayoutConstraint!
    static let height: CGFloat = 46

    override init(frame: CGRect) {
        super.init(frame: frame)
        capsule.layer.cornerRadius = Self.height / 2
        capsule.layer.cornerCurve = .continuous
        capsule.clipsToBounds = true
        capsule.layer.borderWidth = 1 / UIScreen.main.scale
        // 阴影放在外层，胶囊本身要裁圆角。
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)

        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        icon.tintColor = .secondaryLabel
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        textField.placeholder = "搜索名称、地区、分组"
        textField.font = .systemFont(ofSize: 16)
        textField.textColor = .label
        textField.clearButtonMode = .whileEditing
        textField.returnKeyType = .search
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.delegate = self
        textField.accessibilityIdentifier = "probe-search-field"
        textField.addAction(UIAction { [weak self] _ in self?.notifyChange() }, for: .editingChanged)

        cancelButton.setTitle("取消", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        cancelButton.tintColor = .label
        cancelButton.alpha = 0
        cancelButton.accessibilityIdentifier = "probe-search-cancel"
        cancelButton.setContentHuggingPriority(.required, for: .horizontal)
        cancelButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        cancelButton.addAction(UIAction { [weak self] _ in self?.cancel() }, for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [icon, textField])
        row.alignment = .center
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        capsule.contentView.addSubview(row)
        [capsule, cancelButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        cancelVisibleConstraint = capsule.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -12)
        cancelHiddenConstraint = capsule.trailingAnchor.constraint(equalTo: trailingAnchor)
        NSLayoutConstraint.activate([
            capsule.topAnchor.constraint(equalTo: topAnchor),
            capsule.bottomAnchor.constraint(equalTo: bottomAnchor),
            capsule.leadingAnchor.constraint(equalTo: leadingAnchor),
            capsule.heightAnchor.constraint(equalToConstant: Self.height),
            cancelHiddenConstraint,
            cancelButton.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.leadingAnchor.constraint(equalTo: capsule.contentView.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: capsule.contentView.trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: capsule.contentView.topAnchor),
            row.bottomAnchor.constraint(equalTo: capsule.contentView.bottomAnchor),
        ])
        updateBorder()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateBorder()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: capsule.frame, cornerRadius: Self.height / 2).cgPath
    }

    func cancel() {
        let hadText = !text.isEmpty
        textField.text = nil
        textField.resignFirstResponder()
        if hadText { notifyChange() }
    }

    // MARK: - UITextFieldDelegate

    func textFieldDidBeginEditing(_ textField: UITextField) { setCancelVisible(true) }

    func textFieldDidEndEditing(_ textField: UITextField) {
        // 有搜索词时保留“取消”，方便一键清空。
        setCancelVisible(!text.isEmpty)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    private func notifyChange() { onChange?(text) }

    private func setCancelVisible(_ visible: Bool) {
        guard cancelVisibleConstraint.isActive != visible else { return }
        cancelHiddenConstraint.isActive = !visible
        cancelVisibleConstraint.isActive = visible
        UIView.animate(withDuration: window == nil ? 0 : 0.25, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            self.cancelButton.alpha = visible ? 1 : 0
            self.layoutIfNeeded()
        }
    }

    private func updateBorder() {
        capsule.layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
    }
}
