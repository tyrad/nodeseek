//
//  CommentCopySheetViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/5/24.
//

import UIKit

final class CommentCopySheetViewController: UIViewController {
    private enum Layout {
        static let horizontalInset: CGFloat = 18
        static let verticalInset: CGFloat = 16
        static let spacing: CGFloat = 12
        static let textViewMinimumHeight: CGFloat = 180
    }

    private let text: String
    private let pasteboardStringWriter: PasteboardStringWriter

    private let titleLabel = UILabel()
    private let textView = UITextView()
    private let copyButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private var hasSelectedAllAfterPresentation = false

    init(
        text: String,
        pasteboardStringWriter: @escaping PasteboardStringWriter = { UIPasteboard.general.string = $0 }
    ) {
        self.text = text
        self.pasteboardStringWriter = pasteboardStringWriter
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheetPresentationController {
            sheetPresentationController.detents = [.medium(), .large()]
            sheetPresentationController.prefersGrabberVisible = true
            sheetPresentationController.preferredCornerRadius = 18
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureTitleLabel()
        configureTextView()
        configureButtons()
        layoutContent()
        selectAllText()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        selectAllTextAfterPresentationIfNeeded()
    }

    func copySelection() {
        let selectedText = currentSelectedText()
        let textToCopy = selectedText.isEmpty ? textView.text ?? "" : selectedText
        pasteboardStringWriter(textToCopy)
        dismiss(animated: true)
    }

    private func configureTitleLabel() {
        titleLabel.text = "复制内容"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureTextView() {
        textView.text = text
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .label
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 12
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        textView.isEditable = false
        textView.isSelectable = true
        textView.accessibilityIdentifier = "comment-copy-text-view"
        textView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureButtons() {
        configureFilledButton(copyButton, title: "复制")
        copyButton.accessibilityIdentifier = "comment-copy-selected-button"
        copyButton.addTarget(self, action: #selector(copySelectionTapped), for: .touchUpInside)

        configurePlainButton(cancelButton, title: "取消")
        cancelButton.accessibilityIdentifier = "comment-copy-cancel-button"
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
    }

    private func configureFilledButton(_ button: UIButton, title: String) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseBackgroundColor = .systemBlue
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .medium
        button.configuration = configuration
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configurePlainButton(_ button: UIButton, title: String) {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.baseForegroundColor = .label
        button.configuration = configuration
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func layoutContent() {
        let buttonStack = UIStackView(arrangedSubviews: [cancelButton, copyButton])
        buttonStack.axis = .horizontal
        buttonStack.alignment = .fill
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 8
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        view.addSubview(textView)
        view.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Layout.verticalInset),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.horizontalInset),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalInset),

            textView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Layout.spacing),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.horizontalInset),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalInset),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: Layout.textViewMinimumHeight),

            buttonStack.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: Layout.spacing),
            buttonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.horizontalInset),
            buttonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalInset),
            buttonStack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Layout.verticalInset)
        ])
    }

    private func selectAllText() {
        textView.selectedRange = NSRange(location: 0, length: (textView.text as NSString).length)
    }

    private func selectAllTextAfterPresentationIfNeeded() {
        guard hasSelectedAllAfterPresentation == false else { return }
        hasSelectedAllAfterPresentation = true
        textView.becomeFirstResponder()
        selectAllText()
    }

    private func currentSelectedText() -> String {
        let selectedRange = textView.selectedRange
        guard selectedRange.length > 0 else { return "" }
        let source = (textView.text ?? "") as NSString
        guard NSMaxRange(selectedRange) <= source.length else { return "" }
        return source.substring(with: selectedRange)
    }

    @objc private func copySelectionTapped() {
        copySelection()
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
}
