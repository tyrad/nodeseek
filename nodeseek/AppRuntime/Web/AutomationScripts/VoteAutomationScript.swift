import Foundation

enum VoteAutomationScript {
    static let source = #"""
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    const request = async (path, method, payload) => {
      const url = new URL(path, location.href);
      if (url.origin !== location.origin) throw new Error("投票地址无效");
      const body = payload === undefined ? "" : JSON.stringify(payload);
      const text = [method, url.href, navigator.userAgent || "", body].join("\n\n");
      const digest = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(text));
      const sign = Array.from(new Uint8Array(digest), x => x.toString(16).padStart(2, "0")).join("");
      const response = await fetch(url.href, {
        method, credentials: "include", cache: "no-store", signal: controller.signal,
        headers: { "Accept": "application/json", "Content-Type": "application/json", "x-dynamic-sign": sign },
        ...(method === "GET" ? {} : {body})
      });
      const raw = await response.text();
      let json;
      try { json = JSON.parse(raw); } catch (_) { json = null; }
      return { ok: response.ok && json?.success === true, statusCode: response.status,
        body: json ? raw : "", message: json?.message || (response.status === 401 ? "请先登录后参与投票。" : "投票请求失败，请打开网页检查登录或验证状态。") };
    };
    try {
      if (!Number.isSafeInteger(voteID) || voteID <= 0) throw new Error("投票编号无效");
      if (operation === "submit") {
        const current = await request("/api/vote/info/" + voteID, "GET");
        if (!current.ok) return current;
        const vote = JSON.parse(current.body).vote;
        if (!vote || vote.id !== voteID || vote.locked || vote.items.some(x => x.voted)) {
          return {ok:false, reason:"state_changed", message:"投票状态已改变，请刷新后查看。"};
        }
        if (!Array.isArray(ids) || ids.length === 0 || new Set(ids).size !== ids.length ||
            (!vote.multiple && ids.length !== 1) || ids.some(id => !vote.items.some(x => x.vote_item_id === id))) {
          return {ok:false, message:"请选择有效的投票选项。"};
        }
        return await request("/api/vote/voteforitem", "POST", {ids});
      }
      return await request("/api/vote/info/" + voteID, "GET");
    } catch (error) {
      return {ok:false, reason: error.name === "AbortError" ? "timeout" : "network_error",
        message: error.name === "AbortError" ? "请求超时，请刷新投票状态。" : "投票请求失败，请稍后重试或打开网页。"};
    } finally { clearTimeout(timer); }
    """#
}
