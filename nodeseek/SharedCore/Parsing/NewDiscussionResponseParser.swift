//
//  NewDiscussionResponseParser.swift
//  nodeseek
//

import Foundation

/// 发帖接口返回：成功时带新帖地址，失败时带提示文案。
nonisolated struct NewDiscussionResponse: Equatable, Sendable {
    let success: Bool
    let message: String?
    let redirect: String?
    let redirectHash: String?

    /// 新帖地址，例如 `/post-123456-1`；解析不出时返回 nil，由调用方退回刷新列表。
    func postRoute(baseURL: URL = NodeSeekSite.baseURL) -> NodeSeekPostRoute? {
        guard let redirect, !redirect.isEmpty,
              let url = URL(string: redirect + (redirectHash ?? ""), relativeTo: baseURL) else {
            return nil
        }
        return NodeSeekPostRouteResolver.route(for: url, baseURL: baseURL)
    }
}

nonisolated enum NewDiscussionResponseParser {
    enum ParseError: Error, Equatable {
        case invalidJSON
    }

    static func parse(_ data: Data) throws -> NewDiscussionResponse {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            throw ParseError.invalidJSON
        }
        return NewDiscussionResponse(
            success: json["success"] as? Bool ?? false,
            message: nonEmptyString(json["message"]),
            redirect: nonEmptyString(json["redirect"]),
            redirectHash: nonEmptyString(json["redirectHash"])
        )
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
