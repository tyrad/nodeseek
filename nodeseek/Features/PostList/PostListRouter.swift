//
//  PostListRouter.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit

class PostListRouter: PostListRouterProtocol {
    
    // MARK: - Properties
    weak var viewController: UIViewController?
    
    // MARK: - Static Methods
    static func createModule() -> UIViewController {
        let router = PostListRouter()
        let interactor = PostListInteractor()
        let presenter = PostListPresenter(
            interactor: interactor,
            router: router,
            visitedStore: VisitedPostStore.shared
        )
        
        interactor.presenter = presenter
        
        let view = PostListViewController(presenter: presenter)
        
        presenter.setView(view)
        router.viewController = view
        
        return view
    }
    
    // MARK: - Navigation
    func navigateToPostDetail(post: PostSummary) {
        navigateToPostDetail(post: post, page: 1)
    }

    func navigateToPostDetail(post: PostSummary, page: Int) {
        let detailViewController = PostDetailRouter.createModule(post: post, page: page)
        viewController?.navigationController?.pushViewController(detailViewController, animated: true)
    }

    func navigateToLogin(onClose: @escaping @MainActor () -> Void) {
        let loginViewController = LoginWebViewController(onClose: onClose)
        if let navigationController = viewController?.navigationController {
            navigationController.pushViewController(loginViewController, animated: true)
            return
        }

        let navigationWrapper = UINavigationController(rootViewController: loginViewController)
        viewController?.present(navigationWrapper, animated: true)
    }

    func navigateToRecentVisitedPosts(visitedStore: VisitedPostStoreProtocol) {
        let recentViewController = RecentVisitedPostsViewController(visitedStore: visitedStore)
        recentViewController.onSelectRecord = { [weak self, weak recentViewController] record in
            let post = Self.postSummary(from: record)
            let page = Self.page(from: record.url)
            let detailViewController = PostDetailRouter.createModule(post: post, page: page)
            if let navigationController = recentViewController?.navigationController {
                navigationController.pushViewController(detailViewController, animated: true)
                return
            }
            self?.viewController?.navigationController?.pushViewController(detailViewController, animated: true)
        }

        if let navigationController = viewController?.navigationController {
            navigationController.pushViewController(recentViewController, animated: true)
            return
        }

        let navigationWrapper = UINavigationController(rootViewController: recentViewController)
        viewController?.present(navigationWrapper, animated: true)
    }

    private static func postSummary(from record: VisitedPostRecord) -> PostSummary {
        PostSummary(
            id: record.postID,
            title: record.title,
            url: record.url,
            authorName: "最近浏览",
            nodeName: nil,
            replyCount: 0,
            lastActivityText: nil,
            avatarURL: record.avatarURL
        )
    }

    private static func page(from url: URL) -> Int {
        let components = url.lastPathComponent.split(separator: "-")
        guard components.count >= 3,
              components.first == "post",
              let page = Int(components[2]) else {
            return 1
        }
        return max(page, 1)
    }

}

final class RecentVisitedPostsViewController: UITableViewController {
    var onSelectRecord: ((VisitedPostRecord) -> Void)?

    private let visitedStore: VisitedPostStoreProtocol
    private var records: [VisitedPostRecord] = []
    private var hasMoreRecords = true
    private let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter
    }()

    init(visitedStore: VisitedPostStoreProtocol) {
        self.visitedStore = visitedStore
        super.init(style: .plain)
        title = "最近浏览"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        tableView.backgroundColor = .systemBackground
        tableView.register(RecentVisitedPostCell.self, forCellReuseIdentifier: Self.cellIdentifier)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: self,
            action: #selector(clearButtonTapped)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "清扫浏览记录"
        loadNextPageIfNeeded()
        renderEmptyStateIfNeeded()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        records.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath) as? RecentVisitedPostCell
            ?? RecentVisitedPostCell(style: .default, reuseIdentifier: Self.cellIdentifier)
        let record = records[indexPath.row]
        cell.configure(
            record: record,
            visitedText: relativeDateFormatter.localizedString(for: record.visitedAt, relativeTo: Date())
        )
        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        guard indexPath.row >= records.count - 4 else { return }
        loadNextPageIfNeeded()
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard records.indices.contains(indexPath.row) else { return }
        onSelectRecord?(records[indexPath.row])
    }

    @objc private func clearButtonTapped() {
        let alert = UIAlertController(
            title: "清除浏览记录？",
            message: "这会删除所有最近浏览记录，此操作无法撤销。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { [weak self] _ in
            self?.clearAllRecords()
        })
        present(alert, animated: true)
    }

    private func clearAllRecords() {
        visitedStore.clearAll()
        records.removeAll()
        hasMoreRecords = false
        tableView.reloadData()
        renderEmptyStateIfNeeded()
    }

    private func loadNextPageIfNeeded() {
        guard hasMoreRecords else { return }
        let nextRecords = visitedStore.recentRecords(offset: records.count, limit: Self.pageSize)
        guard !nextRecords.isEmpty else {
            hasMoreRecords = false
            return
        }

        let startIndex = records.count
        records.append(contentsOf: nextRecords)
        hasMoreRecords = nextRecords.count == Self.pageSize

        guard startIndex > 0 else {
            tableView.reloadData()
            return
        }

        let indexPaths = (startIndex..<records.count).map { IndexPath(row: $0, section: 0) }
        tableView.insertRows(at: indexPaths, with: .automatic)
    }

    private func renderEmptyStateIfNeeded() {
        guard records.isEmpty else {
            tableView.backgroundView = nil
            navigationItem.rightBarButtonItem?.isEnabled = true
            return
        }

        let label = UILabel()
        label.text = "暂无最近浏览"
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.accessibilityIdentifier = "recent-visited-posts-empty-label"
        tableView.backgroundView = label
        navigationItem.rightBarButtonItem?.isEnabled = false
    }

    private static let pageSize = 30
    private static let cellIdentifier = "RecentVisitedPostCell"
}

private final class RecentVisitedPostCell: UITableViewCell {
    private enum Layout {
        static let avatarSize: CGFloat = 44
        static let horizontalInset: CGFloat = 16
        static let verticalInset: CGFloat = 10
    }

    private let avatarLoader = AvatarImageLoader.shared
    private var representedPostID: String?

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .secondarySystemBackground
        imageView.tintColor = .tertiaryLabel
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 10
        imageView.image = UIImage(systemName: "person.crop.square.fill")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let visitedLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        selectionStyle = .default
        contentView.addSubview(avatarImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(visitedLabel)

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Layout.horizontalInset),
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Layout.verticalInset),
            avatarImageView.widthAnchor.constraint(equalToConstant: Layout.avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: Layout.avatarSize),
            avatarImageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -Layout.verticalInset),

            titleLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Layout.verticalInset),

            visitedLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            visitedLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            visitedLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            visitedLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Layout.verticalInset)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if representedPostID != nil {
            avatarLoader.cancel(on: avatarImageView)
            self.representedPostID = nil
        }
        avatarImageView.image = UIImage(systemName: "person.crop.square.fill")
        titleLabel.text = nil
        visitedLabel.text = nil
    }

    func configure(record: VisitedPostRecord, visitedText: String) {
        representedPostID = record.postID
        titleLabel.text = record.title
        visitedLabel.text = visitedText
        avatarLoader.loadAvatar(into: avatarImageView, postID: record.postID, avatarURL: record.avatarURL)
    }
}
