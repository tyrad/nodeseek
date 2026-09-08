import Foundation
import WebKit

enum TerminalSourceCaptureScript {
    static func install(on configuration: WKWebViewConfiguration) {
        configuration.userContentController.addUserScript(WKUserScript(
            source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
    }

    static let source = #"""
    (() => {
      const attribute = 'data-nodeseek-terminal-source';
      const text = node => {
        if (node.nodeType === Node.TEXT_NODE) return node.nodeValue || '';
        if (node.nodeType !== Node.ELEMENT_NODE) return '';
        if (node.hasAttribute('data-ansicode')) {
          const value = Number(node.getAttribute('data-ansicode'));
          return Number.isInteger(value) && value >= 0 && value <= 0x10ffff
            ? String.fromCodePoint(value) : '';
        }
        if (node.tagName === 'BR') return '\n';
        return Array.from(node.childNodes).map(text).join('');
      };
      const save = (body, pres) => {
        if (!body || !pres.length) return;
        const values = pres.slice(0, 16).map(pre => text(pre.querySelector('code') || pre));
        const bytes = new TextEncoder().encode(JSON.stringify(values));
        if (bytes.length > 512000) return;
        let binary = '';
        for (let i = 0; i < bytes.length; i += 8192) {
          binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
        }
        body.setAttribute(attribute, btoa(binary));
      };
      const scan = () => document.querySelectorAll('.nsk-magic-tab-body').forEach(body => {
        const pres = Array.from(body.querySelectorAll('pre'));
        if (pres.length) save(body, pres);
      });
      new MutationObserver(records => {
        // 同一次脚本执行就移除 pre 时，补读 mutation 中仍可访问的原节点。
        for (const record of records) {
          const body = record.target.nodeType === 1 ? record.target.closest('.nsk-magic-tab-body') : null;
          if (!body || body.hasAttribute(attribute)) continue;
          const pres = [];
          for (const node of record.removedNodes) {
            if (node.nodeType !== 1) continue;
            if (node.matches('pre')) pres.push(node);
            else pres.push(...node.querySelectorAll('pre'));
          }
          save(body, pres);
        }
        scan();
      }).observe(document, { childList: true, subtree: true, characterData: true });
      document.addEventListener('DOMContentLoaded', scan, { once: true });
    })();
    """#
}
