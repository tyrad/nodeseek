//
//  SpecialFollowKeywordsViewController.swift
//  nodeseek
//

import UIKit
import UniformTypeIdentifiers

final class SpecialFollowKeywordsViewController: UITableViewController {
    private let store: SpecialFollowKeywordStore
    private var keywords: [SpecialFollowKeyword] = []

    init(store: SpecialFollowKeywordStore = .shared) {
        self.store = store
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "特别关注"
        tableView.accessibilityIdentifier = "special-follow-keywords-table-view"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SpecialFollowKeywordCell")
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(systemItem: .add, primaryAction: UIAction { [weak self] _ in
                self?.presentKeywordEditor(keyword: nil)
            }),
            UIBarButtonItem(
                image: UIImage(systemName: "ellipsis.circle"),
                menu: UIMenu(children: [
                    UIAction(title: "导入 JSON", image: UIImage(systemName: "square.and.arrow.down")) { [weak self] _ in
                        self?.presentImportPicker()
                    },
                    UIAction(title: "导出 JSON", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                        self?.presentExportSheet()
                    }
                ])
            )
        ]
        reloadKeywords()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadKeywords()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        keywords.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let keyword = keywords[indexPath.row]
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = keyword.keyword
        cell.detailTextLabel?.text = keyword.colorHex
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.image = colorSwatchImage(colorHex: keyword.colorHex)
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "special-follow-keyword-cell-\(indexPath.row)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        presentActions(for: keywords[indexPath.row])
    }

    override func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete else { return }
        store.delete(keyword: keywords[indexPath.row].keyword)
        reloadKeywords()
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if keywords.isEmpty {
            return "添加关键词后，首页帖子标题和发帖人命中时会按颜色高亮。右滑删除关键词。"
        }
        return "右滑删除关键词。"
    }

    func saveKeywordForTesting(keyword: String, colorHex: String) throws {
        try store.save(keyword: keyword, colorHex: colorHex)
        reloadKeywords()
    }

    func deleteKeywordForTesting(keyword: String) {
        store.delete(keyword: keyword)
        reloadKeywords()
    }

    private func reloadKeywords() {
        keywords = store.keywords
        tableView.reloadData()
    }

    private func presentActions(for keyword: SpecialFollowKeyword) {
        let alert = UIAlertController(title: keyword.keyword, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "编辑关键词", style: .default) { [weak self] _ in
            self?.presentKeywordEditor(keyword: keyword)
        })
        alert.addAction(UIAlertAction(title: "选择颜色", style: .default) { [weak self] _ in
            self?.presentPresetColorPicker(for: keyword)
        })
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            self?.store.delete(keyword: keyword.keyword)
            self?.reloadKeywords()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = tableView.rectForRow(at: IndexPath(row: keywords.firstIndex(of: keyword) ?? 0, section: 0))
        }
        present(alert, animated: true)
    }

    private func presentKeywordEditor(keyword: SpecialFollowKeyword?) {
        let alert = UIAlertController(
            title: keyword == nil ? "添加关键词" : "编辑关键词",
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "关键词"
            textField.text = keyword?.keyword
            textField.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let nextKeyword = alert?.textFields?.first?.text ?? ""
            let nextColorHex = keyword?.colorHex ?? SpecialFollowKeyword.defaultColorHex
            do {
                try store.save(keyword: nextKeyword, colorHex: nextColorHex)
                if let keyword, SpecialFollowKeyword.normalizedKeyword(keyword.keyword) != SpecialFollowKeyword.normalizedKeyword(nextKeyword) {
                    store.delete(keyword: keyword.keyword)
                }
                reloadKeywords()
            } catch {
                showAlert(title: "保存失败", message: "请输入关键词。")
            }
        })
        present(alert, animated: true)
    }

    private func presentPresetColorPicker(for keyword: SpecialFollowKeyword) {
        let alert = UIAlertController(title: "选择颜色", message: nil, preferredStyle: .actionSheet)
        for presetColor in SpecialFollowKeywordPresetColor.colors {
            let action = UIAlertAction(
                title: "\(presetColor.name) \(presetColor.colorHex)",
                style: .default
            ) { [weak self] _ in
                guard let self else { return }
                do {
                    try store.save(keyword: keyword.keyword, colorHex: presetColor.colorHex)
                    reloadKeywords()
                } catch {
                    showAlert(title: "保存失败", message: "颜色无法保存。")
                }
            }
            action.setValue(colorSwatchImage(colorHex: presetColor.colorHex), forKey: "image")
            alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = tableView.rectForRow(at: IndexPath(row: keywords.firstIndex(of: keyword) ?? 0, section: 0))
        }
        present(alert, animated: true)
    }

    private func presentImportPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentExportSheet() {
        do {
            let data = try store.exportJSONData()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("special-follow-keywords.json")
            try data.write(to: url, options: .atomic)
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = activity.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.safeAreaInsets.top, width: 1, height: 1)
            }
            present(activity, animated: true)
        } catch {
            showAlert(title: "导出失败", message: error.localizedDescription)
        }
    }

    private func importKeywords(from url: URL) {
        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try store.importJSONData(data)
            reloadKeywords()
            showAlert(title: "导入完成", message: "同名关键词已覆盖。")
        } catch {
            showAlert(title: "导入失败", message: "JSON 格式不符合要求。")
        }
    }

    private func colorSwatchImage(colorHex: String) -> UIImage? {
        guard let color = UIColor(hex: colorHex) else { return nil }
        let size = CGSize(width: 24, height: 24)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            color.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 6).fill()
            UIColor.separator.setStroke()
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 6)
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

extension SpecialFollowKeywordsViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        importKeywords(from: url)
    }
}
