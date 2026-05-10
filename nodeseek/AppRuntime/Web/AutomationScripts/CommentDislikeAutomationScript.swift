//
//  CommentDislikeAutomationScript.swift
//  nodeseek
//

import Foundation

enum CommentDislikeAutomationScript {
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

      const pickDislikeElement = (commentRoot) => {
        if (!commentRoot) return null;
        const direct = commentRoot.querySelector(".menu-item[title='反对']");
        if (direct) return direct;
        const candidates = Array.from(commentRoot.querySelectorAll(".menu-item"));
        return candidates.find((node) => {
          const title = String(node.getAttribute("title") || "").trim();
          const text = String(node.textContent || "").trim();
          const className = String(node.className || "");
          const source = `${title} ${text} ${className}`.toLowerCase();
          return /反对|点踩|dislike|downvote|oppose/.test(source);
        }) || null;
      };

      const locateCommentRoot = (id) => {
        const normalizedID = String(id);
        return document.querySelector(`[data-comment-id='${normalizedID}']`) ||
          document.getElementById(normalizedID) ||
          document.querySelector(`#comment-${normalizedID}`);
      };

      try {
        const commentRoot = locateCommentRoot(commentID);
        const dislikeElement = pickDislikeElement(commentRoot);
        if (!commentRoot || !dislikeElement) {
          finish({
            ok: false,
            statusCode: 404,
            response: {
              success: false,
              message: "未找到可反对的评论节点",
              current: null
            },
            reason: "comment_not_found",
            body: ""
          });
          return;
        }

        if (dislikeElement.classList.contains("clicked")) {
          finish({
            ok: false,
            statusCode: 200,
            response: {
              success: false,
              message: "该评论已反对",
              current: readCount(dislikeElement)
            },
            reason: "already_clicked",
            body: ""
          });
          return;
        }

        timer = window.setTimeout(() => {
          finish({ ok: false, reason: "submit_timeout" });
        }, timeoutMs);

        const response = await window.fetch("/api/statistics/dislike", {
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
