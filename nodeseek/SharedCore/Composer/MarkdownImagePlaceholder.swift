//
//  MarkdownImagePlaceholder.swift
//  nodeseek
//

import Foundation

/// 图片上传期间留在正文里的占位，传完替换成真实图片 Markdown。
/// 正文是唯一来源：用户把占位删掉，图片传完也不再插入。
nonisolated enum MarkdownImagePlaceholder {
    private static let scheme = "uploading:"

    static func text(id: String) -> String {
        "![上传中…](\(scheme)\(id))"
    }

    /// 占位已被删掉时返回 nil。
    static func replacing(id: String, with replacement: String, in content: String) -> String? {
        let placeholder = text(id: id)
        guard content.contains(placeholder) else { return nil }
        return content.replacingOccurrences(of: placeholder, with: replacement)
    }

    /// 去掉占位以及它独占的那一行换行。
    static func removing(id: String, in content: String) -> String {
        removing(placeholders: [text(id: id)], in: content)
    }

    /// 保存草稿时去掉所有占位，避免恢复出永远传不完的图片。
    static func strippingAll(in content: String) -> String {
        guard content.contains(scheme) else { return content }
        let pattern = #"!\[上传中…\]\(uploading:[^)\s]*\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return content }
        let source = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: source.length))
        let placeholders = Set(matches.map { source.substring(with: $0.range) })
        return removing(placeholders: Array(placeholders), in: content)
    }

    static func containsPlaceholder(_ content: String) -> Bool {
        content.contains("](\(scheme)")
    }

    private static func removing(placeholders: [String], in content: String) -> String {
        var result = content
        for placeholder in placeholders {
            // 占位插入时独占一行，先连同换行一起删，删不到再只删占位本身。
            for variant in ["\n\(placeholder)\n", "\(placeholder)\n", "\n\(placeholder)"] where result.contains(variant) {
                result = result.replacingOccurrences(of: variant, with: variant.hasPrefix("\n") && variant.hasSuffix("\n") ? "\n" : "")
            }
            result = result.replacingOccurrences(of: placeholder, with: "")
        }
        return result
    }
}
