//
//  WebRequestFingerprint.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

enum WebRequestFingerprint {
    nonisolated static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    nonisolated static let acceptLanguage = "zh-CN,zh;q=0.9,en;q=0.8"
    nonisolated static let referer = "https://www.nodeseek.com/"
    nonisolated static let htmlAccept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    nonisolated static let imageAccept = "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8"

    nonisolated static func applyHTMLHeaders(to request: inout URLRequest) {
        applyCommonHeaders(to: &request)
        request.setValue(htmlAccept, forHTTPHeaderField: "Accept")
    }

    nonisolated static func applyImageHeaders(to request: inout URLRequest) {
        applyCommonHeaders(to: &request)
        request.setValue(imageAccept, forHTTPHeaderField: "Accept")
    }

    nonisolated private static func applyCommonHeaders(to request: inout URLRequest) {
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        request.setValue(referer, forHTTPHeaderField: "Referer")
    }
}
