//
//  HTMLClient.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

protocol HTMLClient: Sendable {
    func get(_ url: URL) async throws -> HTMLResponse
    func post(_ url: URL, formFields: [String: String]) async throws -> HTMLResponse
}
