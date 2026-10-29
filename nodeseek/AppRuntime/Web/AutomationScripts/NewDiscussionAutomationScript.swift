//
//  NewDiscussionAutomationScript.swift
//  nodeseek
//

import Foundation

/// 在已加载的 `/new-discussion` 页面里执行；同源请求自动带登录 Cookie 和 Cloudflare 放行状态。
enum NewDiscussionAutomationScript {
    /// 读取当前用户等级，用来生成阅读限制选项。
    static let userLevelSource = """
    const user = (typeof __config__ !== "undefined" && __config__) ? __config__.user : null;
    if (!user) {
      return { ok: false, reason: "not_logged_in" };
    }
    return { ok: true, reason: "loaded", rank: Number(user.rank) || 0 };
    """

    /// 参数：`payload`（请求体 JSON 字符串）、`timeoutMs`。
    /// 和网页前端一样直接请求接口；csrf-token 网页也是前端随机生成的 16 位字符串。
    static let submitSource = """
    const user = (typeof __config__ !== "undefined" && __config__) ? __config__.user : null;
    if (!user) {
      return { ok: false, reason: "not_logged_in" };
    }

    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    const randomBytes = crypto.getRandomValues(new Uint8Array(16));
    const csrfToken = Array.from(randomBytes, (value) => alphabet[value % alphabet.length]).join("");

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    let response;
    try {
      response = await fetch("/api/content/new-discussion", {
        method: "POST",
        credentials: "include",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "csrf-token": csrfToken
        },
        body: payload,
        signal: controller.signal
      });
    } catch (error) {
      const aborted = error && error.name === "AbortError";
      return {
        ok: false,
        reason: aborted ? "submit_timeout" : "network_error",
        message: String(error && error.message ? error.message : error)
      };
    } finally {
      clearTimeout(timer);
    }

    // 请求已经发出去了，读不到返回内容时结果未知，不能当普通失败重试。
    let body;
    try {
      body = await response.text();
    } catch (error) {
      return {
        ok: false,
        statusCode: response.status,
        reason: "response_unreadable",
        message: String(error && error.message ? error.message : error)
      };
    }
    return {
      ok: response.status >= 200 && response.status < 300,
      statusCode: response.status,
      reason: "responded",
      body
    };
    """
}
