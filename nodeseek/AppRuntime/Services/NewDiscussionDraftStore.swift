//
//  NewDiscussionDraftStore.swift
//  nodeseek
//

import Foundation

protocol NewDiscussionDraftStoring: AnyObject {
    func load() -> NewDiscussionDraft?
    func save(_ draft: NewDiscussionDraft)
    func clear()
}

/// 本机只保存一份发帖草稿。
final class UserDefaultsNewDiscussionDraftStore: NewDiscussionDraftStoring {
    private let userDefaults: UserDefaults
    private let storageKey: String

    init(userDefaults: UserDefaults = .standard, storageKey: String = "com.nodeseek.new-discussion-draft") {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func load() -> NewDiscussionDraft? {
        guard let data = userDefaults.data(forKey: storageKey) else { return nil }
        do {
            return try JSONDecoder().decode(NewDiscussionDraft.self, from: data)
        } catch {
            AppLog.warning(.postList, "发帖草稿解码失败，已忽略: error=\(error.localizedDescription)")
            return nil
        }
    }

    func save(_ draft: NewDiscussionDraft) {
        do {
            userDefaults.set(try JSONEncoder().encode(draft), forKey: storageKey)
        } catch {
            AppLog.warning(.postList, "发帖草稿保存失败: error=\(error.localizedDescription)")
        }
    }

    func clear() {
        userDefaults.removeObject(forKey: storageKey)
    }
}
