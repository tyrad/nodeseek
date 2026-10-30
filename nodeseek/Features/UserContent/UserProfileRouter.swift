//
//  UserProfileRouter.swift
//  nodeseek
//
//  Created by Claude on 2026/10/30.
//

import UIKit

/// `/space/<uid>` 统一入口：能解析出 uid 走原生个人页，否则回落网页。
enum UserProfileRouter {
    static func nativeUID(for profileURL: URL) -> Int? {
        if profileURL.host != nil, !NodeSeekSite.isNodeSeekHost(profileURL) {
            return nil
        }
        guard profileURL.path.hasPrefix("/space/") else { return nil }
        return NodeSeekUserIDResolver.uid(from: profileURL)
    }

    @MainActor
    static func makeViewController(profileURL: URL, title: String = "用户主页") -> UIViewController {
        if let uid = nativeUID(for: profileURL) {
            return UserProfileViewController(uid: uid)
        }
        return UserInfoWebViewController(profileURL: profileURL, title: title)
    }
}
