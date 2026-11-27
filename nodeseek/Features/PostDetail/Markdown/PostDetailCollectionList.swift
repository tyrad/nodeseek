import UIKit

/// 每个展示位置有独立标识：同一条评论可以同时出现在热评及分页列表中。
final class PostDetailCollectionList: NSObject, UICollectionViewDelegateFlowLayout {
    private final class CachedText {
        let source: DetailFloorSource
        let appearance: DetailTextAppearance
        let blocks: [DetailLayoutBlock]
        init(_ request: DetailFloorRequest, _ blocks: [DetailLayoutBlock]) {
            source = request.source
            appearance = request.appearance
            self.blocks = blocks
        }
    }

    private weak var page: PostDetailViewController?
    private lazy var sizingEntryHint = DetailEntryHintCell(frame: .zero)
    private lazy var sizingFilterBanner = DetailAuthorFilterBannerCell(frame: .zero)
    private let flow = UICollectionViewFlowLayout()
    let view: UICollectionView
    private(set) var rows: [PostDetailViewController.DetailRow] = []
    private var keys: [String] = []
    private var heights: [String: CGFloat] = [:]
    private var headerEstimate: CGFloat = 100
    /// 测评标签选中栏，按楼层 key 和楼层内第几个标签组记录。
    private struct TabGroup: Hashable { let floor: String; let ordinal: Int }
    private var tabSelections: [TabGroup: Int] = [:]
    private let cache = NSCache<NSString, CachedText>()
    private var requestedPage: Int?
    private var retryOnNextDrag = false
    private var userScrollInProgress = false
    private var lastOffsetY: CGFloat = 0
    private var queuedRows: [(row: PostDetailViewController.DetailRow, key: String)] = []
    private var refreshQueuedBanner = false
    private var batchCheckScheduled = false
    private var generation = 0
    private var previousAppearance: DetailTextAppearance?
    private weak var highlightedFloor: DetailFloorListCell?
    private var pendingAnchorKey: String?
    private var revealCover: UIView?
    private var revealDeadline: CFTimeInterval = 0
    private var settledChecks = 0
    var renderer = DetailFloorRenderer()
    var headerSource: DetailFloorSource?
    private lazy var data = UICollectionViewDiffableDataSource<Int, String>(collectionView: view) { [weak self] collection, path, key in
        self?.cell(in: collection, at: path, key: key)
    }

    init(page: PostDetailViewController) {
        self.page = page
        flow.minimumLineSpacing = 0
        flow.minimumInteritemSpacing = 0
        flow.footerReferenceSize = CGSize(width: 1, height: 56)
        let collection = DetailCollectionView(frame: .zero, collectionViewLayout: flow)
        view = collection
        super.init()
        // 文字颜色在排版时按外观定好；中途切换外观不会触发页面布局回调，需在这里重排。
        collection.onAppearanceChange = { [weak self] in self?.updateAppearance() }
        view.backgroundColor = .systemBackground
        view.alwaysBounceVertical = true
        view.accessibilityIdentifier = "post-detail-textkit-collection"
        view.delegate = self
        view.register(DetailFloorListCell.self, forCellWithReuseIdentifier: "floor")
        view.register(UICollectionViewListCell.self, forCellWithReuseIdentifier: "notice")
        view.register(DetailReplyPaginationCell.self, forCellWithReuseIdentifier: "reply-pages")
        view.register(DetailEntryHintCell.self, forCellWithReuseIdentifier: "entry")
        view.register(DetailAuthorFilterBannerCell.self, forCellWithReuseIdentifier: "filter")
        view.register(DetailSkeletonListCell.self, forCellWithReuseIdentifier: "skeleton")
        view.register(UICollectionReusableView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "footer")
        data.supplementaryViewProvider = { [weak page] list, kind, path in
            let footer = list.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "footer", for: path)
            if let container = page?.loadMoreCommentsContainer {
                container.frame = footer.bounds
                container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                footer.addSubview(container)
            }
            return footer
        }
        // 后台期间外观若真的变了，回到前台再补一次重排。
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
        cache.totalCostLimit = 24 * 1024 * 1024
        cache.countLimit = 80
    }

    private var appearance: DetailTextAppearance {
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: AppTypography.commentBodyFont(), compatibleWith: view.traitCollection)
        return .init(width: max(1, view.bounds.width - 2 * PostDetailContentLayout.horizontalInset),
                     pointSize: font.pointSize, scale: view.traitCollection.displayScale, dark: view.traitCollection.userInterfaceStyle == .dark)
    }

    /// 切后台时系统为任务切换器拍浅色和深色快照，外观会来回切一次；此时整页重建会清空高度、回前台后列表跳动。
    var isAppInBackground: () -> Bool = { UIApplication.shared.applicationState == .background }

    func updateAppearance() {
        guard view.bounds.width > 0, !isAppInBackground(), previousAppearance != appearance else { return }
        previousAppearance = appearance
        invalidate()
    }

    @objc private func appWillEnterForeground() {
        DispatchQueue.main.async { [weak self] in self?.updateAppearance() }
    }

    func invalidate() {
        heights.removeAll()
        cache.removeAllObjects()
        reload()
    }

    func reload(refresh: Bool = true) {
        guard let page else { return }
        queuedRows.removeAll()
        refreshQueuedBanner = false
        switch page.displayMode {
        // 首次加载：一个主楼骨架加若干回复骨架；-1 表示主楼。
        case .skeleton: rows = (-1..<page.skeletonCommentRowCount).map(PostDetailViewController.DetailRow.skeletonComment)
        case .content, .pageSkeleton: rows = page.detailRows
        }
        var occurrences = [String: Int]()
        keys = rows.map { row in
            switch row {
            case .header: return "post-" + (page.currentHeaderContent?.postID ?? "")
            case .comment(let index):
                let comment = page.comments[index]
                let number = page.loadedCommentPageRanges.first { $0.value.contains(index) }?.key ?? page.currentPage
                return replyKey(comment, page: number, occurrences: &occurrences)
            case .authorFilterBanner: return "filter"
            case .entryHint: return "entry"
            case .replyPagination: return "reply-pages"
            case .postRepliesDivider: return "divider"
            case .skeletonComment(let index): return index < 0 ? "skeleton-header" : "skeleton-\(index)"
            }
        }
        let currentKeys = Set(keys)
        if let key = pendingAnchorKey, !currentKeys.contains(key) { pendingAnchorKey = nil }
        heights = heights.filter { currentKeys.contains($0.key) }
        tabSelections = tabSelections.filter { currentKeys.contains($0.key.floor) }
        // 预估值在一次加载内保持不变，否则视图尺寸变化会挪动已定位的锚点。
        // 带锚点或翻页打开时主楼可能横跨视口顶部，量完缩短会把目标楼层挤出屏幕，仍按小值预估。
        let opensAtTop = page.currentPage == 1 && page.pendingInitialAnchorID == nil && !page.pendingPageJumpScroll
        headerEstimate = opensAtTop ? max(100, view.bounds.height) : 100
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(keys)
        if !refresh, keys.contains("reply-pages"), data.snapshot().indexOfItem("reply-pages") != nil {
            snapshot.reconfigureItems(["reply-pages"])
        }
        if refresh {
            let previous = Set(data.snapshot().itemIdentifiers)
            snapshot.reconfigureItems(keys.filter(previous.contains))
        }
        data.apply(snapshot, animatingDifferences: false) { [weak self] in self?.scheduleBatchFetchCheck() }
    }

    private func replyKey(_ comment: Comment, page: Int, occurrences: inout [String: Int]) -> String {
        let prefix = "\(page)-\(comment.isHot ? "hot" : "reply")-\(comment.id)"
        let occurrence = occurrences[prefix, default: 0]
        occurrences[prefix] = occurrence + 1
        return "\(prefix)-\(occurrence)"
    }

    func resetPagination() {
        requestedPage = nil
        retryOnNextDrag = false
    }

    func didFinishLoadingMore() {
        retryOnNextDrag = requestedPage != nil && requestedPage == page?.pagination?.nextPage
        scheduleBatchFetchCheck()
    }

    func appendComments(in range: Range<Int>, pageNumber: Int, bannerChanged: Bool) {
        guard let page else { return }
        if range.lowerBound == 0, !range.isEmpty, page.currentHeaderContent != nil, page.authorFilter == nil {
            if !page.showsInlineReplyPagination { queuedRows.append((.postRepliesDivider, "divider")) }
        }
        var occurrences: [String: Int] = [:]
        for index in range {
            let comment = page.comments[index]
            guard page.authorFilter?.matches(comment) != false else { continue }
            let key = replyKey(comment, page: pageNumber, occurrences: &occurrences)
            queuedRows.append((.comment(index), key))
        }
        refreshQueuedBanner = refreshQueuedBanner || bannerChanged
        flushAppendIfPossible()
    }

    // 手指已拉过旧页底时，改变 contentSize 会移动系统回弹的终点。
    private func flushAppendIfPossible() {
        guard !queuedRows.isEmpty || refreshQueuedBanner else { return }
        let bottom = max(-view.adjustedContentInset.top, view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
        guard !userScrollInProgress || view.contentOffset.y <= bottom + 0.5 else { return }
        var snapshot = data.snapshot()
        let addedKeys = queuedRows.map(\.key)
        rows.append(contentsOf: queuedRows.map(\.row))
        keys.append(contentsOf: addedKeys)
        snapshot.appendItems(addedKeys, toSection: 0)
        if snapshot.indexOfItem("reply-pages") != nil { snapshot.reconfigureItems(["reply-pages"]) }
        if refreshQueuedBanner, snapshot.indexOfItem("filter") != nil { snapshot.reconfigureItems(["filter"]) }
        queuedRows.removeAll()
        refreshQueuedBanner = false
        data.apply(snapshot, animatingDifferences: false) { [weak self] in self?.scheduleBatchFetchCheck() }
    }

    private func cell(in list: UICollectionView, at path: IndexPath, key: String) -> UICollectionViewCell {
        guard let page, rows.indices.contains(path.item) else { preconditionFailure("Missing detail row") }
        let row = rows[path.item]
        var source: DetailFloorSource
        var title: String?
        var requiredLevel: Int?
        let author: String
        let badges: [String]
        var isPoster = false
        var isHot = false
        var showsRiskWarning = false
        let time: String?
        var floor: String?
        var signature: String?
        var comment: Comment?
        switch row {
        case .header:
            let header = page.currentHeaderContent!
            source = headerSource ?? .init(html: header.contentHTML, visibleMarkdown: nil)
            title = header.title
            requiredLevel = header.requiredReadingLevel
            author = header.authorName
            badges = header.authorBadgeTexts
            showsRiskWarning = page.authorRiskWarningPostID == header.postID
            time = header.metadataText
            signature = header.signatureHTML
        case .comment(let index):
            let value = page.comments[index]
            comment = value
            source = .init(comment: value)
            author = value.authorName
            badges = value.authorBadgeTexts
            isPoster = value.isPoster
            isHot = value.isHot
            floor = value.floorText?.trimmingCharacters(in: .whitespacesAndNewlines)
            time = value.createdAtText
            signature = value.signatureHTML
        case .replyPagination:
            let cell = list.dequeueReusableCell(withReuseIdentifier: "reply-pages", for: path) as! DetailReplyPaginationCell
            cell.configure(startPage: page.loadedCommentPageRanges.keys.min() ?? page.currentPage,
                           totalPages: page.totalCommentPages,
                           selectPage: { [weak page] in page?.jumpToCommentPage($0) },
                           openPicker: { [weak page] in page?.presentPagePicker() })
            return cell
        case .entryHint:
            let cell = list.dequeueReusableCell(withReuseIdentifier: "entry", for: path) as! DetailEntryHintCell
            cell.configure(page: page.entryHintPage, afterJump: page.hasJumpedCommentPage, traits: list.traitCollection)
            cell.onOpen = { [weak page] in page?.openFullPostFromEntryHint() }
            return cell
        case .skeletonComment:
            let cell = list.dequeueReusableCell(withReuseIdentifier: "skeleton", for: path) as! DetailSkeletonListCell
            cell.configure(key == "skeleton-header" ? .header : .comment)
            return cell
        case .authorFilterBanner:
            let cell = list.dequeueReusableCell(withReuseIdentifier: "filter", for: path) as! DetailAuthorFilterBannerCell
            cell.configure(text: page.authorFilterBannerText)
            cell.onClear = { [weak page] in page?.toggleAuthorFilter(nil, focusingCommentID: nil) }
            return cell
        default:
            let cell = list.dequeueReusableCell(withReuseIdentifier: "notice", for: path) as! UICollectionViewListCell
            var content = UIListContentConfiguration.cell()
            cell.contentConfiguration = content
            cell.backgroundConfiguration = .clear()
            cell.contentView.backgroundColor = key == "divider" ? .secondarySystemBackground : .systemBackground
            return cell
        }
        let cell = list.dequeueReusableCell(withReuseIdentifier: "floor", for: path) as! DetailFloorListCell
        generation += 1
        let indent = comment.map { AuthorDisplayPolicy.isDisplayable($0.authorName) } == true
            ? PostDetailContentLayout.avatarSize + PostDetailContentLayout.avatarSpacing : 0
        let traits = appearance
        let floorAppearance = DetailTextAppearance(width: max(1, traits.width - indent), pointSize: traits.pointSize, scale: traits.scale, dark: traits.dark)
        let request = DetailFloorRequest(id: key, version: generation, source: source, appearance: floorAppearance, baseURL: page.baseURL)
        cell.bind(request)
        cell.body.renderer = renderer
        cell.body.isLayoutMarginsRelativeArrangement = true
        cell.textIndent = indent
        cell.body.directionalLayoutMargins = .init(top: 0, leading: indent, bottom: 0, trailing: 0)
        // 先配置分支入口按钮，确保 configureHeader 里的 wrapBadges 准确留出按钮宽度，且不在滚屏时同步解析 Markdown。
        if let comment, let floorNum = CommentReplyRelationParser.floorNumber(for: comment), floorNum > 0 {
            cell.configureThreadEntry(floor: floorNum) { [weak page] in
                page?.presenter.didTapThreadedReplies(for: comment)
            }
        } else {
            cell.configureThreadEntry(floor: nil, perform: nil)
        }
        cell.configureHeader(title: title, requiredLevel: requiredLevel, name: author, isPoster: isPoster, badges: badges, time: time,
                             floor: floor, isHot: isHot, showsRiskWarning: showsRiskWarning)
        let sourceFloor = comment.flatMap(CommentReplyRelationParser.floorNumber(for:)) ?? 0
        cell.body.onLink = { [weak page] in page?.handleContentLinkTap($0, floor: sourceFloor) }
        cell.body.onSignatureLinks = { [weak page] in page?.handleSignatureLinkCandidatesTap($0) }
        cell.body.onPhotos = { [weak page] in page?.presentPhotoBrowser(imageURLs: $0, initialIndex: $1) }
        cell.body.imageSize = { [weak page] in page?.cachedDetailImageSize(for: $0) }
        cell.body.onImageSize = { [weak page] in page?.cacheDetailImageSize($1, for: $0) }
        cell.body.viewport = list
        let resized = { [weak self, weak cell] in
            DispatchQueue.main.async { [weak self, weak cell] in
                guard let self, let cell, cell.request == request else { return }
                self.updateHeight(cell, key: key)
            }
        }
        cell.body.onSizeChange = resized
        cell.body.savedTab = { [weak self] in self?.tabSelections[.init(floor: key, ordinal: $0)] ?? 0 }
        cell.body.onTabSelected = { [weak self] in self?.tabSelections[.init(floor: key, ordinal: $0)] = $1 }
        cell.didInstall = resized
        cell.body.onStickerSizeChange = { [weak self, weak cell] in
            guard let self, cell?.request == request else { return }
            self.cache.removeObject(forKey: key as NSString)
            self.refresh(key)
        }
        if let comment {
            cell.configureAuthor(name: comment.authorName, avatarURL: comment.avatarURL, profileURL: comment.authorProfileURL) { [weak page] in page?.openUserInfo(profileURL: $0) }
        } else if let header = page.currentHeaderContent {
            cell.configureAuthor(name: header.authorName, avatarURL: header.avatarURL, profileURL: header.authorProfileURL) { [weak page] in page?.openUserInfo(profileURL: $0) }
            if page.entryHintPage > 1, source.html.isEmpty, source.visibleMarkdown == nil, signature == nil {
                cell.floorActions = floorActions(page: page, cell: cell, comment: nil)
                cell.installPageSummary(request, hasAvatar: header.avatarURL != nil)
                return cell
            }
        }
        configureFloorActions(page: page, cell: cell, comment: comment)
        if let cached = cache.object(forKey: key as NSString), cached.source == source, cached.appearance == request.appearance {
            cell.receiver.install(request, .native(cached.blocks))
        } else {
            cell.onNative = { [weak self] blocks in
                self?.cache.setObject(CachedText(request, blocks), forKey: key as NSString, cost: Self.bitmapCost(blocks))
            }
            cell.renderTask = cell.body.renderer.start(request, deliver: cell.receiver.install)
        }
        if PostSignatureDisplaySettings.shared.showsSignatures, let signature, !signature.isEmpty {
            let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: AppTypography.signatureFont(), compatibleWith: list.traitCollection)
            cell.loadSignature(signature, pointSize: font.pointSize, for: request)
        }
        return cell
    }

    private func configureFloorActions(page: PostDetailViewController, cell: DetailFloorListCell, comment: Comment?) {
        cell.floorActions = floorActions(page: page, cell: cell, comment: comment)
        guard !cell.body.isHidden else { return } // 从后续页进入时，主楼摘要只有菜单。
        cell.compactCounts = comment == nil
        cell.replaceActions {
            if let comment {
                cell.addVotes(like: comment.likeCount, chicken: comment.chickenLegCount, oppose: comment.opposeCount,
                              liked: comment.isLikeClicked, rewarded: comment.isChickenLegClicked, opposed: comment.isOpposeClicked,
                              isOwn: comment.isOwnComment,
                              onLike: { [weak page] in page?.handleCommentLikeTap(comment) },
                              onChicken: { [weak page] in page?.handleCommentChickenLegTap(comment) },
                              onOppose: { [weak page] in page?.handleCommentOpposeTap(comment) })
                // 回复、引用常驻底栏，本人楼层另有编辑。
                let floor = comment.anchorID
                cell.addAction("reply", symbol: "arrowshape.turn.up.left", label: "reply-comment") { [weak page] in page?.handleReply(to: comment) }
                cell.addAction("quote", symbol: "quote.bubble", label: "quote-comment",
                               identifier: floor.map { "post-detail-quote-comment-\($0)-\(comment.id)" }) { [weak page] in page?.handleQuote(comment) }
                if comment.isOwnComment {
                    cell.addAction("edit", symbol: "square.and.pencil", label: "edit-comment",
                                   identifier: floor.map { "post-detail-edit-comment-\($0)-\(comment.id)" }) { [weak page] in page?.presenter.didTapEditComment(comment) }
                }
            } else if let header = page.currentHeaderContent {
                if headerHasReactions(header) {
                    cell.addVotes(like: header.likeCount, chicken: header.chickenLegCount, oppose: header.opposeCount,
                                  liked: header.isLikeClicked, rewarded: header.isChickenLegClicked, opposed: header.isOpposeClicked,
                                  isOwn: header.isOwnPost,
                                  onLike: { [weak page] in page?.handlePostLikeTap(header) },
                                  onChicken: { [weak page] in page?.handlePostChickenLegTap(header) },
                                  onOppose: { [weak page] in page?.handlePostOpposeTap(header) })
                    cell.addAction("favorite", symbol: header.isFavoriteCollected ? "star.fill" : "star", count: header.favoriteCount,
                                   selected: header.isFavoriteCollected, enabled: !header.isFavoriteSubmitting) { [weak page] in page?.handleFavoriteTap() }
                }
                if page.showsReplyEntry {
                    cell.addAction("reply", symbol: "arrowshape.turn.up.left", label: "reply-post") { [weak page] in page?.handleReply(toPostHeader: header) }
                    cell.addAction("comment", symbol: "text.bubble") { [weak page] in page?.presentCommentEditor() }
                }
                if header.isOwnPost {
                    cell.addAction("edit", symbol: "square.and.pencil", label: "edit-post") { [weak page] in page?.presenter.didTapEditPost() }
                }
            }
        }
    }

    private static func bitmapCost(_ blocks: [DetailLayoutBlock]) -> Int {
        blocks.reduce(0) { cost, block in
            switch block {
            case .text(let text): return cost + text.tiles.reduce(0) { $0 + $1.image.bytesPerRow * $1.image.height }
            case .quote(let nested), .tabs(_, let nested): return cost + bitmapCost(nested)
            case .widget: return cost
            }
        }
    }

    func refresh(commentID: String) {
        guard let page else { return }
        let affected = zip(rows, keys).compactMap { row, key -> String? in
            guard case .comment(let index) = row, page.comments[index].id == commentID else { return nil }
            return key
        }
        guard !affected.isEmpty else { return }
        var snapshot = data.snapshot()
        snapshot.reconfigureItems(affected)
        data.apply(snapshot, animatingDifferences: false)
    }

    func refreshReactions(commentID: String? = nil) {
        guard let page else { return }
        for (row, key) in zip(rows, keys) {
            let comment: Comment?
            switch row {
            case .header where commentID == nil: comment = nil
            case .comment(let index) where page.comments[index].id == commentID: comment = page.comments[index]
            default: continue
            }
            // 离屏楼层下次绑定时从模型读最新状态，已绑定的楼层只更新底栏和菜单。
            guard let path = data.indexPath(for: key), let cell = view.cellForItem(at: path) as? DetailFloorListCell,
                  cell.request?.id == key else { continue }
            configureFloorActions(page: page, cell: cell, comment: comment)
        }
    }

    func refreshHeader() {
        guard let key = keys.first(where: { $0.hasPrefix("post-") }) else { return }
        refresh(key)
    }

    private func refresh(_ key: String) {
        guard data.indexPath(for: key) != nil else { return }
        var snapshot = data.snapshot()
        snapshot.reconfigureItems([key])
        data.apply(snapshot, animatingDifferences: false)
    }

    private func updateHeight(_ cell: DetailFloorListCell, key: String) {
        guard let index = data.indexPath(for: key), view.bounds.width > 0 else { return }
        let height = cell.measuredHeight(width: view.bounds.width)
        // 已量过的楼层在复用时先收到正文、后收到签名；不能用半成品缩短列表。
        if let measured = heights[key], !cell.isSettled, height < measured { return }
        let old = heights[key] ?? estimatedHeight(for: key)
        guard abs(old - height) >= 0.5 else { return }
        heights[key] = height
        let context = UICollectionViewFlowLayoutInvalidationContext()
        context.invalidateFlowLayoutDelegateMetrics = true
        // 布局失效期间 flow 可能返回零尺寸。仅补偿确实位于视口上方、已经显示过的楼层。
        let visibleTop = view.contentOffset.y + view.adjustedContentInset.top
        if visibleTop > 0, view.indexPath(for: cell) == index, cell.frame.height > 0,
           cell.frame.maxY <= visibleTop {
            context.contentOffsetAdjustment.y = height - old
        }
        flow.invalidateLayout(with: context)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let key = keys.indices.contains(indexPath.item) ? keys[indexPath.item] : ""
        if key.hasPrefix("skeleton") {
            let height = DetailSkeletonListCell.height(for: key == "skeleton-header" ? .header : .comment)
            return CGSize(width: max(1, collectionView.bounds.width), height: height)
        }
        if key == "entry", let page {
            let width = max(1, collectionView.bounds.width)
            sizingEntryHint.configure(page: page.entryHintPage, afterJump: page.hasJumpedCommentPage, traits: collectionView.traitCollection)
            return CGSize(width: width, height: sizingEntryHint.height(for: width))
        }
        if key == "reply-pages" {
            return CGSize(width: collectionView.bounds.width, height: DetailReplyPaginationCell.height(for: collectionView.traitCollection))
        }
        if key == "filter", let page {
            let width = max(1, collectionView.bounds.width)
            sizingFilterBanner.configure(text: page.authorFilterBannerText)
            return CGSize(width: width, height: sizingFilterBanner.height(for: width))
        }
        return CGSize(width: max(1, collectionView.bounds.width), height: heights[key] ?? estimatedHeight(for: key))
    }

    private func estimatedHeight(for key: String) -> CGFloat {
        if key == "divider" { return 8 }
        // 主楼量出高度前按一屏预估：首帧只建主楼，避免一次建出随后被挤出屏幕的整屏回复。
        if key.hasPrefix("post-") { return headerEstimate }
        return 100
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? DetailFloorListCell)?.refreshPlayback()
        showPendingHighlight(on: cell)
        if indexPath.item == 0 { scheduleBatchFetchCheck() }
    }

    func scheduleBatchFetchCheck() {
        guard !batchCheckScheduled, let next = page?.pagination?.nextPage, next != requestedPage else { return }
        batchCheckScheduled = true
        // 等这一轮布局和 presenter 的页码更新完成，再根据最新剩余距离发请求。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.batchCheckScheduled = false
            self.requestNextPageIfNeeded()
        }
    }

    private func requestNextPageIfNeeded(at offsetY: CGFloat? = nil) {
        // 跳页、刷新和筛选自动补页期间，旧列表的滚动回调不能抢占下一次请求。
        // 自动补页只在排队时拦截：请求中已有加载指示器；请求失败后连续计数不会清零，按计数拦会让滚动再也翻不了页。
        guard let page, !page.pendingPageJumpScroll, !page.loadingIndicator.isAnimating,
              !page.loadMoreCommentsIndicator.isAnimating, page.authorFilterAutoLoadWorkItem == nil,
              page.displayMode == .content, let next = page.pagination?.nextPage,
              next > page.currentPage, requestedPage != next, queuedRows.isEmpty,
              view.window != nil, view.contentSize.height > 0 else { return }
        var bounds = view.bounds
        if let offsetY { bounds.origin.y = offsetY }
        let viewport = bounds.inset(by: view.adjustedContentInset)
        guard viewport.height > 0, view.contentSize.height - viewport.maxY <= page.leadingScreensForBatching * viewport.height else { return }
        requestedPage = next
        retryOnNextDrag = false
        if !page.presenter.didApproachCommentEnd() { requestedPage = nil }
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? DetailFloorListCell)?.refreshPlayback()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if !queuedRows.isEmpty || refreshQueuedBanner {
            DispatchQueue.main.async { [weak self] in self?.flushAppendIfPossible() }
        }
        if scrollView.contentOffset.y > lastOffsetY { scheduleBatchFetchCheck() }
        lastOffsetY = scrollView.contentOffset.y
        page?.scrollViewDidScroll(scrollView)
        for case let floor as DetailFloorListCell in view.visibleCells { floor.refreshPlayback() }
    }
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let targetY = targetContentOffset.pointee.y
        guard velocity.y > 0, targetY > scrollView.contentOffset.y else { return }
        // 快速上滑时按系统预计的停靠位置提前加载，保留系统给出的惯性落点。
        requestNextPageIfNeeded(at: targetY)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { finishUserScroll() }
        page?.scrollViewDidEndDragging(scrollView, willDecelerate: decelerate)
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finishUserScroll()
        page?.scrollViewDidEndDecelerating(scrollView)
    }

    private func finishUserScroll() {
        userScrollInProgress = false
        flushAppendIfPossible()
    }
}

extension PostDetailCollectionList {
    /// 首次从骨架切到内容前调用：用骨架快照盖住列表，等首屏楼层装好正文、签名且高度稳定后再揭开，
    /// 最长等待 timeout，避免露出空楼层和预估高度后再跳动。
    func coverUntilSettled(timeout: TimeInterval) {
        guard revealCover == nil, let superview = view.superview, view.window != nil,
              let cover = view.snapshotView(afterScreenUpdates: false) ?? view.snapshotView(afterScreenUpdates: true) else {
            AppLog.debug(.postDetail, "首屏遮盖跳过: superview=\(view.superview != nil) window=\(view.window != nil)")
            return
        }
        cover.frame = view.frame
        cover.accessibilityIdentifier = "post-detail-reveal-cover"
        superview.insertSubview(cover, aboveSubview: view)
        revealCover = cover
        revealDeadline = CACurrentMediaTime() + timeout
        settledChecks = 0
        DispatchQueue.main.async { [weak self] in self?.checkReveal() }
    }

    private func checkReveal() {
        guard let cover = revealCover else { return }
        view.layoutIfNeeded()
        // 正文和签名异步撑高前面的楼层；首屏揭开前按实际高度校准深链的目标位置。
        if let key = pendingAnchorKey, let path = data.indexPath(for: key) {
            scroll(to: path.item, position: .centeredVertically)
            view.layoutIfNeeded()
        }
        let floors = view.visibleCells.compactMap { $0 as? DetailFloorListCell }
        // 高度回写在装入后的下一轮主队列执行，连续两次检查都稳定才算排好。
        settledChecks = !floors.isEmpty && floors.allSatisfy(\.isSettled) ? settledChecks + 1 : 0
        guard settledChecks >= 2 || CACurrentMediaTime() >= revealDeadline else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [weak self] in self?.checkReveal() }
            return
        }
        revealCover = nil
        if let key = pendingAnchorKey, let path = data.indexPath(for: key) {
            showPendingHighlight(on: view.cellForItem(at: path))
        }
        UIView.animate(withDuration: 0.15, animations: { cover.alpha = 0 }, completion: { _ in cover.removeFromSuperview() })
    }
}

private extension PostDetailCollectionList {
    func headerHasReactions(_ header: PostDetailHeaderContent) -> Bool {
        header.isLikeClicked || header.isFavoriteCollected ||
            [header.likeCount, header.chickenLegCount, header.opposeCount, header.favoriteCount].contains { $0 != nil }
    }

    internal func floorActions(page: PostDetailViewController, cell: DetailFloorListCell, comment: Comment?) -> [DetailFloorListCell.FloorAction] {
        let binding = cell.request
        var actions: [DetailFloorListCell.FloorAction] = []
        func add(_ key: String, _ image: UIImage?, _ perform: @escaping (PostDetailViewController) -> Void) {
            actions.append(.init(title: DetailListStrings.text(key), image: image) { [weak page, weak cell] in
                guard let page, let cell, cell.request == binding else { return false }
                perform(page)
                return true
            })
        }
        let filterIcon = UIImage(systemName: "person.crop.circle")
        let editIcon = UIImage(systemName: "square.and.pencil")
        add("copy", UIImage(systemName: "doc.on.doc")) { [weak cell] page in
            // 正文排好前用网页内容兜底，复制后提示，没有内容时直接说明。
            func fallback() -> String? {
                comment.map { CommentCopyTextFormatter.plainText(for: $0, baseURL: page.baseURL) }
                    ?? page.currentHeaderContent.map { CommentCopyTextFormatter.plainText(for: $0, baseURL: page.baseURL) }
            }
            guard let text = cell?.copyText ?? fallback(), !text.isEmpty else {
                page.showToast(message: DetailListStrings.text("nothing-to-copy"))
                return
            }
            page.present(CommentCopySheetViewController(text: text, pasteboardStringWriter: { [weak page] copied in
                page?.pasteboardStringWriter(copied)
                page?.showToast(message: DetailListStrings.text("copied"))
            }), animated: true)
        }
        // 菜单：复制、查看相关对话（有明确正整数楼层的评论）、投放鸡腿（非本人）、只看 TA（作者可展示时）、编辑。引用在底栏。
        if let comment {
            if let floor = CommentReplyRelationParser.floorNumber(for: comment), floor > 0 {
                add("thread-replies", UIImage(systemName: "arrow.turn.down.right")) {
                    $0.presenter.didTapThreadedReplies(for: comment)
                }
            }
            if !comment.isOwnComment { add("chicken", UIImage(named: "ChickenLeg")) { $0.handleCommentChickenLegTap(comment) } }
            if AuthorDisplayPolicy.isDisplayable(comment.authorName) {
                add(page.authorFilter == nil ? "author-them" : "all", filterIcon) { $0.toggleAuthorFilter(.author(of: comment), focusingCommentID: comment.id) }
            }
            if comment.isOwnComment { add("edit", editIcon) { $0.presenter.didTapEditComment(comment) } }
        } else if let header = page.currentHeaderContent {
            if !headerHasReactions(header), !header.isOwnPost, page.showsReplyEntry {
                add("chicken", UIImage(named: "ChickenLeg")) { $0.handlePostChickenLegTap(header) }
            }
            add(page.authorFilter == nil ? "author-poster" : "all", filterIcon) { $0.toggleAuthorFilter(.poster(of: header), focusingCommentID: nil) }
            if header.isOwnPost { add("edit", editIcon) { $0.presenter.didTapEditPost() } }
        }
        return actions
    }
}

extension PostDetailCollectionList {
    func scrollToAnchor(at row: Int) {
        if !keys.indices.contains(row) { finishUserScroll() }
        guard keys.indices.contains(row) else { return }
        highlightedFloor?.clearAnchorHighlight()
        pendingAnchorKey = keys[row]
        scroll(to: row, position: .centeredVertically)
        view.layoutIfNeeded()
        showPendingHighlight(on: view.cellForItem(at: IndexPath(item: row, section: 0)))
    }

    private func showPendingHighlight(on cell: UICollectionViewCell?) {
        guard let key = pendingAnchorKey, revealCover == nil,
              let floor = cell as? DetailFloorListCell, floor.request?.id == key else { return }
        pendingAnchorKey = nil
        highlightedFloor = floor
        floor.flashAnchorHighlight()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        pendingAnchorKey = nil
        userScrollInProgress = true
        if retryOnNextDrag { resetPagination() }
    }

    func scroll(to row: Int, position: UICollectionView.ScrollPosition) {
        guard keys.indices.contains(row), row < view.numberOfItems(inSection: 0) else { return }
        view.layoutIfNeeded()
        view.scrollToItem(at: IndexPath(item: row, section: 0), at: position, animated: false)
    }
}

/// 楼层底栏按钮是 UIControl，系统默认不让列表接管已交给按钮的触摸。这里让按住按钮再拖动仍能滚动列表。
private final class DetailCollectionView: UICollectionView {
    var onAppearanceChange: (() -> Void)?

    override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame, collectionViewLayout: layout)
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Self, _: UITraitCollection) in
                view.onAppearanceChange?()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(iOS, introduced: 2.0, deprecated: 17.0)
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 17.0, *) { return }
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle { onAppearanceChange?() }
    }

    override func touchesShouldCancel(in view: UIView) -> Bool {
        view is UIButton || super.touchesShouldCancel(in: view)
    }
}
