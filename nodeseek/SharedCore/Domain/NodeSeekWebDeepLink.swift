//
//  NodeSeekWebDeepLink.swift
//  nodeseek
//
//  外部链接跳转 App 的深链解析，供 Loon / 快捷指令 / 其它 App 使用：
//    nsconnect://post/<postID>[-<page>][?floor=<anchor>]
//    nsconnect://open?url=<NodeSeek 完整链接>
//  `nsconnect://probe/...` 仍归小组件（ProbeWidgetLink）。
//

import Foundation

nonisolated enum NodeSeekWebDeepLink {
    static let scheme = ProbeWidgetLink.scheme

    static func route(for url: URL) -> PushNotificationRoute? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        switch url.host?.lowercased() {
        case "post":
            return postRoute(for: url)
        case "open":
            return webRoute(for: url)
        default:
            return nil
        }
    }

    /// `nsconnect://post/139218-3?floor=482913`
    private static func postRoute(for url: URL) -> PushNotificationRoute? {
        let components = url.pathComponents.filter { $0.isEmpty == false && $0 != "/" }
        guard let raw = components.first else { return nil }
        let parts = raw.split(separator: "-", omittingEmptySubsequences: true)
        guard let idPart = parts.first, idPart.allSatisfy(\.isNumber) else { return nil }
        let page = parts.count > 1 ? max(Int(parts[1]) ?? 1, 1) : 1

        var floor: String?
        if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "floor" })?
            .value, value.isEmpty == false {
            floor = value
        }

        let postID = String(idPart)
        return .reply(
            postID: postID,
            page: page,
            floor: floor,
            url: NodeSeekSite.postURL(id: postID, page: page)
        )
    }

    /// `nsconnect://open?url=https%3A%2F%2Fwww.nodeseek.com%2Fpost-139218-2`
    private static func webRoute(for url: URL) -> PushNotificationRoute? {
        guard let rawValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "url" })?
            .value,
              let target = URL(string: rawValue),
              let route = NodeSeekPostRouteResolver.route(for: target, baseURL: target) else {
            return nil
        }
        return .reply(
            postID: route.postID,
            page: route.page,
            floor: route.anchorID,
            url: route.url
        )
    }
}
