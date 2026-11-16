//
//  SeekMailMarkAllReadJob.swift
//  nodeseek
//

import Foundation

/// 「全部标为已读」：seek.li 没有批量接口，只能逐封标记。
/// 主动限速，给用户的手动操作留额度；被限流时等一会儿自动继续。
final class SeekMailMarkAllReadJob {
    enum State: Equatable {
        case idle
        case running(done: Int, total: Int)
        /// 额度用完，等到这个时间再继续。
        case waiting(until: Date, done: Int, total: Int)
        case finished(succeeded: Int, failed: Int)
        case stopped(done: Int, total: Int)
    }

    /// 一次最多处理这么多封，避免长时间占满额度。
    static let maxPerRun = 200
    /// 每封之间的间隔：约 24 次/分钟，seek.li 每次扣 2，留出余量。
    static let interval: TimeInterval = 2.5
    /// 剩余额度低于这个数就先等窗口重置。
    static let quotaReserve = 12
    static let rateLimitWait: TimeInterval = 40

    private(set) var state: State = .idle {
        didSet { onChange?(state) }
    }
    var onChange: ((State) -> Void)?
    /// 每成功一封回调一次，列表和未读数据此就地更新。
    var onMarked: ((SeekUnreadMail) -> Void)?

    private let provider: SeekMailProvider<SeekMailAPI>
    private let sleep: (TimeInterval) async throws -> Void
    private let now: () -> Date
    private var task: Task<Void, Never>?
    private var failed: [SeekUnreadMail] = []

    init(provider: SeekMailProvider<SeekMailAPI>,
         sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
         now: @escaping () -> Date = Date.init) {
        self.provider = provider
        self.sleep = sleep
        self.now = now
    }

    deinit { task?.cancel() }

    var isActive: Bool {
        switch state {
        case .running, .waiting: return true
        default: return false
        }
    }

    /// 只取未读的 ID，每页 50 封；mailboxID 为 nil 表示全部邮箱。返回值包含是否还有超出上限的部分。
    func collect(mailboxID: Int64?) async throws -> (mails: [SeekUnreadMail], total: Int) {
        var result: [SeekUnreadMail] = []
        var cursor: String?
        repeat {
            let page = try await provider.unreadMails(limit: 50, cursor: cursor)
            result += page.mails.filter { mailboxID == nil || $0.mailboxId == mailboxID }
            cursor = page.page?.hasMore == true ? page.page?.nextCursor : nil
        } while cursor != nil && result.count <= Self.maxPerRun
        return (Array(result.prefix(Self.maxPerRun)), result.count)
    }

    func start(_ mails: [SeekUnreadMail]) {
        guard isActive == false, mails.isEmpty == false else { return }
        failed = []
        task = Task { [weak self] in await self?.run(mails) }
    }

    func retryFailed() {
        start(failed)
    }

    func stop() {
        guard isActive else { return }
        task?.cancel()
    }

    private func run(_ mails: [SeekUnreadMail]) async {
        let total = mails.count
        var done = 0
        state = .running(done: 0, total: total)
        for mail in mails {
            do {
                try await waitForQuota(done: done, total: total)
                try await mark(mail, done: done, total: total)
                onMarked?(mail)
            } catch is CancellationError {
                state = .stopped(done: done, total: total)
                return
            } catch {
                failed.append(mail)
            }
            done += 1
            state = .running(done: done, total: total)
            if done < total {
                do { try await sleep(Self.interval) } catch {
                    state = .stopped(done: done, total: total)
                    return
                }
            }
        }
        state = .finished(succeeded: total - failed.count, failed: failed.count)
    }

    /// 最近一分钟内看到的剩余额度太低，就等到窗口过去。
    private func waitForQuota(done: Int, total: Int) async throws {
        guard let limit = provider.rateLimit, limit.remaining < Self.quotaReserve else { return }
        let resumeAt = limit.observedAt.addingTimeInterval(60)
        guard resumeAt > now() else { return }
        state = .waiting(until: resumeAt, done: done, total: total)
        try await sleep(resumeAt.timeIntervalSince(now()))
        state = .running(done: done, total: total)
    }

    /// 被限流时等一会儿重试同一封，最多 3 次；其他错误算失败。
    private func mark(_ mail: SeekUnreadMail, done: Int, total: Int) async throws {
        var attempts = 0
        while true {
            try Task.checkCancellation()
            do {
                try await provider.markRead(id: mail.id, read: true)
                return
            } catch SeekMailError.rateLimited where attempts < 3 {
                attempts += 1
                let resumeAt = now().addingTimeInterval(Self.rateLimitWait)
                state = .waiting(until: resumeAt, done: done, total: total)
                try await sleep(Self.rateLimitWait)
                state = .running(done: done, total: total)
            }
        }
    }
}
