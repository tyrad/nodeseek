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

    /// 参数：`endpoint`（发帖或编辑接口路径）、`payload`（请求体 JSON 字符串）、`timeoutMs`。
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
      response = await fetch(endpoint, {
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

    /// 在帖子第一页读取主楼原文；只有楼主本人才返回内容，和网页“编辑”按钮的判断一致。
    static let editableDiscussionSource = """
    const config = (typeof __config__ !== "undefined" && __config__) ? __config__ : null;
    if (!config || !config.user) {
      return { ok: false, reason: "not_logged_in" };
    }
    const post = config.postData;
    const main = post && (post.comments || []).find((comment) => comment.floorIndex === 0);
    if (!post || !main) {
      return { ok: false, reason: "unexpected", message: "没有读到帖子原文" };
    }
    if (!post.op || Number(post.op.uid) !== Number(config.user.member_id)) {
      return { ok: false, reason: "not_owner" };
    }
    return {
      ok: true,
      reason: "loaded",
      title: String(post.title || ""),
      content: String(main.markdown || ""),
      category: String(post.category || ""),
      rank: Number(post.rank) || 0,
      userLevel: Number(config.user.rank) || 0
    };
    """

    /// 在评论所在页读取自己评论的 Markdown 原文，参数 `commentId`。
    static let editableCommentSource = """
    const config = (typeof __config__ !== "undefined" && __config__) ? __config__ : null;
    if (!config || !config.user) {
      return { ok: false, reason: "not_logged_in" };
    }
    const post = config.postData;
    const comment = post && (post.comments || []).find((item) => Number(item.commentId) === Number(commentId));
    if (!comment) {
      return { ok: false, reason: "unexpected", message: "没有在这一页找到这条评论" };
    }
    if (!comment.poster || Number(comment.poster.uid) !== Number(config.user.member_id)) {
      return { ok: false, reason: "not_owner" };
    }
    return {
      ok: true,
      reason: "loaded",
      content: String(comment.markdown || ""),
      floorIndex: Number(comment.floorIndex) || 0
    };
    """
}
