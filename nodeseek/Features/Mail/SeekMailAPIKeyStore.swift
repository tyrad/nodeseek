//
//  SeekMailAPIKeyStore.swift
//  nodeseek
//

import Foundation
import Security

protocol SeekMailAPIKeyStoring: AnyObject {
    func apiKey() -> String?
    func save(apiKey: String)
    func clear()
}

extension SeekMailAPIKeyStoring {
    var hasAPIKey: Bool { apiKey() != nil }
}

enum SeekMailAPIKeyStore {
    /// Key 保存或移除后发出，邮箱页据此在绑定页和邮件列表之间切换。
    static let didChangeNotification = Notification.Name("SeekMailAPIKeyStore.didChange")
    static let shared: SeekMailAPIKeyStoring = KeychainSeekMailAPIKeyStore()

    /// 粘贴内容可能带 `Bearer ` 前缀或引号，规则与 NodeImage 一致。
    static func normalized(_ rawValue: String) -> String {
        NodeImageAPIKeyNormalizer.normalized(rawValue)
    }
}

final class KeychainSeekMailAPIKeyStore: SeekMailAPIKeyStoring {
    private let service: String
    private let account = "api-key"
    private let notificationCenter: NotificationCenter

    init(service: String = "com.nodeseek.seekmail", notificationCenter: NotificationCenter = .default) {
        self.service = service
        self.notificationCenter = notificationCenter
    }

    func apiKey() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        let normalized = SeekMailAPIKeyStore.normalized(value)
        return normalized.isEmpty ? nil : normalized
    }

    func save(apiKey: String) {
        let normalized = SeekMailAPIKeyStore.normalized(apiKey)
        guard normalized.isEmpty == false else {
            clear()
            return
        }
        // 先删后加，保证访问级别每次都按下面的设置写入
        SecItemDelete(baseQuery() as CFDictionary)
        var query = baseQuery()
        query[kSecValueData as String] = Data(normalized.utf8)
        // 只在本机可用，不随 iCloud 钥匙串或备份同步到其他设备
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
        notificationCenter.post(name: SeekMailAPIKeyStore.didChangeNotification, object: self)
    }

    func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
        notificationCenter.post(name: SeekMailAPIKeyStore.didChangeNotification, object: self)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
