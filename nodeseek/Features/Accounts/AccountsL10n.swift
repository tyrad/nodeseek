//
//  AccountsL10n.swift
//  nodeseek
//

import Foundation

enum AccountsL10n {
    nonisolated static func text(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Accounts", bundle: .main, value: key, comment: "")
    }

    nonisolated static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
}
