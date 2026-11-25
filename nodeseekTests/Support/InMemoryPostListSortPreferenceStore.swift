//
//  InMemoryPostListSortPreferenceStore.swift
//  nodeseekTests
//

@testable import nodeseek

/// 测试用排序偏好，避免读写模拟器里 App 实际保存的排序。
final class InMemoryPostListSortPreferenceStore: PostListSortPreferenceStoring {
    var sortMode: PostListSortMode = .replyTime
    var hasSeenHomeSortHint = false
    var showsHomeControl: Bool = true
}
