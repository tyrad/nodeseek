//
//  WebViewStyleInjectionScriptFactory.swift
//  nodeseek
//

import Foundation
import WebKit

enum WebViewStyleInjectionScriptFactory {
    static func makeStyleInjectionScripts(
        css: String,
        markerAttribute: String = "data-nodeseek-injected-style"
    ) -> [WKUserScript] {
        let trimmedCSS = css.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCSS.isEmpty == false else { return [] }

        let source = """
        (() => {
          const style = document.createElement('style');
          style.setAttribute(\(javaScriptStringLiteral(markerAttribute)), 'true');
          style.textContent = \(javaScriptStringLiteral(trimmedCSS));
          document.documentElement.appendChild(style);
        })();
        """
        return [
            WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        ]
    }

    private static func javaScriptStringLiteral(_ string: String) -> String {
        var escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        escaped = escaped
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return "\"\(escaped)\""
    }
}
