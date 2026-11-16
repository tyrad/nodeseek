//
//  SeekMailInboxModel.swift
//  nodeseek
//

import Foundation

/// 列表顶部的文件夹 tab。「已发送」不放：用 API 发出的邮件不在里面。
nonisolated enum SeekMailFolderScope: Hashable, Sendable {
    case inbox
    case spam
    case trash
    case custom(Int64)

    var storageValue: String {
        switch self {
        case .inbox: return "inbox"
        case .spam: return "spam"
        case .trash: return "trash"
        case .custom(let id): return "folder:\(id)"
        }
    }

    init?(storageValue: String) {
        switch storageValue {
        case "inbox": self = .inbox
        case "spam": self = .spam
        case "trash": self = .trash
        default:
            guard storageValue.hasPrefix("folder:"), let id = Int64(storageValue.dropFirst("folder:".count)) else { return nil }
            self = .custom(id)
        }
    }

    func apply(to query: inout SeekMailListQuery) {
        switch self {
        case .inbox: query.folder = .inbox
        case .spam: query.folder = .spam
        case .trash: query.folder = .trash
        case .custom(let id): query.folderID = id
        }
    }
}

/// 记住上次选中的邮箱、文件夹和最近打开的邮箱。
final class SeekMailSelectionStore {
    private let defaults: UserDefaults
    private enum Key {
        static let mailbox = "seekMail.selectedMailboxID"
        static let scope = "seekMail.selectedScope"
        static let recents = "seekMail.recentMailboxIDs"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var mailboxID: Int64? {
        get { (defaults.object(forKey: Key.mailbox) as? NSNumber)?.int64Value }
        set { defaults.set(newValue.map { NSNumber(value: $0) }, forKey: Key.mailbox) }
    }

    var scope: SeekMailFolderScope {
        get { defaults.string(forKey: Key.scope).flatMap(SeekMailFolderScope.init(storageValue:)) ?? .inbox }
        set { defaults.set(newValue.storageValue, forKey: Key.scope) }
    }

    var recentMailboxIDs: [Int64] {
        (defaults.array(forKey: Key.recents) as? [NSNumber])?.map(\.int64Value) ?? []
    }

    func recordRecent(_ id: Int64) {
        var ids = recentMailboxIDs.filter { $0 != id }
        ids.insert(id, at: 0)
        defaults.set(ids.prefix(3).map { NSNumber(value: $0) }, forKey: Key.recents)
    }

    func clear() {
        [Key.mailbox, Key.scope, Key.recents].forEach(defaults.removeObject(forKey:))
    }
}

/// 邮件列表的状态：邮箱、文件夹、分页、搜索和延迟删除。界面只负责展示。
final class SeekMailInboxModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    static let pageSize = 20
    /// 验证码卡片只放这段时间内收到的邮件。
    static let codeFreshness: TimeInterval = 15 * 60

    let provider: SeekMailProvider<SeekMailAPI>
    let selectionStore: SeekMailSelectionStore
    private let deleteDelay: TimeInterval
    private let cache: SeekMailListCache?
    /// 快照按 Key 指纹隔离，取不到 Key 时不读写快照。
    private let cacheKey: () -> String?

    private(set) var mailboxes: [SeekMailbox] = []
    private(set) var names: [Int64: SeekMailboxDisplay] = [:]
    private(set) var folders: [SeekMailFolder] = []
    private(set) var selectedMailboxID: Int64?
    private(set) var scope: SeekMailFolderScope = .inbox
    private(set) var searchText = ""
    private(set) var phase: Phase = .loading
    private(set) var isLoadingMore = false
    private(set) var hasMore = false
    private(set) var rateLimitedUntil: Date?

    private var allMails: [SeekMail] = []
    private var pendingDeletes: [Int64: Task<Void, Never>] = [:]
    private var loadTask: Task<Void, Never>?
    /// 切换邮箱、文件夹或搜索后，旧请求的结果直接丢弃。
    private var generation = 0

    var onChange: (() -> Void)?
    /// 401：入口页清掉 Key 并回到绑定页。
    var onUnauthorized: (() -> Void)?
    /// 列表已有内容时的失败，用 toast 提示而不是整页报错。
    var onMessage: ((String) -> Void)?

    init(
        provider: SeekMailProvider<SeekMailAPI>,
        selectionStore: SeekMailSelectionStore = SeekMailSelectionStore(),
        deleteDelay: TimeInterval = 4,
        cache: SeekMailListCache? = nil,
        cacheKey: @escaping () -> String? = { nil }
    ) {
        self.provider = provider
        self.selectionStore = selectionStore
        self.deleteDelay = deleteDelay
        self.cache = cache
        self.cacheKey = cacheKey
        selectedMailboxID = selectionStore.mailboxID
        scope = selectionStore.scope
    }

    deinit {
        loadTask?.cancel()
    }

    // MARK: - 派生数据

    /// 已排队删除的邮件先从列表隐藏。
    var mails: [SeekMail] {
        allMails.filter { pendingDeletes[$0.id] == nil }
    }

    var selectedMailbox: SeekMailbox? {
        selectedMailboxID.flatMap { id in mailboxes.first { $0.id == id } }
    }

    var isTrash: Bool { scope == .trash }

    /// 没有能发信的邮箱时不显示写信入口。
    var canCompose: Bool { mailboxes.contains { $0.canSendMail } }
    var isSearching: Bool { searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }

    /// 「全部邮箱」时摘要开头标出收件邮箱。
    var showsRecipientMailbox: Bool { selectedMailboxID == nil }

    var selectionTitle: String {
        guard let id = selectedMailboxID else { return "全部邮箱" }
        return names[id]?.title ?? "邮箱"
    }

    var scopeTitle: String { title(for: scope) }

    func title(for scope: SeekMailFolderScope) -> String {
        switch scope {
        case .inbox: return "收件箱"
        case .spam: return "垃圾邮件"
        case .trash: return "回收站"
        case .custom(let id):
            guard let folder = folders.first(where: { $0.id == id }) else { return "文件夹" }
            return [folder.icon, folder.name].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " ")
        }
    }

    var scopes: [SeekMailFolderScope] {
        [.inbox, .spam, .trash] + folders.map { .custom($0.id) }
    }

    /// 当前范围内 15 分钟内最新的一封带验证码的邮件；搜索时不显示。
    func latestCodeMail(now: Date = Date()) -> SeekMail? {
        guard isSearching == false, isTrash == false else { return nil }
        return mails
            .filter { mail in
                guard mail.verificationCode != nil, let date = mail.receivedAt else { return false }
                return now.timeIntervalSince(date) <= Self.codeFreshness
            }
            .max { ($0.receivedAt ?? .distantPast) < ($1.receivedAt ?? .distantPast) }
    }

    func mail(id: Int64) -> SeekMail? {
        allMails.first { $0.id == id }
    }

    // MARK: - 加载

    /// 首次进入：邮箱和文件夹拿到后再加载邮件。
    func start() {
        phase = .loading
        restoreSnapshot()
        onChange?()
        generation += 1
        let token = generation
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let mailboxRequest = provider.mailboxes()
                // 文件夹没有也能用，权限不足时不影响收件箱
                async let folderRequest: [SeekMailFolder]? = try? provider.folders()
                let (mailboxes, folders) = try await (mailboxRequest, folderRequest)
                guard token == generation else { return }
                applyMailboxes(mailboxes, folders: folders ?? [])
                if let key = cacheKey() { cache?.saveMailboxes(mailboxes, folders: folders ?? [], for: key) }
                try await fetchFirstPage(token: token)
            } catch {
                guard token == generation else { return }
                handle(error)
            }
        }
    }

    func reload() {
        guard mailboxes.isEmpty == false else {
            start()
            return
        }
        generation += 1
        let token = generation
        if allMails.isEmpty { phase = .loading }
        onChange?()
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await fetchFirstPage(token: token)
            } catch {
                guard token == generation else { return }
                handle(error)
            }
        }
    }

    func loadMoreIfNeeded() {
        guard hasMore, isLoadingMore == false, phase == .loaded else { return }
        isLoadingMore = true
        let token = generation
        let offset = allMails.count
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let list = try await provider.mails(query(offset: offset))
                guard token == generation else { return }
                let known = Set(allMails.map(\.id))
                allMails += list.mails.filter { known.contains($0.id) == false }
                hasMore = Self.hasMore(list, received: list.mails.count, offset: offset)
                isLoadingMore = false
                onChange?()
            } catch {
                guard token == generation else { return }
                isLoadingMore = false
                handle(error)
            }
        }
    }

    func selectMailbox(_ id: Int64?) {
        guard id != selectedMailboxID else { return }
        selectedMailboxID = id
        selectionStore.mailboxID = id
        if let id { selectionStore.recordRecent(id) }
        resetAndReload()
    }

    func selectScope(_ scope: SeekMailFolderScope) {
        guard scope != self.scope else { return }
        self.scope = scope
        selectionStore.scope = scope
        resetAndReload()
    }

    func setSearchText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != searchText.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        searchText = text
        resetAndReload()
    }

    private func resetAndReload() {
        commitPendingDeletes()
        allMails = []
        hasMore = false
        isLoadingMore = false
        // 切到看过的范围时先显示上次的内容
        if isSearching == false, let key = cacheKey(), let cached = cache?.mails(for: key, page: currentPageKey) {
            allMails = cached
            phase = .loaded
        }
        reload()
    }

    private var currentPageKey: String {
        SeekMailListCache.pageKey(mailboxID: selectedMailboxID, scope: scope)
    }

    /// 先显示上次的邮箱和第一页，网络回来后再替换。
    private func restoreSnapshot() {
        guard let key = cacheKey(), let cache, let saved = cache.mailboxes(for: key) else { return }
        applyMailboxes(saved.mailboxes, folders: saved.folders)
        if let mails = cache.mails(for: key, page: currentPageKey) {
            allMails = mails
            phase = .loaded
        }
    }

    private func applyMailboxes(_ mailboxes: [SeekMailbox], folders: [SeekMailFolder]) {
        self.mailboxes = mailboxes
        self.folders = folders.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
        names = SeekMailboxNaming.displays(for: mailboxes)
        // 记住的邮箱或文件夹已被删掉，回到默认
        if let id = selectedMailboxID, mailboxes.contains(where: { $0.id == id }) == false {
            selectedMailboxID = nil
            selectionStore.mailboxID = nil
        }
        if case .custom(let id) = scope, folders.contains(where: { $0.id == id }) == false {
            scope = .inbox
            selectionStore.scope = .inbox
        }
    }

    private func fetchFirstPage(token: Int) async throws {
        let list = try await provider.mails(query(offset: 0))
        guard token == generation else { return }
        allMails = list.mails
        hasMore = Self.hasMore(list, received: list.mails.count, offset: 0)
        phase = .loaded
        if isSearching == false, let key = cacheKey() {
            cache?.saveMails(list.mails, for: key, page: currentPageKey)
        }
        clearRateLimitIfExpired()
        onChange?()
    }

    private func query(offset: Int) -> SeekMailListQuery {
        var query = SeekMailListQuery(mailboxID: selectedMailboxID, limit: Self.pageSize, offset: offset)
        scope.apply(to: &query)
        query.search = isSearching ? searchText : nil
        return query
    }

    private static func hasMore(_ list: SeekMailList, received: Int, offset: Int) -> Bool {
        if let pagination = list.pagination { return offset + received < pagination.total && received > 0 }
        return received >= pageSize
    }

    private func clearRateLimitIfExpired() {
        if let until = rateLimitedUntil, until <= Date() { rateLimitedUntil = nil }
    }

    private func handle(_ error: Error) {
        if error is CancellationError { return }
        let mailError = error as? SeekMailError
        if case .unauthorized? = mailError {
            onUnauthorized?()
            return
        }
        if case .rateLimited(let resetAt)? = mailError {
            rateLimitedUntil = resetAt ?? Date().addingTimeInterval(60)
        }
        let message = mailError?.userMessage ?? "加载失败，请稍后重试"
        if allMails.isEmpty, mailboxes.isEmpty || phase != .loaded {
            phase = .failed(message)
        } else {
            phase = .loaded
            if case .rateLimited? = mailError {} else { onMessage?(message) }
        }
        onChange?()
    }

    // MARK: - 操作（先改本地，失败再改回）

    func setRead(_ id: Int64, read: Bool, silent: Bool = false) {
        guard let original = mail(id: id), original.isRead != read else { return }
        update(id) { $0.isRead = read }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await provider.markRead(id: id, read: read)
            } catch {
                update(id) { $0.isRead = original.isRead }
                if silent == false { report(error) }
            }
        }
    }

    /// 打开详情时标已读，失败不提示；不在列表里的邮件直接发请求。
    func markOpened(_ id: Int64) {
        if let mail = mail(id: id) {
            if mail.isRead == false { setRead(id, read: true, silent: true) }
            return
        }
        Task { [provider] in try? await provider.markRead(id: id, read: true) }
    }

    func setFlagged(_ id: Int64, flagged: Bool) {
        guard let original = mail(id: id), original.isFlagged != flagged else { return }
        update(id) { $0.isFlagged = flagged }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await provider.markFlagged(id: id, flagged: flagged)
            } catch {
                update(id) { $0.isFlagged = original.isFlagged }
                report(error)
            }
        }
    }

    /// folderID 为 nil 表示移回收件箱。移走后不再属于当前文件夹，从列表去掉。
    func move(_ id: Int64, toFolderID folderID: Int64?) {
        guard let index = allMails.firstIndex(where: { $0.id == id }) else { return }
        let removed = allMails.remove(at: index)
        onChange?()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await provider.moveMail(id: id, folderID: folderID)
            } catch {
                allMails.insert(removed, at: min(index, allMails.count))
                onChange?()
                report(error)
            }
        }
    }

    /// 回收站里的邮件接口无法恢复，所以先隐藏，等一会儿再真正删除，期间可撤销。
    func scheduleDelete(_ id: Int64) {
        guard isTrash == false, mail(id: id) != nil, pendingDeletes[id] == nil else { return }
        let delay = deleteDelay
        pendingDeletes[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard Task.isCancelled == false else { return }
            await self?.performDelete(id)
        }
        onChange?()
    }

    var hasPendingDeletes: Bool { pendingDeletes.isEmpty == false }

    func undoDelete(_ id: Int64) {
        guard let task = pendingDeletes.removeValue(forKey: id) else { return }
        task.cancel()
        onChange?()
    }

    /// 离开页面、切换范围或 App 进入后台时，不再等待，立即删除。
    func commitPendingDeletes() {
        let ids = Array(pendingDeletes.keys)
        for id in ids {
            pendingDeletes[id]?.cancel()
            Task { [weak self] in await self?.performDelete(id) }
        }
    }

    private func performDelete(_ id: Int64) async {
        guard pendingDeletes[id] != nil else { return }
        do {
            try await provider.deleteMail(id: id)
            pendingDeletes[id] = nil
            allMails.removeAll { $0.id == id }
            onChange?()
        } catch {
            // 删除失败，邮件重新出现
            pendingDeletes[id] = nil
            onChange?()
            report(error)
        }
    }

    private func update(_ id: Int64, _ change: (inout SeekMail) -> Void) {
        guard let index = allMails.firstIndex(where: { $0.id == id }) else { return }
        change(&allMails[index])
        onChange?()
    }

    private func report(_ error: Error) {
        if case .unauthorized? = error as? SeekMailError {
            onUnauthorized?()
            return
        }
        onMessage?((error as? SeekMailError)?.userMessage ?? "操作失败，请稍后重试")
    }
}
