//
//  PostListSortPreferenceStore.swift
//  nodeseek
//

import Foundation

/// 帖子列表排序偏好：所有分类共用一个排序方式，重启后沿用上次选择。
protocol PostListSortPreferenceStoring: AnyObject {
    var sortMode: PostListSortMode { get set }
}

final class PostListSortPreferenceStore: PostListSortPreferenceStoring {
    static let shared = PostListSortPreferenceStore()

    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "postList.sortMode"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    var sortMode: PostListSortMode {
        get {
            userDefaults.string(forKey: storageKey).flatMap(PostListSortMode.init(rawValue:)) ?? .replyTime
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: storageKey)
        }
    }
}
