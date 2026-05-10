//
//  NodeSeekWebThemeSupport.swift
//  nodeseek
//

import Foundation
import UIKit
import WebKit

@MainActor
enum NodeSeekWebThemeSupport {
    static let colorSchemeCookieName = "colorscheme"

    static func makeUserContentController(additionalScripts: [WKUserScript] = []) -> WKUserContentController {
        let controller = WKUserContentController()
        controller.addUserScript(makeUserScript())
        for script in additionalScripts {
            controller.addUserScript(script)
        }
        return controller
    }

    static func makeUserScript() -> WKUserScript {
        WKUserScript(
            source: themeSynchronizationJavaScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }

    static func makeColorSchemeCookie(userInterfaceStyle: UIUserInterfaceStyle) -> HTTPCookie? {
        let value = colorSchemeValue(for: userInterfaceStyle)
        return HTTPCookie(properties: [
            .domain: ".nodeseek.com",
            .path: "/",
            .name: colorSchemeCookieName,
            .value: value,
            .secure: "TRUE",
            .expires: Date(timeIntervalSinceNow: 60 * 60 * 24 * 365 * 5)
        ])
    }

    static func syncPreferredColorSchemeCookie(
        to webCookieStore: WebCookieStore,
        userInterfaceStyle: UIUserInterfaceStyle
    ) async {
        guard let cookie = makeColorSchemeCookie(userInterfaceStyle: userInterfaceStyle) else { return }
        await webCookieStore.setCookie(cookie)
    }

    private static func colorSchemeValue(for userInterfaceStyle: UIUserInterfaceStyle) -> String {
        resolvedInterfaceStyle(for: userInterfaceStyle) == .dark ? "dark" : "light"
    }

    private static func resolvedInterfaceStyle(for userInterfaceStyle: UIUserInterfaceStyle) -> UIUserInterfaceStyle {
        userInterfaceStyle == .dark ? .dark : .light
    }

    private static let themeSynchronizationJavaScript = """
    (() => {
      const host = window.location.hostname.toLowerCase();
      if (host !== 'nodeseek.com' && !host.endsWith('.nodeseek.com')) return;

      const media = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)');
      const preferredScheme = () => media && media.matches ? 'dark' : 'light';
      const oppositeScheme = (scheme) => scheme === 'dark' ? 'light' : 'dark';
      const writeCookie = (scheme) => {
        document.cookie = `colorscheme=${scheme}; path=/; max-age=157680000; SameSite=Lax; Secure`;
      };
      const updateIcon = (scheme) => {
        const icon = document.querySelector('.color-theme-switcher use');
        if (!icon) return;
        icon.setAttribute('href', scheme === 'dark' ? '#moon' : '#sun-one');
      };
      const applyBodyClass = (scheme) => {
        if (!document.body) return false;
        const className = (value) => value === 'dark' ? 'dark-layout' : 'light-layout';
        document.body.classList.remove(className(oppositeScheme(scheme)));
        document.body.classList.add(className(scheme));
        document.documentElement.style.colorScheme = scheme;
        updateIcon(scheme);
        return true;
      };
      const apply = () => {
        const scheme = preferredScheme();
        writeCookie(scheme);
        if (!applyBodyClass(scheme)) {
          document.addEventListener('DOMContentLoaded', () => applyBodyClass(scheme), { once: true });
        }
      };

      apply();
      if (media && media.addEventListener) {
        media.addEventListener('change', apply);
      }
    })();
    """
}
