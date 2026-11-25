import UIKit

/// 楼层「吃瓜」层叠回复面板：以选中的评论为根，按父子分支缩进展示后续回复，纯 Markdown 排版。
@MainActor
final class ThreadedRepliesSheetViewController: UIViewController, UICollectionViewDelegateFlowLayout, UIAdaptivePresentationControllerDelegate {
    private enum Row: Equatable {
        case ancestor(ThreadedAncestorNode)
        case root(Comment, floor: Int, parentFloor: Int?, connectsFromTop: Bool, hasAncestors: Bool, hasChildren: Bool)
        case reply(ThreadedReplyNode)
        case empty(rootFloor: Int)

        var key: String {
            switch self {
            case .ancestor(let node):
                return node.stableID
            case .root(let comment, let floor, _, _, _, _):
                return "root-\(floor)-\(comment.id)"
            case .reply(let node):
                return node.stableID
            case .empty(let floor):
                return "empty-\(floor)"
            }
        }
    }

    private let rootComment: Comment
    private let coordinator: ThreadedReplyCoordinator
    private let renderer: DetailFloorRenderer
    private let onLink: (URL) -> Void
    private let onPhotosOverride: (([URL], Int) -> Void)?
    private let onAuthorTapped: (URL) -> Void
    private let onRequireLogin: () -> Void
    private let imageSize: (URL) -> CGSize?
    private let onImageSize: (URL, CGSize) -> Void
    private var photoBrowserPresenter: DetailPhotoBrowserPresenter?

    private var subscriptionID: UUID?
    private(set) var currentSnapshot: ThreadedReplyPanelSnapshot?
    private var rows: [Row] = []
    private var keys: [String] = []
    private var heights: [String: CGFloat] = [:]
    private var renderGeneration = 0
    private var previousAppearance: DetailTextAppearance?

    private let headerView = UIView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let headerSeparator = UIView()

    private let flow = UICollectionViewFlowLayout()
    private(set) lazy var collectionView: UICollectionView = {
        let view = UICollectionView(frame: .zero, collectionViewLayout: flow)
        view.backgroundColor = .systemBackground
        view.alwaysBounceVertical = true
        view.accessibilityIdentifier = "threaded-replies-collection"
        view.delegate = self
        view.register(ThreadedReplyCell.self, forCellWithReuseIdentifier: "reply")
        view.register(ThreadedReplyEmptyCell.self, forCellWithReuseIdentifier: "empty")
        return view
    }()

    private lazy var dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collectionView) { [weak self] collection, indexPath, key in
        self?.makeCell(in: collection, at: indexPath, key: key)
    }

    private let statusBar = UIView()
    private let statusSeparator = UIView()
    private let statusStack = UIStackView()
    private let statusSpinner = UIActivityIndicatorView(style: .medium)
    private let statusLabel = UILabel()
    private let statusActionButton = UIButton(type: .system)

    init(
        rootComment: Comment,
        coordinator: ThreadedReplyCoordinator,
        renderer: DetailFloorRenderer = DetailFloorRenderer(),
        onLink: @escaping (URL) -> Void = { _ in },
        onPhotos: (([URL], Int) -> Void)? = nil,
        onAuthorTapped: @escaping (URL) -> Void = { _ in },
        onRequireLogin: @escaping () -> Void = {},
        imageSize: @escaping (URL) -> CGSize? = { _ in nil },
        onImageSize: @escaping (URL, CGSize) -> Void = { _, _ in }
    ) {
        self.rootComment = rootComment
        self.coordinator = coordinator
        self.renderer = renderer
        self.onLink = onLink
        self.onPhotosOverride = onPhotos
        self.onAuthorTapped = onAuthorTapped
        self.onRequireLogin = onRequireLogin
        self.imageSize = imageSize
        self.onImageSize = onImageSize
        super.init(nibName: nil, bundle: nil)
    }

    private func presentPhotos(imageURLs: [URL], initialIndex: Int) {
        if let onPhotosOverride {
            onPhotosOverride(imageURLs, initialIndex)
            return
        }
        guard !imageURLs.isEmpty else { return }
        let presenter = DetailPhotoBrowserPresenter(imageURLs: imageURLs)
        photoBrowserPresenter = presenter
        presenter.present(from: self, initialIndex: initialIndex)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        presentationController?.delegate = self
        configureHierarchy()
        registerTraitUpdates()
        startSubscription()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        refreshAppearanceIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            stopSubscription()
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        stopSubscription()
    }

    // MARK: - 布局与外观

    private func configureHierarchy() {
        flow.minimumLineSpacing = 0
        flow.minimumInteritemSpacing = 0

        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = .systemBackground

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = DetailListStrings.text("thread-replies")
        titleLabel.font = UIFontMetrics(forTextStyle: .title3).scaledFont(
            for: .systemFont(ofSize: 20, weight: .bold),
            compatibleWith: traitCollection
        )
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.accessibilityTraits = .header
        titleLabel.accessibilityIdentifier = "threaded-replies-title"

        var closeConfig = UIButton.Configuration.filled()
        closeConfig.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        )
        closeConfig.baseBackgroundColor = .secondarySystemFill
        closeConfig.baseForegroundColor = .secondaryLabel
        closeConfig.cornerStyle = .capsule
        closeConfig.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 7, bottom: 7, trailing: 7)
        closeButton.configuration = closeConfig
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.accessibilityLabel = DetailListStrings.text("close")
        closeButton.accessibilityIdentifier = "threaded-replies-close-button"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        headerSeparator.translatesAutoresizingMaskIntoConstraints = false
        headerSeparator.backgroundColor = .separator

        headerView.addSubview(titleLabel)
        headerView.addSubview(closeButton)
        headerView.addSubview(headerSeparator)

        collectionView.translatesAutoresizingMaskIntoConstraints = false

        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.backgroundColor = .systemBackground
        statusBar.accessibilityIdentifier = "threaded-replies-status-bar"

        statusSeparator.translatesAutoresizingMaskIntoConstraints = false
        statusSeparator.backgroundColor = .separator

        statusSpinner.hidesWhenStopped = true
        statusSpinner.color = .secondaryLabel

        statusLabel.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: .systemFont(ofSize: 13, weight: .regular),
            compatibleWith: traitCollection
        )
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .natural
        statusLabel.accessibilityIdentifier = "threaded-replies-status-label"

        var actionConfig = UIButton.Configuration.tinted()
        actionConfig.cornerStyle = .capsule
        actionConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        statusActionButton.configuration = actionConfig
        statusActionButton.titleLabel?.adjustsFontForContentSizeCategory = true
        statusActionButton.setContentHuggingPriority(.required, for: .horizontal)
        statusActionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusActionButton.isHidden = true
        statusActionButton.accessibilityIdentifier = "threaded-replies-action-button"
        statusActionButton.addTarget(self, action: #selector(statusActionTapped), for: .touchUpInside)

        statusStack.axis = .horizontal
        statusStack.alignment = .center
        statusStack.spacing = 8
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        statusStack.addArrangedSubview(statusSpinner)
        statusStack.addArrangedSubview(statusLabel)
        statusStack.addArrangedSubview(statusActionButton)

        statusBar.addSubview(statusSeparator)
        statusBar.addSubview(statusStack)

        view.addSubview(headerView)
        view.addSubview(collectionView)
        view.addSubview(statusBar)

        let hairline = 1 / max(1, traitCollection.displayScale)
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            titleLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -12),
            titleLabel.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -12),

            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 32),
            closeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),

            headerSeparator.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            headerSeparator.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            headerSeparator.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            headerSeparator.heightAnchor.constraint(equalToConstant: hairline),

            collectionView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            statusSeparator.topAnchor.constraint(equalTo: statusBar.topAnchor),
            statusSeparator.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor),
            statusSeparator.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor),
            statusSeparator.heightAnchor.constraint(equalToConstant: hairline),

            statusStack.topAnchor.constraint(equalTo: statusBar.topAnchor, constant: 10),
            statusStack.leadingAnchor.constraint(greaterThanOrEqualTo: statusBar.leadingAnchor, constant: 16),
            statusStack.trailingAnchor.constraint(lessThanOrEqualTo: statusBar.trailingAnchor, constant: -16),
            statusStack.centerXAnchor.constraint(equalTo: statusBar.centerXAnchor),
            statusStack.bottomAnchor.constraint(equalTo: statusBar.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        ])
    }

    private func registerTraitUpdates() {
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
                self.refreshAppearanceIfNeeded()
            }
        }
    }

    @available(iOS, introduced: 2.0, deprecated: 17.0)
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 17.0, *) { return }
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle
            || previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            refreshAppearanceIfNeeded()
        }
    }

    private var currentAppearance: DetailTextAppearance {
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: AppTypography.commentBodyFont(),
            compatibleWith: traitCollection
        )
        return DetailTextAppearance(
            width: max(1, collectionView.bounds.width),
            pointSize: font.pointSize,
            scale: traitCollection.displayScale,
            dark: traitCollection.userInterfaceStyle == .dark
        )
    }

    private func refreshAppearanceIfNeeded() {
        guard collectionView.bounds.width > 0 else { return }
        let appearance = currentAppearance
        guard previousAppearance != appearance else { return }
        previousAppearance = appearance
        heights.removeAll()
        if let snapshot = currentSnapshot {
            apply(snapshot, reconfigureExisting: true)
        }
    }

    // MARK: - 订阅与状态渲染

    private func startSubscription() {
        subscriptionID = coordinator.startViewing(rootComment: rootComment) { [weak self] snapshot in
            self?.apply(snapshot, reconfigureExisting: false)
        }
    }

    func stopSubscription() {
        guard let subscriptionID else { return }
        self.subscriptionID = nil
        coordinator.stopViewing(subscriptionID: subscriptionID)
    }

    @objc private func closeTapped() {
        stopSubscription()
        dismiss(animated: true)
    }

    @objc private func statusActionTapped() {
        guard let currentSnapshot, let subscriptionID else { return }
        switch currentSnapshot.state {
        case .pausedAtBatchLimit:
            coordinator.continueScanning(subscriptionID: subscriptionID)
        case .failed(_, let requiresLogin):
            if requiresLogin {
                stopSubscription()
                onRequireLogin()
            } else {
                coordinator.retry(subscriptionID: subscriptionID)
            }
        case .idle, .scanning, .completed:
            break
        }
    }

    /// 供测试或快照变化时更新列表，保持用户当前可见楼层的屏内位置不跳动。
    func apply(_ snapshot: ThreadedReplyPanelSnapshot, reconfigureExisting: Bool = false) {
        let previousSnapshot = currentSnapshot
        currentSnapshot = snapshot

        var nextRows: [Row] = snapshot.ancestors.map(Row.ancestor)
        nextRows.append(
            .root(
                snapshot.rootComment,
                floor: snapshot.rootFloor,
                parentFloor: snapshot.rootDisplayedParentFloor,
                connectsFromTop: snapshot.rootConnectsFromTop,
                hasAncestors: !snapshot.ancestors.isEmpty,
                hasChildren: !snapshot.nodes.isEmpty
            )
        )
        if snapshot.nodes.isEmpty, snapshot.state == .completed {
            nextRows.append(.empty(rootFloor: snapshot.rootFloor))
        } else {
            nextRows.append(contentsOf: snapshot.nodes.map(Row.reply))
        }

        let nextKeys = nextRows.map(\.key)
        let changedKeys: Set<String>
        if reconfigureExisting {
            changedKeys = Set(nextKeys)
        } else {
            let previousByKey = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0) })
            changedKeys = Set(nextRows.compactMap { row -> String? in
                guard let old = previousByKey[row.key], old != row else { return nil }
                return row.key
            })
        }

        let scrollAnchor = captureScrollAnchor()

        rows = nextRows
        keys = nextKeys
        let validKeys = Set(nextKeys)
        heights = heights.filter { validKeys.contains($0.key) }

        var diff = NSDiffableDataSourceSnapshot<Int, String>()
        diff.appendSections([0])
        diff.appendItems(nextKeys)
        let existingKeys = Set(dataSource.snapshot().itemIdentifiers)
        let toReconfigure = nextKeys.filter { existingKeys.contains($0) && changedKeys.contains($0) }
        if !toReconfigure.isEmpty {
            diff.reconfigureItems(toReconfigure)
        }

        dataSource.apply(diff, animatingDifferences: false)
        collectionView.layoutIfNeeded()

        if let scrollAnchor, previousSnapshot != nil {
            restoreScrollAnchor(scrollAnchor)
        }

        updateStatusBar(for: snapshot)
    }

    private struct ScrollAnchor {
        let key: String
        let relativeTopOffset: CGFloat
    }

    private func captureScrollAnchor() -> ScrollAnchor? {
        guard collectionView.bounds.height > 0, collectionView.contentOffset.y > 0.5 else { return nil }
        let visibleTop = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
        let visiblePaths = collectionView.indexPathsForVisibleItems.sorted { $0.item < $1.item }
        for path in visiblePaths {
            guard keys.indices.contains(path.item),
                  let attrs = collectionView.layoutAttributesForItem(at: path),
                  attrs.frame.maxY > visibleTop else { continue }
            return ScrollAnchor(
                key: keys[path.item],
                relativeTopOffset: attrs.frame.minY - collectionView.contentOffset.y
            )
        }
        return nil
    }

    private func restoreScrollAnchor(_ anchor: ScrollAnchor) {
        guard let newPath = dataSource.indexPath(for: anchor.key),
              let attrs = collectionView.layoutAttributesForItem(at: newPath) else { return }
        let targetY = attrs.frame.minY - anchor.relativeTopOffset
        let minOffsetY = -collectionView.adjustedContentInset.top
        let maxOffsetY = max(
            minOffsetY,
            collectionView.contentSize.height - collectionView.bounds.height + collectionView.adjustedContentInset.bottom
        )
        let clampedY = min(max(targetY, minOffsetY), maxOffsetY)
        if abs(collectionView.contentOffset.y - clampedY) >= 0.5 {
            collectionView.contentOffset.y = clampedY
        }
    }

    private func updateStatusBar(for snapshot: ThreadedReplyPanelSnapshot) {
        let count = snapshot.replyCount
        switch snapshot.state {
        case .idle:
            statusSpinner.stopAnimating()
            statusLabel.text = nil
            statusActionButton.isHidden = true

        case .scanning(let currentPage, let totalPages):
            statusSpinner.startAnimating()
            if let totalPages, totalPages >= currentPage {
                statusLabel.text = String(
                    format: DetailListStrings.text("thread-scanning-with-total"),
                    count, currentPage, totalPages
                )
            } else {
                statusLabel.text = String(
                    format: DetailListStrings.text("thread-scanning-without-total"),
                    count, currentPage
                )
            }
            statusActionButton.isHidden = true

        case .pausedAtBatchLimit(let scannedUpToPage, let totalPages):
            statusSpinner.stopAnimating()
            if let totalPages, totalPages >= scannedUpToPage {
                statusLabel.text = String(
                    format: DetailListStrings.text("thread-paused-with-total"),
                    count, scannedUpToPage, totalPages
                )
            } else {
                statusLabel.text = String(
                    format: DetailListStrings.text("thread-paused-without-total"),
                    count, scannedUpToPage
                )
            }
            statusActionButton.configuration?.title = DetailListStrings.text("thread-continue")
            statusActionButton.isHidden = false

        case .failed(let message, let requiresLogin):
            statusSpinner.stopAnimating()
            statusLabel.text = String(
                format: DetailListStrings.text("thread-failed-partial"),
                count, message
            )
            statusActionButton.configuration?.title = DetailListStrings.text(requiresLogin ? "thread-login" : "thread-retry")
            statusActionButton.isHidden = false

        case .completed:
            statusSpinner.stopAnimating()
            if count == 0 {
                statusLabel.text = DetailListStrings.text("thread-completed-empty")
            } else {
                statusLabel.text = Self.completedCountText(count)
            }
            statusActionButton.isHidden = true
        }
    }

    private static func completedCountText(_ count: Int) -> String {
        if count == 1 {
            let singularKey = "thread-completed-count-one"
            let singular = DetailListStrings.text(singularKey)
            if singular != singularKey {
                return singular
            }
        }
        return String(format: DetailListStrings.text("thread-completed-count"), count)
    }

    // MARK: - Cell 配置与高度

    private func makeCell(in list: UICollectionView, at path: IndexPath, key: String) -> UICollectionViewCell {
        guard rows.indices.contains(path.item) else {
            return list.dequeueReusableCell(withReuseIdentifier: "empty", for: path)
        }
        let row = rows[path.item]
        switch row {
        case .empty(let rootFloor):
            let cell = list.dequeueReusableCell(withReuseIdentifier: "empty", for: path) as! ThreadedReplyEmptyCell
            cell.configure(rootFloor: rootFloor)
            return cell

        case .ancestor(let ancestor):
            let cell = list.dequeueReusableCell(withReuseIdentifier: "reply", for: path) as! ThreadedReplyCell
            configureReplyCell(
                cell,
                key: key,
                comment: ancestor.comment,
                floor: ancestor.floor,
                parentFloor: ancestor.parentFloorInChain,
                visualDepth: 0,
                showsParentBadge: false,
                ancestorContinuations: [],
                isLastSibling: true,
                hasChildren: ancestor.connectsToNext,
                connectsFromTop: ancestor.connectsFromPrevious,
                isFocusedHighlight: false
            )
            return cell

        case .root(let comment, let floor, let parentFloor, let connectsFromTop, let hasAncestors, let hasChildren):
            let cell = list.dequeueReusableCell(withReuseIdentifier: "reply", for: path) as! ThreadedReplyCell
            configureReplyCell(
                cell,
                key: key,
                comment: comment,
                floor: floor,
                parentFloor: parentFloor,
                visualDepth: 0,
                showsParentBadge: false,
                ancestorContinuations: [],
                isLastSibling: true,
                hasChildren: hasChildren,
                connectsFromTop: connectsFromTop,
                isFocusedHighlight: hasAncestors
            )
            return cell

        case .reply(let node):
            let cell = list.dequeueReusableCell(withReuseIdentifier: "reply", for: path) as! ThreadedReplyCell
            configureReplyCell(
                cell,
                key: key,
                comment: node.comment,
                floor: node.floor,
                parentFloor: node.parentFloor,
                visualDepth: node.visualDepth,
                showsParentBadge: node.showsParentBadge,
                ancestorContinuations: node.ancestorContinuations,
                isLastSibling: node.isLastSibling,
                hasChildren: node.hasChildren,
                connectsFromTop: false,
                isFocusedHighlight: false
            )
            return cell
        }
    }

    private func configureReplyCell(
        _ cell: ThreadedReplyCell,
        key: String,
        comment: Comment,
        floor: Int,
        parentFloor: Int?,
        visualDepth: Int,
        showsParentBadge: Bool,
        ancestorContinuations: [Bool],
        isLastSibling: Bool,
        hasChildren: Bool,
        connectsFromTop: Bool,
        isFocusedHighlight: Bool
    ) {
        renderGeneration += 1
        let traits = currentAppearance
        let cellWidth = max(1, collectionView.bounds.width)
        let bodyWidth = ThreadedReplyCell.bodyWidth(forCellWidth: cellWidth, visualDepth: visualDepth)

        let displayMarkdown: String?
        if let raw = comment.markdown?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            displayMarkdown = CommentReplyRelationParser.displayMarkdown(
                from: raw,
                parentFloor: parentFloor,
                postID: coordinator.postID,
                currentFloor: floor,
                baseURL: coordinator.baseURL
            )
        } else {
            displayMarkdown = nil
        }

        let bodyAppearance = DetailTextAppearance(
            width: bodyWidth,
            pointSize: traits.pointSize,
            scale: traits.scale,
            dark: traits.dark
        )
        let request = DetailFloorRequest(
            id: key,
            version: renderGeneration,
            source: DetailFloorSource(html: "", visibleMarkdown: displayMarkdown),
            appearance: bodyAppearance,
            baseURL: coordinator.baseURL
        )

        cell.configure(
            request: request,
            comment: comment,
            floor: floor,
            parentFloor: parentFloor,
            visualDepth: visualDepth,
            showsParentBadge: showsParentBadge,
            ancestorContinuations: ancestorContinuations,
            isLastSibling: isLastSibling,
            hasChildren: hasChildren,
            connectsFromTop: connectsFromTop,
            isFocusedHighlight: isFocusedHighlight,
            renderer: renderer,
            viewport: collectionView,
            onAuthorTapped: onAuthorTapped,
            onLink: onLink,
            onPhotos: { [weak self] urls, index in
                self?.presentPhotos(imageURLs: urls, initialIndex: index)
            },
            imageSize: imageSize,
            onImageSize: onImageSize,
            onSizeChange: { [weak self, weak cell] in
                DispatchQueue.main.async { [weak self, weak cell] in
                    guard let self, let cell, cell.boundRequest == request else { return }
                    self.updateCellHeight(cell, key: key)
                }
            }
        )
    }

    private func updateCellHeight(_ cell: ThreadedReplyCell, key: String) {
        guard let indexPath = dataSource.indexPath(for: key), collectionView.bounds.width > 0 else { return }
        let measured = cell.measuredHeight(width: collectionView.bounds.width)
        let old = heights[key] ?? estimatedHeight(for: key)
        guard abs(old - measured) >= 0.5 else { return }
        heights[key] = measured

        let context = UICollectionViewFlowLayoutInvalidationContext()
        context.invalidateFlowLayoutDelegateMetrics = true
        let visibleTop = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
        if visibleTop > 0,
           collectionView.indexPath(for: cell) == indexPath,
           cell.frame.height > 0,
           cell.frame.maxY <= visibleTop {
            context.contentOffsetAdjustment.y = measured - old
        }
        flow.invalidateLayout(with: context)
    }

    private func estimatedHeight(for key: String) -> CGFloat {
        key.hasPrefix("empty-") ? 120 : 88
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let width = max(1, collectionView.bounds.width)
        let key = keys.indices.contains(indexPath.item) ? keys[indexPath.item] : ""
        return CGSize(width: width, height: heights[key] ?? estimatedHeight(for: key))
    }
}

// MARK: - 层叠楼层 Cell

@MainActor
private final class ThreadedReplyCell: UICollectionViewCell {
    enum Metrics {
        static let outerInset: CGFloat = 16
        static let avatarSize: CGFloat = 32
        static let avatarSpacing: CGFloat = 10
        static let indentStep: CGFloat = 24
        static let topPadding: CGFloat = 12
        static let bottomPadding: CGFloat = 12
        static let stemOffsetFromAvatarLeading: CGFloat = 10
    }

    static func bodyWidth(forCellWidth cellWidth: CGFloat, visualDepth: Int) -> CGFloat {
        let clampedDepth = max(0, min(visualDepth, ThreadedReplyNode.maxVisualDepth))
        let leading = Metrics.outerInset
            + CGFloat(clampedDepth) * Metrics.indentStep
            + Metrics.avatarSize
            + Metrics.avatarSpacing
        return max(1, cellWidth - leading - Metrics.outerInset)
    }

    private let branchGuide = ThreadBranchGuideView()
    private let topHighlightDivider = UIView()
    private let bottomHighlightDivider = UIView()
    private let avatarView = UIImageView()
    private let contentStack = UIStackView()
    private let headerRow = UIStackView()
    private let authorLabel = UILabel()
    private let posterBadge = UILabel()
    private let floorLabel = UILabel()
    private let parentBadgeLabel = UILabel()
    private let placeholderLabel = UILabel()
    private var bodyStack = DetailBlockStack()

    private var avatarLeadingConstraint: NSLayoutConstraint!
    private var contentLeadingConstraint: NSLayoutConstraint!
    private var authorProfileURL: URL?
    private var onAuthorTapped: ((URL) -> Void)?
    private var renderTask: Task<Void, Never>?
    private(set) var boundRequest: DetailFloorRequest?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .systemBackground

        branchGuide.translatesAutoresizingMaskIntoConstraints = false
        branchGuide.isUserInteractionEnabled = false
        contentView.addSubview(branchGuide)

        topHighlightDivider.translatesAutoresizingMaskIntoConstraints = false
        topHighlightDivider.backgroundColor = .separator
        topHighlightDivider.isHidden = true
        bottomHighlightDivider.translatesAutoresizingMaskIntoConstraints = false
        bottomHighlightDivider.backgroundColor = .separator
        bottomHighlightDivider.isHidden = true
        contentView.addSubview(topHighlightDivider)
        contentView.addSubview(bottomHighlightDivider)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 8
        avatarView.layer.cornerCurve = .continuous
        avatarView.backgroundColor = .secondarySystemBackground
        avatarView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(authorTapped)))
        contentView.addSubview(avatarView)

        authorLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: AppTypography.commentAuthorFont(),
            compatibleWith: traitCollection
        )
        authorLabel.textColor = .label
        authorLabel.adjustsFontForContentSizeCategory = true
        authorLabel.numberOfLines = 1
        authorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        authorLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(authorTapped)))

        posterBadge.text = DetailListStrings.text("poster")
        posterBadge.textColor = .systemOrange
        posterBadge.adjustsFontForContentSizeCategory = true
        posterBadge.setContentHuggingPriority(.required, for: .horizontal)
        posterBadge.setContentCompressionResistancePriority(.required, for: .horizontal)

        floorLabel.textColor = .tertiaryLabel
        floorLabel.adjustsFontForContentSizeCategory = true
        floorLabel.setContentHuggingPriority(.required, for: .horizontal)
        floorLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.spacing = 6
        headerRow.addArrangedSubview(authorLabel)
        headerRow.addArrangedSubview(posterBadge)
        headerRow.addArrangedSubview(UIView())
        headerRow.addArrangedSubview(floorLabel)

        parentBadgeLabel.textColor = .secondaryLabel
        parentBadgeLabel.adjustsFontForContentSizeCategory = true
        parentBadgeLabel.numberOfLines = 1
        parentBadgeLabel.isHidden = true

        placeholderLabel.text = DetailListStrings.text("thread-no-markdown")
        placeholderLabel.textColor = .secondaryLabel
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.numberOfLines = 0
        placeholderLabel.isHidden = true

        bodyStack.axis = .vertical
        bodyStack.spacing = 6

        contentStack.axis = .vertical
        contentStack.spacing = 4
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(headerRow)
        contentStack.addArrangedSubview(parentBadgeLabel)
        contentStack.addArrangedSubview(placeholderLabel)
        contentStack.addArrangedSubview(bodyStack)
        contentView.addSubview(contentStack)

        avatarLeadingConstraint = avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.outerInset)
        contentLeadingConstraint = contentStack.leadingAnchor.constraint(
            equalTo: avatarView.trailingAnchor,
            constant: Metrics.avatarSpacing
        )

        let hairline = 1 / max(1, traitCollection.displayScale)
        NSLayoutConstraint.activate([
            branchGuide.topAnchor.constraint(equalTo: contentView.topAnchor),
            branchGuide.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            branchGuide.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            branchGuide.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            topHighlightDivider.topAnchor.constraint(equalTo: contentView.topAnchor),
            topHighlightDivider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            topHighlightDivider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            topHighlightDivider.heightAnchor.constraint(equalToConstant: hairline),

            bottomHighlightDivider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bottomHighlightDivider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bottomHighlightDivider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottomHighlightDivider.heightAnchor.constraint(equalToConstant: hairline),

            avatarLeadingConstraint,
            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.topPadding),
            avatarView.widthAnchor.constraint(equalToConstant: Metrics.avatarSize),
            avatarView.heightAnchor.constraint(equalToConstant: Metrics.avatarSize),

            contentLeadingConstraint,
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.topPadding),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.outerInset)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        renderTask?.cancel()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        reset()
    }

    private func reset() {
        renderTask?.cancel()
        renderTask = nil
        boundRequest = nil
        AvatarImageLoader.shared.cancel(on: avatarView)
        avatarView.image = nil
        authorProfileURL = nil
        onAuthorTapped = nil
        bodyStack.removeFromSuperview()
        bodyStack = DetailBlockStack()
        bodyStack.axis = .vertical
        bodyStack.spacing = 6
        contentStack.addArrangedSubview(bodyStack)
        placeholderLabel.isHidden = true
        parentBadgeLabel.isHidden = true
        contentView.backgroundColor = .systemBackground
        topHighlightDivider.isHidden = true
        bottomHighlightDivider.isHidden = true
    }

    func configure(
        request: DetailFloorRequest,
        comment: Comment,
        floor: Int,
        parentFloor: Int?,
        visualDepth: Int,
        showsParentBadge: Bool,
        ancestorContinuations: [Bool],
        isLastSibling: Bool,
        hasChildren: Bool,
        connectsFromTop: Bool,
        isFocusedHighlight: Bool,
        renderer: DetailFloorRenderer,
        viewport: UIScrollView,
        onAuthorTapped: @escaping (URL) -> Void,
        onLink: @escaping (URL) -> Void,
        onPhotos: @escaping ([URL], Int) -> Void,
        imageSize: @escaping (URL) -> CGSize?,
        onImageSize: @escaping (URL, CGSize) -> Void,
        onSizeChange: @escaping () -> Void
    ) {
        if boundRequest != nil { reset() }
        boundRequest = request
        accessibilityIdentifier = request.id

        let clampedDepth = max(0, min(visualDepth, ThreadedReplyNode.maxVisualDepth))
        avatarLeadingConstraint.constant = Metrics.outerInset + CGFloat(clampedDepth) * Metrics.indentStep

        let metrics = UIFontMetrics(forTextStyle: .subheadline)
        let smallFont = metrics.scaledFont(for: AppTypography.commentMetadataFont(), compatibleWith: traitCollection)
        let badgeFont = metrics.scaledFont(for: AppTypography.commentBadgeFont(), compatibleWith: traitCollection)
        let authorFont = metrics.scaledFont(for: AppTypography.commentAuthorFont(), compatibleWith: traitCollection)

        authorLabel.font = authorFont
        authorLabel.text = comment.authorName
        posterBadge.font = badgeFont
        posterBadge.isHidden = !comment.isPoster
        floorLabel.font = smallFont
        floorLabel.text = "#\(floor)"
        floorLabel.accessibilityIdentifier = "threaded-reply-floor-\(floor)"

        if showsParentBadge, let parentFloor {
            parentBadgeLabel.font = smallFont
            parentBadgeLabel.text = String(format: DetailListStrings.text("thread-replying-to"), parentFloor)
            parentBadgeLabel.accessibilityIdentifier = "threaded-reply-parent-badge-\(floor)"
            parentBadgeLabel.isHidden = false
        } else {
            parentBadgeLabel.isHidden = true
        }

        authorProfileURL = comment.authorProfileURL
        self.onAuthorTapped = onAuthorTapped
        avatarView.isUserInteractionEnabled = comment.authorProfileURL != nil
        authorLabel.isUserInteractionEnabled = comment.authorProfileURL != nil
        ImageLoad.url(comment.avatarURL).toAvatar(requestID: request.id).into(avatarView)

        contentView.backgroundColor = isFocusedHighlight ? .secondarySystemBackground : .systemBackground
        topHighlightDivider.isHidden = !isFocusedHighlight
        bottomHighlightDivider.isHidden = !isFocusedHighlight

        branchGuide.configure(
            visualDepth: clampedDepth,
            ancestorContinuations: ancestorContinuations,
            isLastSibling: isLastSibling,
            hasChildren: hasChildren,
            connectsFromTop: connectsFromTop
        )

        bodyStack.renderer = renderer
        bodyStack.appearance = request.appearance
        bodyStack.viewport = viewport
        bodyStack.onLink = onLink
        bodyStack.onPhotos = onPhotos
        bodyStack.imageSize = imageSize
        bodyStack.onImageSize = onImageSize
        bodyStack.onSizeChange = onSizeChange

        if let markdown = request.source.visibleMarkdown, !markdown.isEmpty {
            placeholderLabel.isHidden = true
            bodyStack.isHidden = false
            renderTask = renderer.startPureMarkdown(request) { [weak self] delivered, layout in
                guard let self, self.boundRequest == delivered else { return }
                self.bodyStack.removeAllBlocks()
                if case .native(let blocks) = layout {
                    self.bodyStack.append(blocks, to: self.bodyStack, width: delivered.appearance.width)
                }
                self.bodyStack.refreshPlayback()
                onSizeChange()
            }
        } else {
            placeholderLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(
                for: AppTypography.commentMetadataFont(),
                compatibleWith: traitCollection
            )
            placeholderLabel.isHidden = false
            bodyStack.isHidden = true
            onSizeChange()
        }
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        let clampedLeading = avatarLeadingConstraint.constant + Metrics.avatarSize + Metrics.avatarSpacing
        let availableWidth = max(1, width - clampedLeading - Metrics.outerInset)
        let target = CGSize(width: availableWidth, height: UIView.layoutFittingCompressedSize.height)
        let measured = contentStack.systemLayoutSizeFitting(
            target,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let minContentHeight = max(measured.height, Metrics.avatarSize)
        return ceil(Metrics.topPadding + minContentHeight + Metrics.bottomPadding)
    }

    @objc private func authorTapped() {
        if let authorProfileURL {
            onAuthorTapped?(authorProfileURL)
        }
    }
}

// MARK: - 树形分支线视图

private final class ThreadBranchGuideView: UIView {
    private var visualDepth = 0
    private var ancestorContinuations: [Bool] = []
    private var isLastSibling = true
    private var hasChildren = false
    private var connectsFromTop = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .redraw
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
                self.setNeedsDisplay()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        visualDepth: Int,
        ancestorContinuations: [Bool],
        isLastSibling: Bool,
        hasChildren: Bool,
        connectsFromTop: Bool
    ) {
        self.visualDepth = visualDepth
        self.ancestorContinuations = ancestorContinuations
        self.isLastSibling = isLastSibling
        self.hasChildren = hasChildren
        self.connectsFromTop = connectsFromTop
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let lineWidth: CGFloat = 1.25
        let cornerRadius: CGFloat = 8
        let strokeColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor

        context.setStrokeColor(strokeColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let avatarTopY = ThreadedReplyCell.Metrics.topPadding
        let avatarCenterY = avatarTopY + ThreadedReplyCell.Metrics.avatarSize / 2
        let avatarBottomY = avatarTopY + ThreadedReplyCell.Metrics.avatarSize

        func stemX(forParentVisualDepth depth: Int) -> CGFloat {
            ThreadedReplyCell.Metrics.outerInset
                + CGFloat(depth) * ThreadedReplyCell.Metrics.indentStep
                + ThreadedReplyCell.Metrics.stemOffsetFromAvatarLeading
        }

        // 0. 上游祖先链或焦点楼顶部承接来自上一层的垂直连线。
        if visualDepth == 0, connectsFromTop {
            let x = stemX(forParentVisualDepth: 0)
            let endY = max(0, avatarTopY - 4)
            if endY > 0 {
                context.move(to: CGPoint(x: x, y: 0))
                context.addLine(to: CGPoint(x: x, y: endY))
                context.strokePath()
            }
        }

        // 1. 祖先层级延续的竖线。
        if visualDepth > 1 {
            for ancestorLevel in 0..<(visualDepth - 1) {
                guard ancestorLevel < ancestorContinuations.count, ancestorContinuations[ancestorLevel] else { continue }
                let x = stemX(forParentVisualDepth: ancestorLevel)
                context.move(to: CGPoint(x: x, y: 0))
                context.addLine(to: CGPoint(x: x, y: bounds.height))
                context.strokePath()
            }
        }

        // 2. 当前节点与直接父级的 L 型分支线。
        if visualDepth >= 1 {
            let parentLevel = visualDepth - 1
            let x = stemX(forParentVisualDepth: parentLevel)
            let avatarLeading = ThreadedReplyCell.Metrics.outerInset + CGFloat(visualDepth) * ThreadedReplyCell.Metrics.indentStep
            let endX = avatarLeading - 5

            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: max(0, avatarCenterY - cornerRadius)))
            path.addQuadCurve(
                to: CGPoint(x: min(endX, x + cornerRadius), y: avatarCenterY),
                control: CGPoint(x: x, y: avatarCenterY)
            )
            path.addLine(to: CGPoint(x: endX, y: avatarCenterY))
            context.addPath(path)
            context.strokePath()

            if !isLastSibling {
                context.move(to: CGPoint(x: x, y: max(0, avatarCenterY - cornerRadius)))
                context.addLine(to: CGPoint(x: x, y: bounds.height))
                context.strokePath()
            }
        }

        // 3. 当前节点向下引出子分支的竖线。
        if hasChildren {
            let childStemParentDepth = min(visualDepth, ThreadedReplyNode.maxVisualDepth - 1)
            let x = stemX(forParentVisualDepth: childStemParentDepth)
            let startY = visualDepth < ThreadedReplyNode.maxVisualDepth ? avatarBottomY + 4 : avatarCenterY
            if startY < bounds.height {
                context.move(to: CGPoint(x: x, y: startY))
                context.addLine(to: CGPoint(x: x, y: bounds.height))
                context.strokePath()
            }
        }
    }
}

// MARK: - 完成空态 Cell

@MainActor
private final class ThreadedReplyEmptyCell: UICollectionViewCell {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .systemBackground
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.accessibilityIdentifier = "threaded-replies-empty-label"
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(rootFloor: Int) {
        label.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: AppTypography.commentMetadataFont(),
            compatibleWith: traitCollection
        )
        label.text = String(format: DetailListStrings.text("thread-empty"), rootFloor)
    }
}
