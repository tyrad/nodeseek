//
//  HotListSourceSettings.swift
//  nodeseek
//

import Foundation

/// 热榜接口地址。用户没改过时用默认地址；第三方服务失效时可以换成其他兼容地址。
nonisolated final class HotListSourceSettings: @unchecked Sendable {
    static let shared = HotListSourceSettings()
    static let didChangeNotification = Notification.Name("HotListSourceSettingsDidChange")

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func url(for kind: HotListKind) -> URL {
        customURL(for: kind) ?? kind.defaultURL
    }

    func customURL(for kind: HotListKind) -> URL? {
        userDefaults.string(forKey: Self.key(for: kind)).flatMap(Self.validatedURL(from:))
    }

    var isUsingDefaults: Bool {
        HotListKind.allCases.allSatisfy { customURL(for: $0) == nil }
    }

    /// 传入默认地址或 nil 都视为恢复默认，不单独存储。
    func setURLs(_ urls: [HotListKind: URL]) {
        for kind in HotListKind.allCases {
            if let url = urls[kind], url != kind.defaultURL {
                userDefaults.set(url.absoluteString, forKey: Self.key(for: kind))
            } else {
                userDefaults.removeObject(forKey: Self.key(for: kind))
            }
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    func resetToDefaults() {
        setURLs([:])
    }

    /// 只接受带主机名的 http/https 地址。
    static func validatedURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
            let host = components.host, !host.isEmpty,
            let url = components.url
        else {
            return nil
        }
        return url
    }

    private static func key(for kind: HotListKind) -> String {
        "hotList.sourceURL.\(kind.rawValue)"
    }
}
