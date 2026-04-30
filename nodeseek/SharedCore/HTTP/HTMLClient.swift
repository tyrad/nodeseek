//
//  HTMLClient.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

struct HTMLResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let finalURL: URL
    let html: String
}

protocol HTMLClient: Sendable {
    func get(_ url: URL) async throws -> HTMLResponse
    func post(_ url: URL, formFields: [String: String]) async throws -> HTMLResponse
}
