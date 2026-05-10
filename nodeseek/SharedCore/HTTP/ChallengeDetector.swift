//
//  ChallengeDetector.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

struct ChallengeDetector: Sendable {

    func detect(response: HTMLResponse) -> ChallengeKind? {
        if Self.containsLoginRequiredHTML(response.html) {
            return .loginRequired(response.finalURL)
        }

        if Self.containsUsableNodeSeekHTML(response.html) {
            return nil
        }

        if isCloudflareChallenge(html: response.html, headers: response.headers) {
            return .cloudflare(response.finalURL)
        }

        if response.statusCode == 403 || response.statusCode == 503 {
            return .blocked(response.finalURL)
        }

        return nil
    }

    private func isCloudflareChallenge(html: String, headers: [String: String]) -> Bool {
        let normalizedHeaders = Dictionary(
            uniqueKeysWithValues: headers.map { key, value in
                (key.lowercased(), value.lowercased())
            }
        )

        // 注意：NodeSeek 正常页面也会带 `Server: cloudflare`，不能仅凭这个头判断 challenge。
        // 仅在 Cloudflare 明确给出 challenge 信号时判定。
        if normalizedHeaders["cf-mitigated"] == "challenge" {
            return true
        }

        return Self.containsCloudflareChallengeHTML(html)
    }

    static func containsCloudflareChallengeHTML(_ html: String) -> Bool {
        HTMLPayloadInspector.containsCloudflareChallenge(html)
    }

    static func containsLoginRequiredHTML(_ html: String) -> Bool {
        html.contains("本帖需要注册用户才能查看")
            || html.contains("需要注册用户才能查看")
    }

    static func containsUsableNodeSeekHTML(_ html: String) -> Bool {
        html.contains("id=\"nsk-body\"")
            || html.contains("class=\"post-list\"")
            || html.contains("class=\"nsk-post\"")
            || html.contains("class=\"post-content\"")
            || html.contains("class=\"comments\"")
    }
}
