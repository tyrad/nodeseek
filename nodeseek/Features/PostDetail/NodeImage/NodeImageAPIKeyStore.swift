//
//  NodeImageAPIKeyStore.swift
//  nodeseek
//
//  Created by Codex on 2026/5/9.
//

import Foundation
import Security

protocol NodeImageAPIKeyStoring: AnyObject {
    func apiKey() -> String?
    func save(apiKey: String)
    func clear()
}

enum NodeImageAPIKeyNormalizer {
    static func normalized(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }

        if let headerLine = trimmed
            .components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { $0.lowercased().hasPrefix("x-api-key") }),
           let separatorIndex = headerLine.firstIndex(where: { $0 == ":" || $0 == "=" }) {
            return strippedQuotes(String(headerLine[headerLine.index(after: separatorIndex)...]))
        }

        if trimmed.lowercased().hasPrefix("bearer ") {
            return strippedQuotes(String(trimmed.dropFirst("Bearer ".count)))
        }

        return strippedQuotes(trimmed)
    }

    private static func strippedQuotes(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return trimmed }
        if (trimmed.first == "\"" && trimmed.last == "\"")
            || (trimmed.first == "'" && trimmed.last == "'") {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }
}

final class KeychainNodeImageAPIKeyStore: NodeImageAPIKeyStoring {
    private let service = "com.nodeseek.nodeimage"
    private let account = "api-key"

    func apiKey() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            return nil
        }
        let normalized = NodeImageAPIKeyNormalizer.normalized(apiKey)
        return normalized.isEmpty ? nil : normalized
    }

    func save(apiKey: String) {
        let normalizedAPIKey = NodeImageAPIKeyNormalizer.normalized(apiKey)
        guard normalizedAPIKey.isEmpty == false else {
            clear()
            return
        }

        let data = Data(normalizedAPIKey.utf8)
        var query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            SecItemAdd(query as CFDictionary, nil)
        } else if status != errSecSuccess {
            clear()
            query[kSecValueData as String] = data
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
