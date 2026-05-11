//
//  FloatingControlPositionStore.swift
//  nodeseek
//
//  Created by Codex on 2026/5/11.
//

import CoreGraphics
import Foundation

enum FloatingControlPositionKeys {
    static let postListSortToggle = "floating.postList.sortToggle.position"
    static let postDetailReplyButton = "floating.postDetail.replyButton.position"
}

struct FloatingControlPosition: Codable, Equatable {
    let edgeRawValue: UInt
    let verticalOriginRatio: CGFloat
}

protocol FloatingControlPositionStoring {
    func position(forKey key: String) -> FloatingControlPosition?
    func save(_ position: FloatingControlPosition, forKey key: String)
}

final class UserDefaultsFloatingControlPositionStore: FloatingControlPositionStoring {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func position(forKey key: String) -> FloatingControlPosition? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FloatingControlPosition.self, from: data)
    }

    func save(_ position: FloatingControlPosition, forKey key: String) {
        guard let data = try? JSONEncoder().encode(position) else { return }
        userDefaults.set(data, forKey: key)
    }
}
