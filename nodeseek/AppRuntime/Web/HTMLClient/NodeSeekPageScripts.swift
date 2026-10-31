//
//  NodeSeekPageScripts.swift
//  nodeseek
//

import Foundation

enum NodeSeekPageScripts {
    /// 读取整页 HTML，并把 `window.__config__` 附在末尾，供解析器取当前账号。
    /// 隐藏 WebView 抓取和登录页关闭时共用。
    nonisolated static let outerHTMLWithCapturedConfig = """
        (() => {
          const html = document.documentElement.outerHTML;
          try {
            if (!window.__config__) {
              return html;
            }
            const json = JSON.stringify(window.__config__).replace(/</g, '\\\\u003c');
            return html + '\\n<script id="nodeseek-captured-config" type="application/json">' + json + '</script>';
          } catch (error) {
            return html;
          }
        })()
        """
}
