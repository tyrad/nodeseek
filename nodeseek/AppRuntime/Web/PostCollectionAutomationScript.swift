//
//  PostCollectionAutomationScript.swift
//  nodeseek
//

import Foundation

enum PostCollectionAutomationScript {
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

        const response = await window.fetch("/api/statistics/collection", {
          method: "POST",
          credentials: "include",
          headers: {
            "Accept": "application/json",
            "Content-Type": "application/json"
          },
          body: JSON.stringify({
            postId: postID,
            action
          })
        });

        const body = await response.text();
        const json = parseJSON(body);
        finish({
          ok: response.status >= 200 && response.status < 300 && json.success !== false,
          statusCode: response.status,
          response: {
            success: typeof json.success === "boolean" ? json.success : null,
            message: json.message || json.msg || json.error || null,
            postCollectionCount: typeof json.postCollectionCount === "number" ? json.postCollectionCount : null,
            userCollectionCount: typeof json.userCollectionCount === "number" ? json.userCollectionCount : null
          },
          reason: response.status >= 200 && response.status < 300 && json.success !== false ? "submitted" : "server_error",
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
