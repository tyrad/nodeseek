//
//  LogFileViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/5/2.
//

import UIKit

final class LogFileViewController: UIViewController {
    private let textView: UITextView = {
        let textView = UITextView()
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .label
        textView.backgroundColor = .systemBackground
        textView.isEditable = false
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        textView.accessibilityIdentifier = "log-file-content-text-view"
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "文件日志"
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItems = [
            makeBarButton(
                systemName: "trash",
                accessibilityLabel: "删除文件日志",
                action: #selector(deleteButtonTapped),
                tintColor: .systemRed
            ),
            makeBarButton(
                systemName: "doc.on.doc",
                accessibilityLabel: "复制文件日志",
                action: #selector(copyButtonTapped)
            ),
            makeBarButton(
                systemName: "arrow.clockwise",
                accessibilityLabel: "刷新文件日志",
                action: #selector(refreshButtonTapped)
            )
        ]

        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        reloadContent()
    }

    private func makeBarButton(
        systemName: String,
        accessibilityLabel: String,
        action: Selector,
        tintColor: UIColor? = nil
    ) -> UIBarButtonItem {
        let button = UIBarButtonItem(
            image: UIImage(systemName: systemName),
            style: .plain,
            target: self,
            action: action
        )
        button.accessibilityLabel = accessibilityLabel
        button.tintColor = tintColor
        return button
    }

    @objc private func refreshButtonTapped() {
        reloadContent()
    }

    @objc private func copyButtonTapped() {
        UIPasteboard.general.string = textView.text
    }

    @objc private func deleteButtonTapped() {
        let alert = UIAlertController(
            title: "删除日志文件？",
            message: "将删除当前 DEBUG 文件日志，操作不可撤销。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            self?.deleteLogFile()
        })
        present(alert, animated: true)
    }

    private func deleteLogFile() {
        do {
            try AppLog.deleteFileLog()
            reloadContent()
        } catch {
            textView.text = "删除文件日志失败：\(error.localizedDescription)"
        }
    }

    private func reloadContent() {
        #if DEBUG
        let pathLine = "路径：\(AppLog.fileLogURL.path)"
        if NodeSeekDebugConfig.enableFileLogging == false {
            textView.text = "文件日志未开启\n\(pathLine)\n\n将 NodeSeekDebugConfig.enableFileLogging 设为 true 后，新的 AppLog 记录会写入这里。"
            scrollToBottom()
            return
        }

        do {
            let content = try AppLog.fileLogContent()
            textView.text = content.isEmpty ? "暂无文件日志\n\(pathLine)" : "\(pathLine)\n\n\(content)"
            scrollToBottom()
        } catch {
            textView.text = "读取文件日志失败：\(error.localizedDescription)\n\(pathLine)"
        }
        #else
        textView.text = "文件日志只在 DEBUG 环境可用。"
        scrollToBottom()
        #endif
    }

    private func scrollToBottom() {
        let textLength = (textView.text as NSString).length
        guard textLength > 0 else { return }
        let bottomRange = NSRange(location: textLength - 1, length: 1)
        DispatchQueue.main.async { [weak self] in
            self?.textView.scrollRangeToVisible(bottomRange)
        }
    }
}
