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
          const value = JSON.parse(body);
          return value && typeof value === "object" && !Array.isArray(value) ? value : {};
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
        // 非 2xx 优先保留状态码，交给 Swift 区分登录失效、限流等明确失败。
        if (response.status >= 200 && response.status < 300 && typeof json.success !== "boolean") {
          finish({ ok: false, statusCode: response.status, reason: "invalid_response", body });
          return;
        }
        const ok = response.status >= 200 && response.status < 300 && json && json.success === true;
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
