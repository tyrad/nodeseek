//
//  NodeSeekSite.swift
//  nodeseek
//
//  Created by Codex on 2026/5/2.
//

import Foundation

enum NodeSeekSite {
    nonisolated static let baseURL = URL(string: "https://www.nodeseek.com")!
    nonisolated static let rootHost = "nodeseek.com"
    nonisolated static let allowedCookieDomains = [rootHost]

    nonisolated static var referer: String {
        baseURL.appendingPathComponent("").absoluteString
    }

    nonisolated static var loginURL: URL {
        baseURL.appendingPathComponent("signIn.html")
    }

    nonisolated static var defaultPostListURL: URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("page-1"),
            resolvingAgainstBaseURL: true
        )
        components?.queryItems = [URLQueryItem(name: "sortBy", value: "replyTime")]
        return components?.url ?? baseURL.appendingPathComponent("page-1")
    }

    nonisolated static func postURL(id: String, page: Int) -> URL {
        baseURL.appendingPathComponent("post-\(id)-\(max(1, page))")
    }

    nonisolated static func isNodeSeekHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == rootHost || host.hasSuffix(".\(rootHost)")
    }
}
