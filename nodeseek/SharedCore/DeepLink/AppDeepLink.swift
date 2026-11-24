import Foundation

nonisolated enum AppDeepLink: Equatable, Sendable {
    enum SearchTarget: String, Sendable { case post, user }

    case post(postID: String, page: Int, floor: String?, url: URL)
    case externalWebPage(URL)
    case probe(ProbeWidgetLink)
    case user(Int)
    case search(query: String, scope: SearchTarget)
    case compose(title: String, body: String)

    static let scheme = ProbeWidgetLink.scheme

    static func route(for url: URL) -> AppDeepLink? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil, components.port == nil else { return nil }
        switch url.host?.lowercased() {
        case "probe":
            return ProbeWidgetLink(url: url).map(Self.probe)
        case "user":
            guard components.query == nil, components.fragment == nil else { return nil }
            return userRoute(path: components.percentEncodedPath)
        case "search":
            guard let values = parameters(components, allowing: ["q", "scope"]),
                  let query = values["q"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !query.isEmpty else { return nil }
            return .search(query: query, scope: SearchTarget(rawValue: values["scope"] ?? "") ?? .post)
        case "compose":
            guard let values = parameters(components, allowing: ["title", "body"]) else { return nil }
            let title = values["title"] ?? ""
            let body = values["body"] ?? ""
            guard title.count <= 200, body.count <= 20_000 else { return nil }
            return .compose(title: title, body: body)
        case "post":
            return postRoute(for: url)
        case "open":
            return webRoute(for: url)
        default:
            return nil
        }
    }

    private static func userRoute(path: String) -> AppDeepLink? {
        guard path.first == "/" else { return nil }
        let digits = path.dropFirst()
        guard !digits.isEmpty, digits.utf8.allSatisfy({ (48...57).contains($0) }),
              let uid = Int(digits), uid > 0 else { return nil }
        return .user(uid)
    }

    private static func parameters(_ components: URLComponents, allowing names: Set<String>) -> [String: String]? {
        guard components.path.isEmpty, components.fragment == nil else { return nil }
        var values = [String: String]()
        for item in components.queryItems ?? [] {
            guard names.contains(item.name), values[item.name] == nil, let value = item.value else { return nil }
            values[item.name] = value
        }
        return values
    }

    /// `nsconnect://post/139218-3?floor=482913`
    private static func postRoute(for url: URL) -> AppDeepLink? {
        let path = url.path
        guard path.hasPrefix("/") else { return nil }
        let postURL = NodeSeekSite.baseURL.appendingPathComponent("post-" + path.dropFirst())
        guard let route = NodeSeekPostRouteResolver.route(for: postURL, baseURL: NodeSeekSite.baseURL) else { return nil }

        var floor: String?
        if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "floor" })?
            .value, value.isEmpty == false {
            floor = value
        }

        return .post(postID: route.postID, page: route.page, floor: floor, url: NodeSeekSite.postURL(id: route.postID, page: route.page))
    }

    /// `nsconnect://open?url=https%3A%2F%2Fwww.nodeseek.com%2Fpost-139218-2`
    private static func webRoute(for url: URL) -> AppDeepLink? {
        guard let rawValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "url" })?
            .value,
              let target = URL(string: rawValue),
              let scheme = target.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = target.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        guard host == NodeSeekSite.rootHost || host == NodeSeekSite.baseURL.host else {
            return .externalWebPage(target)
        }
        if let path = URLComponents(url: target, resolvingAgainstBaseURL: false)?.percentEncodedPath,
           path.hasPrefix("/space/") {
            return userRoute(path: String(path.dropFirst("/space".count)))
        }
        guard let route = NodeSeekPostRouteResolver.route(for: target, baseURL: NodeSeekSite.baseURL) else { return nil }
        return .post(
            postID: route.postID,
            page: route.page,
            floor: route.anchorID,
            url: NodeSeekSite.postURL(id: route.postID, page: route.page)
        )
    }
}
