//
//  NotificationMarkViewedAutomationScript.swift
//  nodeseek
//
//  Created by Codex on 2026/6/8.
//

import Foundation

enum NotificationMarkViewedAutomationScript {
    static let source = """
    return await new Promise(async (resolve) => {
      let resolved = false;
      let timer = null;

      const finish = (payload) => {
        if (resolved) return;
        resolved = true;
        if (timer) window.clearTimeout(timer);
        resolve(payload);
      };

      const parseJSON = (body) => {
        try {
          return JSON.parse(body || "{}");
        } catch (_) {
          return {};
        }
      };

      try {
        timer = window.setTimeout(() => {
          finish({ ok: false, reason: "submit_timeout" });
        }, timeoutMs);

        const options = {
          method: "POST",
          credentials: "include",
          headers: {
            "Accept": "application/json",
            "Content-Type": "application/json"
          }
        };
        if (typeof bodyJSON === "string" && bodyJSON.length > 0) {
          options.body = bodyJSON;
        }

        const response = await window.fetch(apiPath, options);
        const body = await response.text();
        const json = parseJSON(body);
        const ok = response.status >= 200 && response.status < 300 && json.success !== false;
        finish({
          ok,
          statusCode: response.status,
          response: {
            success: typeof json.success === "boolean" ? json.success : null,
            message: json.message || json.msg || json.error || null
          },
          reason: ok ? "submitted" : "server_error",
          body
        });
      } catch (error) {
        finish({
          ok: false,
          reason: "network_error",
          message: String(error && error.message ? error.message : error)
        });
      }
    });
    """
}
