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
            UIBarButtonItem(
                image: UIImage(systemName: "doc.on.doc"),
                style: .plain,
                target: self,
                action: #selector(copyButtonTapped)
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "arrow.clockwise"),
                style: .plain,
                target: self,
                action: #selector(refreshButtonTapped)
            )
        ]
        navigationItem.rightBarButtonItems?[0].accessibilityLabel = "复制文件日志"
        navigationItem.rightBarButtonItems?[1].accessibilityLabel = "刷新文件日志"

        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        reloadContent()
    }

    @objc private func refreshButtonTapped() {
        reloadContent()
    }

    @objc private func copyButtonTapped() {
        UIPasteboard.general.string = textView.text
    }

    private func reloadContent() {
        #if DEBUG
        let pathLine = "路径：\(AppLog.fileLogURL.path)"
        if NodeSeekDebugConfig.enableFileLogging == false {
            textView.text = "文件日志未开启\n\(pathLine)\n\n将 NodeSeekDebugConfig.enableFileLogging 设为 true 后，新的 AppLog 记录会写入这里。"
            return
        }

        do {
            let content = try AppLog.fileLogContent()
            textView.text = content.isEmpty ? "暂无文件日志\n\(pathLine)" : "\(pathLine)\n\n\(content)"
        } catch {
            textView.text = "读取文件日志失败：\(error.localizedDescription)\n\(pathLine)"
        }
        #else
        textView.text = "文件日志只在 DEBUG 环境可用。"
        #endif
    }
}
