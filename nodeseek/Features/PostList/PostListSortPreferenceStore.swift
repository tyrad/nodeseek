//
//  PostListSortPreferenceStore.swift
//  nodeseek
//

import Foundation

/// 帖子列表排序偏好：所有分类共用一个排序方式，重启后沿用上次选择。
protocol PostListSortPreferenceStoring: AnyObject {
    var sortMode: PostListSortMode { get set }
    var showsHomeControl: Bool { get set }
    var hasSeenHomeSortHint: Bool { get set }
}

final class PostListSortPreferenceStore: PostListSortPreferenceStoring {
    static let shared = PostListSortPreferenceStore()

    private let userDefaults: UserDefaults
    private let storageKey: String
    private let showsHomeControlStorageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "postList.sortMode",
        showsHomeControlStorageKey: String = "postList.showsSortControl"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.showsHomeControlStorageKey = showsHomeControlStorageKey
    }

    var showsHomeControl: Bool {
        get { userDefaults.object(forKey: showsHomeControlStorageKey) as? Bool ?? true }
        set { userDefaults.set(newValue, forKey: showsHomeControlStorageKey) }
    }

    // 提示在本次启动内只展示一次。
    var hasSeenHomeSortHint = false

    var sortMode: PostListSortMode {
        get {
            userDefaults.string(forKey: storageKey).flatMap(PostListSortMode.init(rawValue:)) ?? .replyTime
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: storageKey)
        }
    }
}
