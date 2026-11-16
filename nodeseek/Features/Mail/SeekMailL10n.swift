import Foundation

/// 邮箱界面独立使用 Mail 表；格式串保留完整句子，允许译文调整参数顺序。
nonisolated enum SeekMailL10n {
    static func text(_ key: String, bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: key, value: key, table: "Mail")
    }

    static func format(_ key: String, _ arguments: String...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
}
