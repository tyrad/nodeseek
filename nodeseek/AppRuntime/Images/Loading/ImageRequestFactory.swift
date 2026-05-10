//
//  ImageRequestFactory.swift
//  nodeseek
//
//  Created by Codex on 2026/5/9.
//

import Foundation

enum ImageRequestFactory {
    static let timeout: TimeInterval = 20

    static func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        return configuration
    }

    static func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = .returnCacheDataElseLoad
        WebRequestFingerprint.applyImageHeaders(to: &request)
        return request
    }
}
