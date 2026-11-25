//
//  NodeSeekCookieClassifier.swift
//  nodeseek
//

import Foundation

nonisolated enum NodeSeekCookieCategory: Equatable, Sendable {
    case accountSession
    case cloudflare
    case sitePreference
    case external
}

/// 区分 NodeSeek 账号会话 Cookie 与 Cloudflare 过盾 / 站点偏好 Cookie。
/// 采用排除法识别账号会话 Cookie，避免硬编码站点登录 Cookie 名并在站点调整时漏存。
enum NodeSeekCookieClassifier {
    private nonisolated static let cloudflareExactNames: Set<String> = [
        "cf_clearance",
        "__cf_bm",
        "_cfuvid",
        "__cflb"
    ]

    private nonisolated static let cloudflarePrefixes: [String] = [
        "cf_chl_"
    ]

    private nonisolated static let sitePreferenceNames: Set<String> = [
        "colorscheme",
        "sortby",
        "hmti_"
    ]

    nonisolated static func isAllowedDomain(
        _ domain: String,
        allowedDomains: [String] = NodeSeekSite.allowedCookieDomains
    ) -> Bool {
        let normalizedDomain = domain
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        guard normalizedDomain.isEmpty == false else { return false }
        return allowedDomains.contains { allowedDomain in
            let normalizedAllowed = allowedDomain
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .lowercased()
            return normalizedDomain == normalizedAllowed
                || normalizedDomain.hasSuffix(".\(normalizedAllowed)")
        }
    }

    nonisolated static func classify(
        name: String,
        domain: String,
        allowedDomains: [String] = NodeSeekSite.allowedCookieDomains
    ) -> NodeSeekCookieCategory {
        guard isAllowedDomain(domain, allowedDomains: allowedDomains) else {
            return .external
        }
        let lowercasedName = name.lowercased()
        if cloudflareExactNames.contains(lowercasedName)
            || cloudflarePrefixes.contains(where: { lowercasedName.hasPrefix($0) }) {
            return .cloudflare
        }
        if sitePreferenceNames.contains(lowercasedName) {
            return .sitePreference
        }
        return .accountSession
    }

    nonisolated static func classify(
        _ cookie: HTTPCookie,
        allowedDomains: [String] = NodeSeekSite.allowedCookieDomains
    ) -> NodeSeekCookieCategory {
        classify(name: cookie.name, domain: cookie.domain, allowedDomains: allowedDomains)
    }

    nonisolated static func isAccountSession(
        _ cookie: HTTPCookie,
        allowedDomains: [String] = NodeSeekSite.allowedCookieDomains
    ) -> Bool {
        classify(cookie, allowedDomains: allowedDomains) == .accountSession
    }

    nonisolated static func isCloudflare(
        _ cookie: HTTPCookie,
        allowedDomains: [String] = NodeSeekSite.allowedCookieDomains
    ) -> Bool {
        classify(cookie, allowedDomains: allowedDomains) == .cloudflare
    }

    nonisolated static func accountSessionCookies(
        from cookies: [HTTPCookie],
        allowedDomains: [String] = NodeSeekSite.allowedCookieDomains
    ) -> [HTTPCookie] {
        cookies.filter { isAccountSession($0, allowedDomains: allowedDomains) }
    }

    nonisolated static func cloudflareCookies(
        from cookies: [HTTPCookie],
        allowedDomains: [String] = NodeSeekSite.allowedCookieDomains
    ) -> [HTTPCookie] {
        cookies.filter { isCloudflare($0, allowedDomains: allowedDomains) }
    }
}
