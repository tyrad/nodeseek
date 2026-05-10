//
//  ImageURLResolver.swift
//  nodeseek
//
//  Created by Codex on 2026/5/9.
//

import Foundation

enum ImageURLResolver {
    static let defaultBaseURL = NodeSeekSite.baseURL

    static func resolve(
        _ rawValue: String?,
        baseURL: URL = defaultBaseURL
    ) -> URL? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return secureImageURL(absolute)
        }
        guard let resolved = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL else { return nil }
        return secureImageURL(resolved)
    }

    static func resolve(
        _ url: URL?,
        baseURL: URL = defaultBaseURL
    ) -> URL? {
        guard let url else { return nil }
        if url.scheme != nil {
            return secureImageURL(url)
        }
        guard let resolved = URL(string: url.relativeString, relativeTo: baseURL)?.absoluteURL else { return nil }
        return secureImageURL(resolved)
    }

    private static func secureImageURL(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.scheme = "https"
        if components.port == 80 {
            components.port = nil
        }
        return components.url ?? url
    }
}
