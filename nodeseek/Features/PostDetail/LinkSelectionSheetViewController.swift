//
//  LinkSelectionSheetViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/6/2.
//

import UIKit

final class LinkSelectionSheetViewController: UITableViewController {
    private enum Layout {
        static let headerHorizontalInset: CGFloat = 20
        static let headerVerticalInset: CGFloat = 16
        static let titleSpacing: CGFloat = 4
        static let estimatedHeaderHeight: CGFloat = 74
    }

    private let candidates: [DetailLinkCandidate]
    private let onSelect: (URL) -> Void

    init(
        candidates: [DetailLinkCandidate],
        onSelect: @escaping (URL) -> Void
    ) {
        self.candidates = candidates
        self.onSelect = onSelect
        super.init(style: .plain)
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
        tableView.backgroundColor = .systemBackground
        tableView.separatorColor = .separator
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "LinkCandidateCell")
        tableView.tableHeaderView = makeHeaderView()
        tableView.tableFooterView = UIView()
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        candidates.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LinkCandidateCell", for: indexPath)
        let candidate = candidates[indexPath.row]
        var configuration = UIListContentConfiguration.subtitleCell()
        configuration.text = candidate.title
        configuration.secondaryText = candidate.subtitle
        configuration.textProperties.font = .preferredFont(forTextStyle: .body)
        configuration.textProperties.color = .label
        configuration.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
        configuration.secondaryTextProperties.color = .secondaryLabel
        configuration.secondaryTextProperties.numberOfLines = 2
        configuration.image = UIImage(systemName: "link")
        configuration.imageProperties.tintColor = NodeSeekLinkStyle.color
        cell.contentConfiguration = configuration
        cell.accessoryType = .disclosureIndicator
        cell.backgroundColor = .systemBackground
        cell.selectionStyle = .default
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let url = candidates[indexPath.row].url
        dismiss(animated: true) { [onSelect] in
            onSelect(url)
        }
    }

    private func makeHeaderView() -> UIView {
        let container = UIView()
        container.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = "选择链接"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = UILabel()
        subtitleLabel.text = "签名档里有多个可点击链接"
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(titleLabel)
        container.addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: Layout.headerVerticalInset),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.headerHorizontalInset),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Layout.headerHorizontalInset),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Layout.titleSpacing),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Layout.headerVerticalInset)
        ])
        container.frame = CGRect(
            x: 0,
            y: 0,
            width: tableView.bounds.width,
            height: Layout.estimatedHeaderHeight
        )
        return container
    }
}
