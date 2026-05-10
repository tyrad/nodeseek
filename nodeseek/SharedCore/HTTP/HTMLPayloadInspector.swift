//
//  HTMLPayloadInspector.swift
//  nodeseek
//
//  Created by Codex on 2026/5/10.
//

import Foundation

enum HTMLPayloadInspector {
    private static let prefixByteLimit = 2048

    static func looksLikeHTMLPayload(_ data: Data) -> Bool {
        looksLikeHTMLDocument(data) || containsCloudflareChallenge(data)
    }

    static func looksLikeHTMLDocument(_ data: Data) -> Bool {
        guard let prefix = normalizedPrefix(from: data) else { return false }
        return containsHTMLDocumentMarker(prefix)
    }

    static func containsCloudflareChallenge(_ data: Data) -> Bool {
        guard let prefix = normalizedPrefix(from: data) else { return false }
        return containsCloudflareChallenge(prefix)
    }

    static func containsCloudflareChallenge(_ html: String) -> Bool {
        let normalized = normalizedHTML(html)
        return normalized.contains("just a moment")
            || normalized.contains("window._cf_chl_opt")
            || normalized.contains("/cdn-cgi/challenge-platform/")
            || normalized.contains("challenge-platform")
            || normalized.contains("cf_chl")
            || normalized.contains("enable javascript and cookies to continue")
    }

    private static func normalizedPrefix(from data: Data) -> String? {
        guard data.isEmpty == false else { return nil }
        return String(data: data.prefix(prefixByteLimit), encoding: .utf8).map(normalizedHTML)
    }

    private static func normalizedHTML(_ html: String) -> String {
        html.lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static func containsHTMLDocumentMarker(_ html: String) -> Bool {
        html.contains("<html")
            || html.contains("<!doctype html")
            || html.contains("<body")
    }
}
