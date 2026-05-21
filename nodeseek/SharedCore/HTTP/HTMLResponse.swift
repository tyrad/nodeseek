//
//  HTMLResponse.swift
//  nodeseek
//
//  Created by Codex on 2026/5/21.
//

import Foundation

struct HTMLResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let finalURL: URL
    let html: String
}
