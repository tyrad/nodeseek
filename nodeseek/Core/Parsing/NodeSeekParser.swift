//
//  NodeSeekParser.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

protocol NodeSeekParser: Sendable {
    func parseAccount(html: String) throws -> AccountResponse
    func parsePostList(html: String) throws -> [PostSummary]
    func parsePostDetail(html: String, url: URL) throws -> PostDetail
    func parseReplyForm(html: String, pageURL: URL) throws -> ReplyForm
    func parseCheckInState(html: String, pageURL: URL) throws -> CheckInState
}
