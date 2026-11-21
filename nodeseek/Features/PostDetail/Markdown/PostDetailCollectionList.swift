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
    private let flow = UICollectionViewFlowLayout()
    let view: UICollectionView
    private(set) var rows: [PostDetailViewController.DetailRow] = []
    private var keys: [String] = []
    private var heights: [String: CGFloat] = [:]
    private let cache = NSCache<NSString, CachedText>()
    private var batchCheckScheduled = false
    private var generation = 0
    private var previousAppearance: DetailTextAppearance?
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
        view = UICollectionView(frame: .zero, collectionViewLayout: flow)
        super.init()
        view.backgroundColor = .systemBackground
        view.alwaysBounceVertical = true
        view.accessibilityIdentifier = "post-detail-textkit-collection"
        view.delegate = self
        view.register(DetailFloorListCell.self, forCellWithReuseIdentifier: "floor")
        view.register(UICollectionViewListCell.self, forCellWithReuseIdentifier: "notice")
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
        cache.totalCostLimit = 24 * 1024 * 1024
        cache.countLimit = 80
    }

    private var appearance: DetailTextAppearance {
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: AppTypography.commentBodyFont(), compatibleWith: view.traitCollection)
        return .init(width: max(1, view.bounds.width - 2 * PostDetailContentLayout.horizontalInset),
                     pointSize: font.pointSize, scale: view.traitCollection.displayScale, dark: view.traitCollection.userInterfaceStyle == .dark)
    }

    func updateAppearance() {
        guard view.bounds.width > 0, previousAppearance != appearance else { return }
        previousAppearance = appearance
        invalidate()
    }

    func invalidate() {
        heights.removeAll()
        cache.removeAllObjects()
        reload()
    }

    func reload(refresh: Bool = true) {
        guard let page else { return }
        switch page.displayMode {
        // 首次加载：与 Texture 相同，一个主楼骨架加若干回复骨架；-1 表示主楼。
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
                let prefix = "\(number)-\(comment.isHot ? "hot" : "reply")-\(comment.id)"
                let occurrence = occurrences[prefix, default: 0]
                occurrences[prefix] = occurrence + 1
                return "\(prefix)-\(occurrence)"
            case .authorFilterBanner: return "filter"
            case .entryHint: return "entry"
            case .postRepliesDivider: return "divider"
            case .skeletonComment(let index): return index < 0 ? "skeleton-header" : "skeleton-\(index)"
            }
        }
        let currentKeys = Set(keys)
        heights = heights.filter { currentKeys.contains($0.key) }
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(keys)
        if refresh {
            let previous = Set(data.snapshot().itemIdentifiers)
            snapshot.reconfigureItems(keys.filter(previous.contains))
        }
        data.apply(snapshot, animatingDifferences: false) { [weak self] in self?.scheduleBatchFetchCheck() }
    }

    private func cell(in list: UICollectionView, at path: IndexPath, key: String) -> UICollectionViewCell {
        guard let page, rows.indices.contains(path.item) else { preconditionFailure("Missing detail row") }
        let row = rows[path.item]
        var source: DetailFloorSource
        var title: String?
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
            title = header.title + (header.requiredReadingLevel.map { " 🔒 \($0)" } ?? "")
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
        case .skeletonComment:
            let cell = list.dequeueReusableCell(withReuseIdentifier: "skeleton", for: path) as! DetailSkeletonListCell
            cell.configure(key == "skeleton-header" ? .header : .comment)
            return cell
        default:
            let cell = list.dequeueReusableCell(withReuseIdentifier: "notice", for: path) as! UICollectionViewListCell
            var content = UIListContentConfiguration.cell()
            content.text = key == "filter" ? page.authorFilterBannerText : key == "entry" ? DetailListStrings.text("open-first") : nil
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
        cell.configureHeader(title: title, name: author, isPoster: isPoster, badges: badges, time: time,
                             floor: floor, isHot: isHot, showsRiskWarning: showsRiskWarning)
        cell.body.onLink = { [weak page] in page?.handleContentLinkTap($0) }
        cell.body.onSignatureLinks = { [weak page] in page?.handleSignatureLinkCandidatesTap($0) }
        cell.body.onPhotos = { [weak page] in page?.presentPhotoBrowser(imageURLs: $0, initialIndex: $1) }
        cell.body.viewport = list
        let resized = { [weak self, weak cell] in
            DispatchQueue.main.async { [weak self, weak cell] in
                guard let self, let cell, cell.request == request else { return }
                self.updateHeight(cell, key: key)
            }
        }
        cell.body.onSizeChange = resized
        cell.didInstall = resized
        cell.body.onStickerSizeChange = { [weak self, weak cell] in
            guard let self, cell?.request == request else { return }
            self.cache.removeObject(forKey: key as NSString)
            self.refresh(key)
        }
        if let comment {
            cell.configureAuthor(name: comment.authorName, avatarURL: comment.avatarURL, profileURL: comment.authorProfileURL) { [weak page] in page?.openUserInfo(profileURL: $0) }
            cell.addVotes(like: comment.likeCount, chicken: comment.chickenLegCount, oppose: comment.opposeCount,
                          liked: comment.isLikeClicked, rewarded: comment.isChickenLegClicked, opposed: comment.isOpposeClicked,
                          isOwn: comment.isOwnComment,
                          onLike: { [weak page] in page?.handleCommentLikeTap(comment) },
                          onChicken: { [weak page] in page?.handleCommentChickenLegTap(comment) },
                          onOppose: { [weak page] in page?.handleCommentOpposeTap(comment) })
            cell.addAction("reply", symbol: "arrowshape.turn.up.left") { [weak page] in page?.handleReply(to: comment) }
        } else if let header = page.currentHeaderContent {
            cell.configureAuthor(name: header.authorName, avatarURL: header.avatarURL, profileURL: header.authorProfileURL) { [weak page] in page?.openUserInfo(profileURL: $0) }
            if headerHasReactions(header) {
                cell.addVotes(like: header.likeCount, chicken: header.chickenLegCount, oppose: header.opposeCount,
                              liked: header.isLikeClicked, rewarded: header.isChickenLegClicked, opposed: header.isOpposeClicked,
                              isOwn: header.isOwnPost,
                              onLike: { [weak page] in page?.handlePostLikeTap(header) },
                              onChicken: { [weak page] in page?.handlePostChickenLegTap(header) },
                              onOppose: { [weak page] in page?.handlePostOpposeTap(header) })
                cell.addAction("favorite", symbol: header.isFavoriteCollected ? "star.fill" : "star", count: header.favoriteCount,
                               selected: header.isFavoriteCollected, enabled: !header.isFavoriteSubmitting) { [weak page] in page?.presenter.didTapFavorite() }
            }
            if page.showsReplyEntry {
                cell.addAction("reply", symbol: "arrowshape.turn.up.left") { [weak page] in page?.handleReply(toPostHeader: header) }
                cell.addAction("comment", symbol: "text.bubble") { [weak page] in page?.presentCommentEditor() }
            }
        }
        cell.floorActions = floorActions(page: page, cell: cell, comment: comment)
        if let cached = cache.object(forKey: key as NSString), cached.source == source, cached.appearance == request.appearance {
            cell.receiver.install(request, .native(cached.blocks))
        } else {
            cell.onNative = { [weak self] blocks in
                self?.cache.setObject(CachedText(request, blocks), forKey: key as NSString, cost: Self.bitmapCost(blocks))
            }
            cell.renderTask = cell.body.renderer.start(request, deliver: cell.receiver.install)
        }
        if PostSignatureDisplaySettings.shared.showsSignatures, let signature, !signature.isEmpty {
            cell.loadSignature(signature, for: request)
        }
        return cell
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

    private func refresh(_ key: String) {
        guard data.indexPath(for: key) != nil else { return }
        var snapshot = data.snapshot()
        snapshot.reconfigureItems([key])
        data.apply(snapshot, animatingDifferences: false)
    }

    private func updateHeight(_ cell: DetailFloorListCell, key: String) {
        guard let index = data.indexPath(for: key), view.bounds.width > 0 else { return }
        let height = cell.measuredHeight(width: view.bounds.width)
        let old = heights[key] ?? 100
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
        let estimate: CGFloat = key == "divider" ? 8 : ["filter", "entry"].contains(key) ? 48 : 100
        return CGSize(width: max(1, collectionView.bounds.width), height: heights[key] ?? estimate)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let page, rows.indices.contains(indexPath.item) else { return }
        switch rows[indexPath.item] {
        case .entryHint: page.openFullPostFromEntryHint()
        case .authorFilterBanner: page.toggleAuthorFilter(nil, focusingCommentID: nil)
        default: break
        }
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? DetailFloorListCell)?.body.refreshPlayback()
        scheduleBatchFetchCheck()
    }

    private func scheduleBatchFetchCheck() {
        guard !batchCheckScheduled, let page, page.canRequestCommentBatchFetch() else { return }
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
        guard let page, !page.pendingPageJumpScroll, !page.loadingIndicator.isAnimating,
              !page.loadMoreCommentsIndicator.isAnimating, page.authorFilterAutoLoadStreak == 0,
              page.canRequestCommentBatchFetch(),
              view.window != nil, view.contentSize.height > 0 else { return }
        var bounds = view.bounds
        if let offsetY { bounds.origin.y = offsetY }
        let viewport = bounds.inset(by: view.adjustedContentInset)
        guard viewport.height > 0, view.contentSize.height - viewport.maxY <= page.leadingScreensForBatching * viewport.height else { return }
        page.lastBatchFetchRequestedCommentCount = page.comments.count
        page.presenter.didApproachCommentEnd()
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? DetailFloorListCell)?.body.refreshPlayback()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        scheduleBatchFetchCheck()
        page?.scrollViewDidScroll(scrollView)
        for case let floor as DetailFloorListCell in view.visibleCells { floor.body.refreshPlayback() }
    }
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let targetY = targetContentOffset.pointee.y
        guard velocity.y > 0, targetY > scrollView.contentOffset.y else { return }
        // 快速上滑时按系统预计的停靠位置提前加载，保留系统给出的惯性落点。
        requestNextPageIfNeeded(at: targetY)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        page?.scrollViewDidEndDragging(scrollView, willDecelerate: decelerate)
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { page?.scrollViewDidEndDecelerating(scrollView) }
}

extension PostDetailCollectionList {
    /// 首次从骨架切到内容前调用：用骨架快照盖住列表，等首屏楼层装好正文、签名且高度稳定后再揭开，
    /// 最长等待 timeout，与 Texture 首屏揭示一致，避免露出空楼层和预估高度后再跳动。
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
        let floors = view.visibleCells.compactMap { $0 as? DetailFloorListCell }
        // 高度回写在装入后的下一轮主队列执行，连续两次检查都稳定才算排好。
        settledChecks = !floors.isEmpty && floors.allSatisfy(\.isSettled) ? settledChecks + 1 : 0
        guard settledChecks >= 2 || CACurrentMediaTime() >= revealDeadline else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [weak self] in self?.checkReveal() }
            return
        }
        revealCover = nil
        UIView.animate(withDuration: 0.15, animations: { cover.alpha = 0 }, completion: { _ in cover.removeFromSuperview() })
    }
}

private extension PostDetailCollectionList {
    func headerHasReactions(_ header: PostDetailHeaderContent) -> Bool {
        [header.likeCount, header.chickenLegCount, header.opposeCount, header.favoriteCount].contains { $0 != nil }
    }

    func floorActions(page: PostDetailViewController, cell: DetailFloorListCell, comment: Comment?) -> [DetailFloorListCell.FloorAction] {
        let binding = cell.request
        var actions: [DetailFloorListCell.FloorAction] = []
        func add(_ key: String, _ perform: @escaping (PostDetailViewController) -> Void) {
            actions.append(.init(title: DetailListStrings.text(key)) { [weak page, weak cell] in
                guard let page, let cell, cell.request == binding else { return false }
                perform(page)
                return true
            })
        }
        add("copy") { [weak cell] page in
            if let text = cell?.copyText {
                page.present(CommentCopySheetViewController(text: text), animated: true)
            }
        }
        if let comment {
            add("quote") { $0.handleQuote(comment) }
            add(page.authorFilter == nil ? "author" : "all") { $0.toggleAuthorFilter(.author(of: comment), focusingCommentID: comment.id) }
            if comment.isOwnComment { add("edit") { $0.presenter.didTapEditComment(comment) } }
        } else if let header = page.currentHeaderContent {
            if !headerHasReactions(header), !header.isOwnPost, page.showsReplyEntry {
                add("chicken") { $0.handlePostChickenLegTap(header) }
            }
            add(page.authorFilter == nil ? "author" : "all") { $0.toggleAuthorFilter(.poster(of: header), focusingCommentID: nil) }
            if header.isOwnPost { add("edit") { $0.presenter.didTapEditPost() } }
        }
        return actions
    }
}

extension PostDetailCollectionList {
    func scroll(to row: Int, position: UICollectionView.ScrollPosition) {
        guard keys.indices.contains(row), row < view.numberOfItems(inSection: 0) else { return }
        view.layoutIfNeeded()
        view.scrollToItem(at: IndexPath(item: row, section: 0), at: position, animated: false)
    }
}
