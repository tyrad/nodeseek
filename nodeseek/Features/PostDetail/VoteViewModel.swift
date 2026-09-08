import Foundation

@MainActor
final class VoteViewModel {
    let id: Int
    private let service: NodeSeekVoteServing
    private(set) var vote: NodeSeekVote?
    private(set) var selected: Set<Int> = []
    private(set) var busy = false
    private(set) var message: String?
    private(set) var requiresRefresh = false
    var onChange: (() -> Void)?
    private var generation = 0

    init(id: Int, service: NodeSeekVoteServing) {
        self.id = id
        self.service = service
    }

    var canSubmit: Bool { !busy && !requiresRefresh && vote?.accepts(selected) == true }

    func select(_ itemID: Int) {
        guard !busy, !requiresRefresh, let vote, vote.canSubmit,
              vote.items.contains(where: { $0.vote_item_id == itemID }) else { return }
        if vote.multiple {
            if selected.contains(itemID) { selected.remove(itemID) } else { selected.insert(itemID) }
        } else { selected = [itemID] }
        onChange?()
    }

    func resetSession() {
        generation += 1
        vote = nil
        selected = []
        busy = false
        message = nil
        requiresRefresh = true
        onChange?()
    }

    func refresh() async {
        guard !busy else { return }
        let current = generation
        busy = true
        message = nil
        onChange?()
        do {
            let result = try await service.load(id: id)
            guard current == generation else { return }
            apply(result)
        } catch {
            guard current == generation else { return }
            requiresRefresh = true
            message = error is CancellationError ? "登录状态已改变，请重新进入页面。" : error.localizedDescription
        }
        busy = false
        onChange?()
    }

    func submit() async {
        guard canSubmit else { return }
        let current = generation
        busy = true
        message = "正在提交…"
        onChange?()
        var submissionError: Error?
        do { try await service.submit(id: id, ids: selected) }
        catch { submissionError = error }
        guard current == generation else { return }
        // 写请求超时也可能已生效。重新读取完成前始终禁止再次提交。
        requiresRefresh = true
        do {
            let result = try await service.load(id: id)
            guard current == generation else { return }
            apply(result)
            message = result.hasVoted ? "已投票" : (submissionError?.localizedDescription ?? "已提交，请稍后重新进入页面确认结果。")
            if submissionError == nil && !result.hasVoted { requiresRefresh = true }
        } catch {
            guard current == generation else { return }
            message = "提交结果尚未确认，请重新进入页面后查看。"
        }
        busy = false
        onChange?()
    }

    private func apply(_ result: NodeSeekVote) {
        vote = result
        selected = result.hasVoted ? result.selectedIDs : selected.intersection(Set(result.items.map(\.vote_item_id)))
        requiresRefresh = false
    }
}
