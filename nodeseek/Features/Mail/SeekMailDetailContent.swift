//
//  SeekMailDetailContent.swift
//  nodeseek
//

import Foundation

/// 详情页正文的纯逻辑：发件人验证、远程图片计数、HTML 包装。和界面分开，方便单测。
enum SeekMailDetailContent {
    /// SPF/DKIM/DMARC 有失败项，或发件人和实际域名对不上时，提示用户留意链接。
    /// 实测格式：{"auth":{"spf":{"status":"pass"},"dkim":{...},"dmarc":{...},"fromMismatch":false}, ...}
    static func hasAuthFailure(scoreDetails: String?) -> Bool {
        guard let data = scoreDetails?.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = root["auth"] as? [String: Any] else {
            return false
        }
        if auth["fromMismatch"] as? Bool == true { return true }
        let failed: Set<String> = ["fail", "softfail", "permerror"]
        return ["spf", "dkim", "dmarc"].contains { key in
            let status = (auth[key] as? [String: Any])?["status"] as? String
            return status.map { failed.contains($0.lowercased()) } ?? false
        }
    }

    /// 只数 `<img src="http...">`，背景图之类的也会被一起拦截，但不计入横幅的数字。
    static func remoteImageCount(in html: String) -> Int {
        let pattern = #"<img\b[^>]*\bsrc\s*=\s*["']?\s*https?://"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return 0 }
        return regex.numberOfMatches(in: html, range: NSRange(html.startIndex..., in: html))
    }

    /// 注入 color-scheme 和最小样式：没有样式的邮件在深色模式下也能看清，自带背景色的保持原样。
    static func wrappedHTML(_ html: String) -> String {
        let head = """
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <style>
        :root { color-scheme: light dark; }
        body { margin: 0; font: -apple-system-body; overflow-wrap: anywhere; -webkit-text-size-adjust: 100%; }
        img { max-width: 100%; height: auto; }
        table { max-width: 100% !important; }
        pre { white-space: pre-wrap; }
        </style>
        """
        // 浏览器会把 <html> 之前的 meta 和 style 归到 head 里，不用解析原文结构
        return head + html
    }

    /// 拦截所有 http(s) 图片，配合 WKContentRuleList 使用。
    static let blockRemoteImagesRule = #"[{"trigger":{"url-filter":"^https?://","resource-type":["image"]},"action":{"type":"block"}}]"#
}
