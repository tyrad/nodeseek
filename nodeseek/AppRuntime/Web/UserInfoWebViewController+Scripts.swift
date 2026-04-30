//
//  UserInfoWebViewController+Scripts.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import Foundation
import WebKit

extension UserInfoWebViewController {
    static func makeUserScripts() -> [WKUserScript] {
        let css = injectedUserInfoCSS.trimmingCharacters(in: .whitespacesAndNewlines)
        guard css.isEmpty == false else { return [] }

        let source = """
        (() => {
          const style = document.createElement('style');
          style.setAttribute('data-nodeseek-user-info-style', 'true');
          style.textContent = \(javaScriptStringLiteral(css));
          document.documentElement.appendChild(style);
        })();
        """
        return [
            WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        ]
    }

    private static var injectedUserInfoCSS: String {
        """
        """
    }

    private static func javaScriptStringLiteral(_ string: String) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: string, options: []),
            let literal = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }

        return literal
    }
}

