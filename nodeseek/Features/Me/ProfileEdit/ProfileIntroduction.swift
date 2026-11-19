//
//  ProfileIntroduction.swift
//  nodeseek
//

import Foundation

/// 个人信息里的三项文字资料。站点接口一次提交三项，改其中一项也要带上另外两项。
nonisolated struct ProfileIntroduction: Equatable, Sendable {
    var bio: String
    var signature: String
    var readme: String

    init(bio: String = "", signature: String = "", readme: String = "") {
        self.bio = bio
        self.signature = signature
        self.readme = readme
    }
}

/// 照搬网页设置页提交前的签名检查：不允许引用和图片，只支持基本平面内的字符。
enum ProfileSignatureValidator {
    nonisolated static func validationMessage(for signature: String) -> String? {
        if containsBlockquote(signature) {
            return NSLocalizedString("签名不允许使用引用", tableName: "Me", comment: "")
        }
        if containsImage(signature) {
            return NSLocalizedString("签名不允许使用图片", tableName: "Me", comment: "")
        }
        // 网页按码点长度 ≥ 2 判断，也就是基本平面以外的字符（多数 emoji）。
        let extended = String(String.UnicodeScalarView(signature.unicodeScalars.filter { $0.value > 0xFFFF }))
        if !extended.isEmpty {
            return String(
                format: NSLocalizedString("签名只支持 Unicode 1.1，不支持扩展 emoji：%@", tableName: "Me", comment: ""),
                extended
            )
        }
        return nil
    }

    /// 代码块里的 `>` 不会渲染成引用，跳过。
    private nonisolated static func containsBlockquote(_ text: String) -> Bool {
        var isInFence = false
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                isInFence.toggle()
                continue
            }
            guard !isInFence else { continue }
            let indent = line.prefix { $0 == " " }.count
            if indent <= 3, line.dropFirst(indent).hasPrefix(">") {
                return true
            }
        }
        return false
    }

    private nonisolated static func containsImage(_ text: String) -> Bool {
        text.range(of: #"!\[[^\]]*\]\([^)]*\)"#, options: .regularExpression) != nil
            || text.range(of: "<img", options: .caseInsensitive) != nil
    }
}
