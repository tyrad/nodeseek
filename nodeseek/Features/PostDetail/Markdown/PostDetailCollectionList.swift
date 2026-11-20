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
    private var rows: [PostDetailViewController.DetailRow] = []
    private var keys: [String] = []
    private var heights: [String: CGFloat] = [:]
    private let cache = NSCache<NSString, CachedText>()
    private var generation = 0
    private var previousAppearance: DetailTextAppearance?
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
        rows = page.displayMode == .content ? page.detailRows : []
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
            case .skeletonComment(let index): return "skeleton-\(index)"
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
        data.apply(snapshot, animatingDifferences: false)
    }

    private func cell(in list: UICollectionView, at path: IndexPath, key: String) -> UICollectionViewCell {
        guard let page, rows.indices.contains(path.item) else { preconditionFailure("Missing detail row") }
        let row = rows[path.item]
        var source: DetailFloorSource
        var title: String?
        var metadata: [String?]
        var signature: String?
        var comment: Comment?
        switch row {
        case .header:
            let header = page.currentHeaderContent!
            source = headerSource ?? .init(html: header.contentHTML, visibleMarkdown: nil)
            title = header.title + (header.requiredReadingLevel.map { " 🔒 \($0)" } ?? "")
            metadata = [header.authorName, header.authorBadgeTexts.joined(separator: " "), header.metadataText, page.authorRiskWarningPostID == header.postID ? PostAuthorRiskWarningNode.message : nil]
            signature = header.signatureHTML
        case .comment(let index):
            let value = page.comments[index]
            comment = value
            source = .init(comment: value)
            metadata = [value.authorName, value.isPoster ? DetailListStrings.text("poster") : nil, value.authorBadgeTexts.joined(separator: " "), value.isHot ? DetailListStrings.text("hot") : nil, value.floorText, value.createdAtText]
            signature = value.signatureHTML
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
        cell.heading.font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: AppTypography.detailTitleFont())
        cell.metadata.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: AppTypography.commentMetadataFont())
        cell.heading.text = title
        cell.heading.isHidden = title == nil
        cell.metadata.text = metadata.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
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
            cell.addAction("like", symbol: "hand.thumbsup", count: comment.likeCount, selected: comment.isLikeClicked) { [weak page] in page?.handleCommentLikeTap(comment) }
            cell.addAction("oppose", symbol: "hand.thumbsdown", count: comment.opposeCount, selected: comment.isOpposeClicked) { [weak page] in page?.handleCommentOpposeTap(comment) }
            cell.addAction("chicken", symbol: "fork.knife", count: comment.chickenLegCount, selected: comment.isChickenLegClicked) { [weak page] in page?.handleCommentChickenLegTap(comment) }
            cell.addAction("reply", symbol: "arrowshape.turn.up.left") { [weak page] in page?.handleReply(to: comment) }
        } else if let header = page.currentHeaderContent {
            cell.configureAuthor(name: header.authorName, avatarURL: header.avatarURL, profileURL: header.authorProfileURL) { [weak page] in page?.openUserInfo(profileURL: $0) }
            if page.showsReplyEntry {
                cell.addAction("like", symbol: "hand.thumbsup", count: header.likeCount, selected: header.isLikeClicked) { [weak page] in page?.handlePostLikeTap(header) }
                cell.addAction("oppose", symbol: "hand.thumbsdown", count: header.opposeCount, selected: header.isOpposeClicked) { [weak page] in page?.handlePostOpposeTap(header) }
                cell.addAction("favorite", symbol: "star", count: header.favoriteCount, selected: header.isFavoriteCollected) { [weak page] in page?.presenter.didTapFavorite() }
                cell.addAction("reply", symbol: "arrowshape.turn.up.left") { [weak page] in page?.handleReply(toPostHeader: header) }
            }
        }
        cell.menuButton.menu = menu(page: page, cell: cell, comment: comment)
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
        if let attributes = flow.layoutAttributesForItem(at: index),
           attributes.frame.maxY <= view.contentOffset.y + view.adjustedContentInset.top {
            context.contentOffsetAdjustment.y = height - old
        }
        flow.invalidateLayout(with: context)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let key = keys.indices.contains(indexPath.item) ? keys[indexPath.item] : ""
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
        if indexPath.item >= keys.count - 3 {
            DispatchQueue.main.async { [weak self] in
                guard let self, let page = self.page, page.authorFilter == nil, page.canRequestCommentBatchFetch(),
                      self.view.indexPathsForVisibleItems.contains(where: { $0.item >= self.keys.count - 3 }) else { return }
                page.lastBatchFetchRequestedCommentCount = page.comments.count
                page.presenter.didApproachCommentEnd()
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? DetailFloorListCell)?.body.refreshPlayback()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        page?.scrollViewDidScroll(scrollView)
        for case let floor as DetailFloorListCell in view.visibleCells { floor.body.refreshPlayback() }
    }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        page?.scrollViewDidEndDragging(scrollView, willDecelerate: decelerate)
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { page?.scrollViewDidEndDecelerating(scrollView) }
}

private extension PostDetailCollectionList {
    func menu(page: PostDetailViewController, cell: DetailFloorListCell, comment: Comment?) -> UIMenu {
        var actions: [UIAction] = []
        func add(_ key: String, _ perform: @escaping (PostDetailViewController) -> Void) {
            actions.append(UIAction(title: DetailListStrings.text(key)) { [weak page] _ in
                if let page { perform(page) }
            })
        }
        let binding = cell.request
        add("copy") { [weak cell] page in
            if cell?.request == binding, let text = cell?.copyText {
                page.present(CommentCopySheetViewController(text: text), animated: true)
            }
        }
        if let comment {
            add("quote") { $0.handleQuote(comment) }
            add("chicken") { $0.handleCommentChickenLegTap(comment) }
            add(page.authorFilter == nil ? "author" : "all") { $0.toggleAuthorFilter(.author(of: comment), focusingCommentID: comment.id) }
            if comment.isOwnComment { add("edit") { $0.presenter.didTapEditComment(comment) } }
        } else if let header = page.currentHeaderContent {
            add("chicken") { $0.handlePostChickenLegTap(header) }
            add(page.authorFilter == nil ? "author" : "all") { $0.toggleAuthorFilter(.poster(of: header), focusingCommentID: nil) }
            if header.isOwnPost { add("edit") { $0.presenter.didTapEditPost() } }
        }
        return UIMenu(children: actions)
    }
}

extension PostDetailCollectionList {
    func scroll(to row: Int, position: UICollectionView.ScrollPosition) {
        guard keys.indices.contains(row), row < view.numberOfItems(inSection: 0) else { return }
        view.layoutIfNeeded()
        view.scrollToItem(at: IndexPath(item: row, section: 0), at: position, animated: false)
    }
}
