//
//  AvatarImageRequest.swift
//  nodeseek
//
//  Created by Codex on 2026/5/9.
//

import UIKit

struct AvatarImageRequest {
    let url: URL?
    let requestID: String

    @MainActor
    func into(
        _ imageView: UIImageView,
        completion: AvatarImageLoader.Completion? = nil
    ) {
        AvatarImageLoader.shared.loadAvatar(
            into: imageView,
            postID: requestID,
            avatarURL: url,
            completion: completion
        )
    }
}
