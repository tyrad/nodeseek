//
//  PostDetailEntity.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

struct PostDetailRequest {
    let postID: String
    let page: Int
}

struct PostDetailResponse {
    let detail: PostDetail
}
