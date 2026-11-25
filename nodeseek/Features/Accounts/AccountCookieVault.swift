//
//  AccountCookieVault.swift
//  nodeseek
//

import Foundation
import Security

protocol AccountCookieVaultStoring: AnyObject {
    @discardableResult
    func saveCookies(_ cookies: [HTTPCookie], forUID uid: Int) -> Bool
    func loadCookies(forUID uid: Int) -> [HTTPCookie]?
    func deleteCookies(forUID uid: Int)
    func deleteAll()
}

struct PersistedHTTPCookie: Codable, Equatable, Sendable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresTimestamp: TimeInterval?
    let isSecure: Bool
    let isHTTPOnly: Bool
    let version: Int
    let sameSitePolicy: String?
    let comment: String?

    init(cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        expiresTimestamp = cookie.expiresDate?.timeIntervalSince1970
        isSecure = cookie.isSecure
        isHTTPOnly = cookie.isHTTPOnly
        version = cookie.version
        sameSitePolicy = cookie.sameSitePolicy?.rawValue
        comment = cookie.comment
    }

    func toHTTPCookie(now: Date = Date()) -> HTTPCookie? {
        if let expiresTimestamp, Date(timeIntervalSince1970: expiresTimestamp) <= now {
            return nil
        }
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
            .version: version
        ]
        if let expiresTimestamp {
            properties[.expires] = Date(timeIntervalSince1970: expiresTimestamp)
        }
        if isSecure {
            properties[.secure] = "TRUE"
        }
        if isHTTPOnly {
            properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
        }
        if let sameSitePolicy, sameSitePolicy.isEmpty == false {
            properties[.sameSitePolicy] = HTTPCookieStringPolicy(rawValue: sameSitePolicy)
        }
        if let comment, comment.isEmpty == false {
            properties[.comment] = comment
        }
        return HTTPCookie(properties: properties)
    }
}

/// 将已保存账号的会话 Cookie 快照按 UID 加密持久化到本机钥匙串。
final class KeychainAccountCookieVault: AccountCookieVaultStoring {
    private let service: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(service: String = "com.nodeseek.account-cookies") {
        self.service = service
    }

    @discardableResult
    func saveCookies(_ cookies: [HTTPCookie], forUID uid: Int) -> Bool {
        let filtered = NodeSeekCookieClassifier.accountSessionCookies(from: cookies)
        guard filtered.isEmpty == false else { return false }
        let persisted = filtered.map(PersistedHTTPCookie.init(cookie:))
        guard let data = try? encoder.encode(persisted) else { return false }

        let query = itemQuery(forUID: uid)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus != errSecItemNotFound {
            SecItemDelete(query as CFDictionary)
        }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            AppLog.warning(.account, "account-vault: Keychain 写入失败 uid=\(uid) status=\(addStatus)")
            return false
        }
        return true
    }

    func loadCookies(forUID uid: Int) -> [HTTPCookie]? {
        var query = itemQuery(forUID: uid)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let persisted = try? decoder.decode([PersistedHTTPCookie].self, from: data) else {
            return nil
        }
        let cookies = persisted.compactMap { $0.toHTTPCookie() }
        return cookies.isEmpty ? nil : cookies
    }

    func deleteCookies(forUID uid: Int) {
        SecItemDelete(itemQuery(forUID: uid) as CFDictionary)
    }

    func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func itemQuery(forUID uid: Int) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "uid-\(uid)"
        ]
    }
}

/// 内存实现，供单元测试注入验证切号逻辑。
final class InMemoryAccountCookieVault: AccountCookieVaultStoring {
    private var storage: [Int: [PersistedHTTPCookie]] = [:]
    var shouldFailSave = false

    @discardableResult
    func saveCookies(_ cookies: [HTTPCookie], forUID uid: Int) -> Bool {
        guard !shouldFailSave else { return false }
        let filtered = NodeSeekCookieClassifier.accountSessionCookies(from: cookies)
        guard filtered.isEmpty == false else { return false }
        storage[uid] = filtered.map(PersistedHTTPCookie.init(cookie:))
        return true
    }

    func loadCookies(forUID uid: Int) -> [HTTPCookie]? {
        guard let persisted = storage[uid] else { return nil }
        let cookies = persisted.compactMap { $0.toHTTPCookie() }
        return cookies.isEmpty ? nil : cookies
    }

    func deleteCookies(forUID uid: Int) {
        storage.removeValue(forKey: uid)
    }

    func deleteAll() {
        storage.removeAll()
    }
}
