//
//  PostListNotificationUnreadCountInteractor.swift
//  nodeseek
//
//  Created by Codex on 2026/6/8.
//

import Foundation

final class PostListNotificationUnreadCountInteractor: PostListNotificationUnreadCountInteractorProtocol {
    private let client: NodeSeekNotificationClientProtocol

    init(client: NodeSeekNotificationClientProtocol? = nil) {
        self.client = client ?? NodeSeekNotificationClient()
    }

    func loadUnreadCount() async throws -> NodeSeekNotificationUnreadCount {
        try await client.loadUnreadCount()
    }
}
