import Foundation

/// APNs `type` + `url` 决定点进去去哪。未知类型只出横幅。
enum PushNotificationRoute: Equatable, Sendable {
    case reply(postID: String, page: Int, floor: String?, url: URL)
    case atMe(postID: String, page: Int, floor: String?, url: URL)
    case checkin
    case inbox
    case webPage(url: URL, title: String)
    case bannerOnly

    nonisolated init?(userInfo: [AnyHashable: Any]) {
        let type = stringValue(userInfo["type"])?.lowercased() ?? ""
        let postID = stringValue(userInfo["post_id"])
        let floor = stringValue(userInfo["floor"])
        let url = stringValue(userInfo["url"]).flatMap(URL.init(string:))
        let post = url.flatMap(Self.parsePostURL)
        let resolvedID = postID ?? post?.id
        let page = post?.page ?? Self.page(forFloor: floor)
        let resolvedURL = url ?? resolvedID.map { NodeSeekSite.postURL(id: $0, page: page) }

        switch type {
        case "other", "unknown":
            // 旧 ns-apns 把私信标成 other，有对话链接时仍应打开。
            if let url, NodeSeekSite.isNodeSeekHost(url), Self.isTalkURL(url) {
                self = .webPage(url: url, title: Self.webTitle(for: url))
            } else {
                self = .bannerOnly
            }
        case "checkin":
            self = .checkin
        case "reply":
            guard let resolvedID, let resolvedURL else { return nil }
            self = .reply(postID: resolvedID, page: page, floor: floor, url: resolvedURL)
        case "at", "atme", "mention":
            if let resolvedID, let resolvedURL, post != nil || postID != nil {
                self = .atMe(postID: resolvedID, page: page, floor: floor, url: resolvedURL)
            } else if let url, NodeSeekSite.isNodeSeekHost(url) {
                self = .webPage(url: url, title: "提到我")
            } else {
                self = .bannerOnly
            }
        case "message", "dm", "inbox", "notification", "system":
            if let url, NodeSeekSite.isNodeSeekHost(url) {
                self = .webPage(url: url, title: Self.webTitle(for: url))
            } else {
                self = .inbox
            }
        default:
            self = .bannerOnly
        }
    }

    nonisolated static func parsePostURL(_ url: URL) -> (id: String, page: Int)? {
        let path = url.path
        guard let regex = try? NSRegularExpression(pattern: #"post-(\d+)(?:-(\d+))?"#) else {
            return nil
        }
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        guard let match = regex.firstMatch(in: path, range: range) else {
            return nil
        }
        guard let idRange = Range(match.range(at: 1), in: path) else { return nil }
        let page: Int
        if match.range(at: 2).location != NSNotFound, let pageRange = Range(match.range(at: 2), in: path) {
            page = max(1, Int(path[pageRange]) ?? 1)
        } else {
            page = 1
        }
        return (String(path[idRange]), page)
    }

    private nonisolated static func webTitle(for url: URL) -> String {
        let fragment = url.fragment ?? ""
        if fragment.contains("mode=talk") { return "私信" }
        if fragment.contains("atMe") { return "提到我" }
        return "系统提醒"
    }

    private nonisolated static func isTalkURL(_ url: URL) -> Bool {
        (url.fragment ?? "").contains("mode=talk")
    }

    private nonisolated static func page(forFloor floor: String?) -> Int {
        guard let floor, let value = Int(floor) else { return 1 }
        return max(1, (value + 9) / 10)
    }
}

private nonisolated func stringValue(_ raw: Any?) -> String? {
    switch raw {
    case let value as String:
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    case let value as Int:
        return String(value)
    case let value as Int64:
        return String(value)
    default:
        return nil
    }
}
