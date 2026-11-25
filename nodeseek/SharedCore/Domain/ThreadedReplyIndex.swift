import Foundation

/// 吃瓜面板中展示在焦点楼上方的上游被回复楼层。
nonisolated struct ThreadedAncestorNode: Equatable, Sendable {
    let comment: Comment
    let floor: Int
    /// 若该祖先的直接父楼也位于上游链中，记录用于裁剪重复父引用。
    let parentFloorInChain: Int?
    /// 是否与上方紧邻的祖先存在直接父子关系（互不相关的多父楼之间不连竖线）。
    let connectsFromPrevious: Bool
    /// 是否向下连接到下一条祖先或焦点楼。
    let connectsToNext: Bool

    init(
        comment: Comment,
        floor: Int,
        parentFloorInChain: Int?,
        connectsFromPrevious: Bool = false,
        connectsToNext: Bool = true
    ) {
        self.comment = comment
        self.floor = floor
        self.parentFloorInChain = parentFloorInChain
        self.connectsFromPrevious = connectsFromPrevious
        self.connectsToNext = connectsToNext
    }

    var stableID: String {
        "thread-ancestor-\(floor)-comment-\(comment.id)"
    }
}

/// 吃瓜面板中单条层叠子楼节点。
nonisolated struct ThreadedReplyNode: Equatable, Sendable {
    static let maxVisualDepth = 3

    let comment: Comment
    let floor: Int
    let parentFloor: Int
    /// 相对根楼的真实深度（直接回复为 1，二级跟帖为 2，以此类推）。
    let depth: Int
    /// 每一级祖先（索引 0 对应 depth=1 的层级）在当前节点之后是否仍有后续兄弟，用于绘制分支竖线。
    let ancestorContinuations: [Bool]
    let isLastSibling: Bool
    let hasChildren: Bool

    /// 面板最大缩进为三级，超过三级保持三级宽度并用「回复 #上级」标明。
    var visualDepth: Int {
        min(depth, Self.maxVisualDepth)
    }

    var showsParentBadge: Bool {
        depth > Self.maxVisualDepth
    }

    var stableID: String {
        "thread-floor-\(floor)-comment-\(comment.id)"
    }
}

/// 针对某个根楼层生成的当前对话快照（含上游祖先链与下游层叠子树）。
nonisolated struct ThreadedReplyTree: Equatable, Sendable {
    let rootFloor: Int
    let rootComment: Comment?
    /// 展示在焦点楼上方的上游祖先链（按楼号升序，最早的对话起点在最上方）。
    let ancestors: [ThreadedAncestorNode]
    /// 焦点楼若直接回复了已展示在 `ancestors` 中的某楼，记录用于裁剪重复父引用。
    let rootDisplayedParentFloor: Int?
    /// 焦点楼是否与紧邻的最后一条祖先存在直接父子连线。
    let rootConnectsFromTop: Bool
    let nodes: [ThreadedReplyNode]
    /// 缺失的上游祖先页与从焦点楼所在页到已确认末页是否均已覆盖完成。
    let isComplete: Bool
    let totalPages: Int?
    let completedPages: Set<Int>

    /// 计数仅统计下游回复，不含焦点楼和上游祖先。
    var replyCount: Int { nodes.count }
}

/// 单篇帖子的按页回复关系索引。
/// 每条评论只在入库当页解析一次 Markdown 关系并缓存在 `PageRecord` 中，聚合阶段只做纯内存合并。
nonisolated struct ThreadedReplyIndex: Equatable, Sendable {
    typealias TargetExtractor = @Sendable (String?, String, Int, URL) -> [Int]

    /// 单页内已解析完成的楼层条目（可在后台线程提前构造）。
    struct ParsedFloorEntry: Equatable, Sendable {
        let comment: Comment
        let floor: Int
        let sourcePage: Int
        let isPrimarySource: Bool
        let targets: [Int]
    }

    struct PageRecord: Equatable, Sendable {
        let page: Int
        let entries: [ParsedFloorEntry]
        let nextPage: Int?
        let isLastPage: Bool
        let totalPages: Int?
    }

    let postID: String
    let baseURL: URL
    private(set) var pageRecords: [Int: PageRecord] = [:]
    private(set) var completedPages: Set<Int> = []
    private(set) var stalePages: Set<Int> = []
    private(set) var totalPages: Int?

    // 由 pageRecords 聚合出的当前视图（纯字典合并，不触发 Markdown 解析）。
    private var entriesByFloor: [Int: ParsedFloorEntry] = [:]
    private var childrenByParent: [Int: [Int]] = [:]

    init(postID: String, baseURL: URL = NodeSeekSite.baseURL) {
        self.postID = postID
        self.baseURL = baseURL
    }

    /// 将单页详情解析为不可变的 `PageRecord`（纯函数，可在后台线程调用，每条评论仅解析一次）。
    static func parsePage(
        _ detail: PostDetail,
        postID: String,
        baseURL: URL = NodeSeekSite.baseURL,
        targetExtractor: TargetExtractor = CommentReplyRelationParser.extractTargets
    ) -> PageRecord? {
        guard detail.id == postID, !detail.isRestricted else { return nil }
        let page = max(1, detail.page)
        let nextPage = detail.pagination?.nextPage
        let isLastPage = detail.isLastPage && nextPage == nil
        let pageTotal = detail.totalPages ?? detail.pagination?.items.map(\.page).max()

        var entries: [ParsedFloorEntry] = []
        entries.reserveCapacity(detail.comments.count + 1)

        if page == 1,
           let bodyMarkdown = detail.visibleMarkdown,
           !bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let postBodyComment = Comment(
                id: "post-\(detail.id)-0",
                anchorID: "0",
                authorName: detail.authorName,
                isPoster: true,
                avatarURL: detail.avatarURL,
                authorProfileURL: detail.authorProfileURL,
                authorBadgeTexts: detail.authorBadgeTexts,
                floorText: "#0",
                createdAtText: detail.metadataText,
                contentHTML: detail.contentHTML,
                markdown: bodyMarkdown,
                hasVisibleMarkdown: true
            )
            entries.append(
                ParsedFloorEntry(
                    comment: postBodyComment,
                    floor: 0,
                    sourcePage: page,
                    isPrimarySource: true,
                    targets: []
                )
            )
        }

        for comment in detail.comments {
            guard let floor = CommentReplyRelationParser.floorNumber(for: comment) else { continue }
            let expectedPage = CommentComposerContentBuilder.commentPage(forFloor: floor)
            let isPrimary = !comment.isHot && expectedPage == page
            let targets = targetExtractor(comment.markdown, postID, floor, baseURL)
            entries.append(
                ParsedFloorEntry(
                    comment: comment,
                    floor: floor,
                    sourcePage: page,
                    isPrimarySource: isPrimary,
                    targets: targets
                )
            )
        }

        return PageRecord(
            page: page,
            entries: entries,
            nextPage: nextPage,
            isLastPage: isLastPage,
            totalPages: pageTotal
        )
    }

    /// 写入已在后台解析好的单页记录（只做轻量内存合并，不重复解析历史页 Markdown）。
    mutating func ingest(_ record: PageRecord) {
        let page = max(1, record.page)
        let previousRecord = pageRecords[page]
        pageRecords[page] = record
        completedPages.insert(page)
        stalePages.remove(page)

        if let pageTotal = record.totalPages {
            totalPages = max(totalPages ?? 0, pageTotal)
        } else if record.isLastPage {
            totalPages = max(totalPages ?? 0, page)
        }

        if let previousRecord, previousRecord.isLastPage, !record.isLastPage {
            stalePages.remove(page)
        }

        rebuildAggregatedView()
    }

    /// 同步解析并写入单页详情（便捷入口；主 App 调度走后台 `parsePage` + `ingest(record)`）。
    @discardableResult
    mutating func ingest(
        _ detail: PostDetail,
        targetExtractor: TargetExtractor = CommentReplyRelationParser.extractTargets
    ) -> Bool {
        guard let record = Self.parsePage(
            detail,
            postID: postID,
            baseURL: baseURL,
            targetExtractor: targetExtractor
        ) else {
            return false
        }
        ingest(record)
        return true
    }

    /// 本地发评成功或检测到回复增长时，把原末页标为待复查，以便下次扫描先复查末页再追新增页。
    mutating func markLastPageStaleForGrowth() {
        let confirmedLast = pageRecords.values
            .filter { $0.isLastPage }
            .map(\.page)
            .max()
        let targetPage = confirmedLast ?? completedPages.max()
        guard let targetPage else { return }
        stalePages.insert(targetPage)
        completedPages.remove(targetPage)
    }

    mutating func reset() {
        pageRecords.removeAll()
        completedPages.removeAll()
        stalePages.removeAll()
        totalPages = nil
        entriesByFloor.removeAll()
        childrenByParent.removeAll()
    }

    /// 计算下一步需要扫描的缺页：
    /// 1. 若焦点楼存在尚未加载的上游祖先页，优先补查该祖先页；
    /// 2. 上游祖先页就绪后，再从焦点楼所在页向后补齐直至已确认末页。
    func nextPageToScan(forRootFloor rootFloor: Int, fallbackRootComment: Comment? = nil) -> Int? {
        if let missingAncestorPage = nextMissingAncestorPage(
            forRootFloor: rootFloor,
            fallbackRootComment: fallbackRootComment
        ) {
            return missingAncestorPage
        }
        let startPage = CommentComposerContentBuilder.commentPage(forFloor: rootFloor)
        return nextPageToScan(startingFrom: startPage)
    }

    /// 查找上游祖先链里尚未扫描完成的页码（已扫描但父楼不存在时不重复请求）。
    func nextMissingAncestorPage(forRootFloor rootFloor: Int, fallbackRootComment: Comment? = nil) -> Int? {
        var visited = Set<Int>([rootFloor])
        var queue = directTargets(of: rootFloor, fallbackComment: fallbackRootComment)
        var cursor = 0
        var missingPages: [Int] = []
        let maxDepthNodes = 32

        while cursor < queue.count, visited.count <= maxDepthNodes {
            let targetFloor = queue[cursor]
            cursor += 1
            guard targetFloor >= 0, visited.insert(targetFloor).inserted else { continue }

            if let entry = entriesByFloor[targetFloor] {
                for parent in entry.targets where !visited.contains(parent) {
                    queue.append(parent)
                }
            } else {
                let page = CommentComposerContentBuilder.commentPage(forFloor: targetFloor)
                if !completedPages.contains(page) || stalePages.contains(page) {
                    missingPages.append(page)
                }
            }
        }

        // 优先补查离当前楼层最近的祖先页（页码较大者），让直接父楼最快显现。
        return missingPages.max()
    }

    func nextPageToScan(startingFrom startPage: Int) -> Int? {
        var page = max(1, startPage)
        var visited = Set<Int>()
        while visited.insert(page).inserted {
            guard completedPages.contains(page),
                  !stalePages.contains(page),
                  let record = pageRecords[page] else {
                return page
            }
            if record.isLastPage && record.nextPage == nil {
                return nil
            }
            if let next = record.nextPage, next > page {
                page = next
            } else {
                page += 1
            }
        }
        return nil
    }

    func isComplete(forRootFloor rootFloor: Int, fallbackRootComment: Comment? = nil) -> Bool {
        nextPageToScan(forRootFloor: rootFloor, fallbackRootComment: fallbackRootComment) == nil
    }

    func comment(forFloor floor: Int) -> Comment? {
        entriesByFloor[floor]?.comment
    }

    func directChildren(of floor: Int) -> [Int] {
        childrenByParent[floor] ?? []
    }

    private final class RawTreeNode {
        let entry: ParsedFloorEntry
        let parentFloor: Int
        let depth: Int
        var children: [RawTreeNode] = []

        init(entry: ParsedFloorEntry, parentFloor: Int, depth: Int) {
            self.entry = entry
            self.parentFloor = parentFloor
            self.depth = depth
        }
    }

    /// 以 `rootFloor` 为根构建当前对话快照（上方展示上游祖先链，下方按 DFS 展示层叠子楼）。
    func tree(forRootFloor rootFloor: Int, fallbackRootComment: Comment? = nil) -> ThreadedReplyTree {
        // 1. 收集上游祖先链（按楼号升序排列；相邻两条仅存在直接父子关系时才连竖线，避免互不相关的多父楼误连）。
        let rootTargets = directTargets(of: rootFloor, fallbackComment: fallbackRootComment)
        var visitedAncestors = Set<Int>([rootFloor])
        var queue = rootTargets
        var cursor = 0
        var collectedAncestorFloors: [Int] = []
        let maxAncestorCount = 32

        while cursor < queue.count, collectedAncestorFloors.count < maxAncestorCount {
            let floor = queue[cursor]
            cursor += 1
            guard floor >= 0, visitedAncestors.insert(floor).inserted else { continue }
            if let entry = entriesByFloor[floor] {
                collectedAncestorFloors.append(floor)
                for parent in entry.targets where !visitedAncestors.contains(parent) {
                    queue.append(parent)
                }
            }
        }

        let sortedAncestorFloors = collectedAncestorFloors.sorted()
        let ancestorFloorSet = Set(sortedAncestorFloors)
        var ancestors: [ThreadedAncestorNode] = []
        ancestors.reserveCapacity(sortedAncestorFloors.count)

        for (index, floor) in sortedAncestorFloors.enumerated() {
            guard let entry = entriesByFloor[floor] else { continue }
            let displayedParent = entry.targets.first { ancestorFloorSet.contains($0) }
            let connectsFromPrevious: Bool
            if index > 0 {
                let previousFloor = sortedAncestorFloors[index - 1]
                connectsFromPrevious = entry.targets.contains(previousFloor)
            } else {
                connectsFromPrevious = false
            }

            let connectsToNext: Bool
            if index + 1 < sortedAncestorFloors.count {
                let nextFloor = sortedAncestorFloors[index + 1]
                connectsToNext = entriesByFloor[nextFloor]?.targets.contains(floor) == true
            } else {
                connectsToNext = rootTargets.contains(floor)
            }

            ancestors.append(
                ThreadedAncestorNode(
                    comment: entry.comment,
                    floor: floor,
                    parentFloorInChain: displayedParent,
                    connectsFromPrevious: connectsFromPrevious,
                    connectsToNext: connectsToNext
                )
            )
        }
        let rootDisplayedParentFloor = rootTargets.first { ancestorFloorSet.contains($0) }
        let rootConnectsFromTop = ancestors.last?.connectsToNext == true

        // 2. 构建下游层叠回复树。
        var visited = Set<Int>([rootFloor])

        func buildChildren(of parentFloor: Int, depth: Int) -> [RawTreeNode] {
            var built: [RawTreeNode] = []
            for childFloor in childrenByParent[parentFloor] ?? [] {
                guard visited.insert(childFloor).inserted,
                      let entry = entriesByFloor[childFloor] else { continue }
                let raw = RawTreeNode(entry: entry, parentFloor: parentFloor, depth: depth)
                raw.children = buildChildren(of: childFloor, depth: depth + 1)
                built.append(raw)
            }
            return built
        }

        let topLevel = buildChildren(of: rootFloor, depth: 1)
        var nodes: [ThreadedReplyNode] = []

        func flatten(_ siblings: [RawTreeNode], ancestorContinuations: [Bool]) {
            for (offset, raw) in siblings.enumerated() {
                let isLast = offset == siblings.count - 1
                nodes.append(
                    ThreadedReplyNode(
                        comment: raw.entry.comment,
                        floor: raw.entry.floor,
                        parentFloor: raw.parentFloor,
                        depth: raw.depth,
                        ancestorContinuations: ancestorContinuations,
                        isLastSibling: isLast,
                        hasChildren: !raw.children.isEmpty
                    )
                )
                flatten(raw.children, ancestorContinuations: ancestorContinuations + [!isLast])
            }
        }

        flatten(topLevel, ancestorContinuations: [])

        return ThreadedReplyTree(
            rootFloor: rootFloor,
            rootComment: entriesByFloor[rootFloor]?.comment ?? fallbackRootComment,
            ancestors: ancestors,
            rootDisplayedParentFloor: rootDisplayedParentFloor,
            rootConnectsFromTop: rootConnectsFromTop,
            nodes: nodes,
            isComplete: isComplete(forRootFloor: rootFloor, fallbackRootComment: fallbackRootComment),
            totalPages: totalPages,
            completedPages: completedPages
        )
    }

    // MARK: - 纯内存聚合重建（不重复解析 Markdown）

    private func directTargets(of floor: Int, fallbackComment: Comment?) -> [Int] {
        if let entry = entriesByFloor[floor] {
            return entry.targets
        }
        guard let fallbackComment else { return [] }
        return CommentReplyRelationParser.extractTargets(
            from: fallbackComment.markdown,
            postID: postID,
            currentFloor: floor,
            baseURL: baseURL
        )
    }

    private mutating func rebuildAggregatedView() {
        var bestByFloor: [Int: ParsedFloorEntry] = [:]
        for page in pageRecords.keys.sorted() {
            guard let record = pageRecords[page] else { continue }
            for candidate in record.entries {
                if let existing = bestByFloor[candidate.floor] {
                    if shouldPrefer(candidate, over: existing) {
                        bestByFloor[candidate.floor] = candidate
                    }
                } else {
                    bestByFloor[candidate.floor] = candidate
                }
            }
        }

        var edges: [Int: Set<Int>] = [:]
        for entry in bestByFloor.values {
            for parentFloor in entry.targets {
                edges[parentFloor, default: []].insert(entry.floor)
            }
        }

        entriesByFloor = bestByFloor
        childrenByParent = edges.mapValues { $0.sorted() }
    }

    /// 正式所属页优先于首页热评副本；同级别下有原文优先于缺原文；若同一正式页更新，保留最新内容。
    private func shouldPrefer(_ candidate: ParsedFloorEntry, over existing: ParsedFloorEntry) -> Bool {
        if candidate.isPrimarySource != existing.isPrimarySource {
            return candidate.isPrimarySource
        }
        let candidateHasMarkdown = candidate.comment.markdown?.isEmpty == false
        let existingHasMarkdown = existing.comment.markdown?.isEmpty == false
        if candidateHasMarkdown != existingHasMarkdown {
            return candidateHasMarkdown
        }
        return candidate.sourcePage >= existing.sourcePage
    }
}
