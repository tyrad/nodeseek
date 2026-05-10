//
//  PostChickenLegAutomationScript.swift
//  nodeseek
//

import Foundation

enum PostChickenLegAutomationScript {
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

      const readCount = (root) => {
        if (!root) return null;
        const countText = root.querySelector("span")?.textContent || root.textContent || "";
        const matched = String(countText).match(/\\d+/);
        if (!matched) return null;
        return Number(matched[0]);
      };

      const pickPostRoot = () =>
        document.querySelector(".nsk-post > .content-item") ||
        document.querySelector(".post-title + .content-item") ||
        document.querySelector("#nsk-body-left .content-item");

      const readPostCommentID = (postRoot) => {
        const rawID = postRoot?.getAttribute("data-comment-id") || "";
        const commentID = Number(rawID);
        return Number.isInteger(commentID) && commentID > 0 ? commentID : null;
      };

      const pickPostChickenLegElement = () => {
        const postRoot = pickPostRoot();
        const candidates = Array.from((postRoot || document).querySelectorAll(".menu-item[title='加鸡腿'], .menu-item"));
        return candidates.find((node) => {
          if (!postRoot && node.closest(".comment-container, ul.comments")) return false;
          const title = String(node.getAttribute("title") || "").trim();
          const text = String(node.textContent || "").trim();
          const className = String(node.className || "");
          const source = `${title} ${text} ${className}`.toLowerCase();
          return /加鸡腿|鸡腿|chicken|chicken-leg|drumstick|stardust|coin/.test(source);
        }) || null;
      };

      try {
        const postRoot = pickPostRoot();
        const commentID = readPostCommentID(postRoot);
        if (!commentID) {
          finish({
            ok: false,
            statusCode: 404,
            response: {
              success: false,
              message: "未找到帖子正文的评论 ID",
              current: null
            },
            reason: "post_comment_id_not_found",
            body: ""
          });
          return;
        }

        const chickenLegElement = pickPostChickenLegElement();
        if (chickenLegElement && chickenLegElement.classList.contains("clicked")) {
          finish({
            ok: false,
            statusCode: 200,
            response: {
              success: false,
              message: "该帖子已投放鸡腿",
              current: readCount(chickenLegElement)
            },
            reason: "already_clicked",
            body: ""
          });
          return;
        }

        timer = window.setTimeout(() => {
          finish({ ok: false, reason: "submit_timeout" });
        }, timeoutMs);

        const response = await window.fetch("/api/statistics/like", {
          method: "POST",
          credentials: "include",
          headers: {
            "Accept": "application/json",
            "Content-Type": "application/json"
          },
          body: JSON.stringify({
            commentId: commentID,
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
            current: typeof json.current === "number" ? json.current : null
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
