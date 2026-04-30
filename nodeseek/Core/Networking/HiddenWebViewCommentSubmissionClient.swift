//
//  HiddenWebViewCommentSubmissionClient.swift
//  nodeseek
//

import Foundation
import OSLog

struct HiddenWebViewCommentSubmissionClient {
    private let timeoutInterval: TimeInterval
    private let logger = Logger(subsystem: "com.nodeseek.app", category: "HiddenWebViewCommentSubmission")

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
    }

    func submitComment(postID: Int, content: String, referer: URL) async throws -> CommentAutomationResponse {
        let requestLock = HiddenWebViewRequestLock.shared
        await requestLock.acquire()
        logger.info("准备通过隐藏 WebView 模拟评论提交: postID=\(postID), referer=\(referer.absoluteString)")
        do {
            let loader = await MainActor.run {
                HiddenWebViewLoader.shared
            }
            let response = try await loader.submitComment(
                pageURL: referer,
                content: content,
                timeoutInterval: timeoutInterval
            )
            await requestLock.release()
            return response
        } catch {
            await requestLock.release()
            throw error
        }
    }
}

enum CommentSubmissionAutomationScript {
    static let source = """
    return await new Promise(async (resolve) => {
      let resolved = false;
      let timer = null;
      let originalFetch = window.fetch;
      const originalXHROpen = window.XMLHttpRequest && window.XMLHttpRequest.prototype.open;
      const originalXHRSend = window.XMLHttpRequest && window.XMLHttpRequest.prototype.send;

      const finish = (payload) => {
        if (resolved) return;
        resolved = true;
        if (timer) window.clearTimeout(timer);
        if (originalFetch) window.fetch = originalFetch;
        if (originalXHROpen) window.XMLHttpRequest.prototype.open = originalXHROpen;
        if (originalXHRSend) window.XMLHttpRequest.prototype.send = originalXHRSend;
        resolve(payload);
      };

      try {
        const isCommentRequest = (url) => String(url || "").includes("/api/content/new-comment");

        const parseResponseBody = (statusCode, body) => {
          let message = null;
          try {
            const json = JSON.parse(body || "{}");
            message = json.message || json.error || json.msg || null;
          } catch (_) {}
          finish({
            ok: statusCode >= 200 && statusCode < 300,
            statusCode,
            message,
            reason: statusCode >= 200 && statusCode < 300 ? "submitted" : "server_error",
            body: body || ""
          });
        };

        const visible = (element) => {
          if (!element) return false;
          const style = window.getComputedStyle(element);
          const rect = element.getBoundingClientRect();
          return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0;
        };

        const sleep = (milliseconds) => new Promise((done) => window.setTimeout(done, milliseconds));

        const findEditor = () =>
          document.querySelector(".comment-container textarea[tabindex='2']") ||
          document.querySelector("textarea[tabindex='2']") ||
          document.querySelector(".vditor textarea") ||
          document.querySelector(".vditor [contenteditable='true']") ||
          document.querySelector(".milkdown .editor") ||
          document.querySelector(".milkdown [contenteditable='true']") ||
          document.querySelector(".ProseMirror") ||
          document.querySelector("[contenteditable='true']") ||
          document.querySelector("textarea");

        const findSubmitButton = () => {
          const selectorButton = document.querySelector("button.submit.btn:not(:disabled)");
          const buttons = Array.from(document.querySelectorAll("button, input[type='button'], input[type='submit']"));
          const textButton = buttons.find((button) => {
            const text = (button.innerText || button.textContent || button.value || "").trim();
            return visible(button) && !button.disabled && /发送|提交|评论|回复|发布|submit|send|comment|reply/i.test(text);
          });
          return selectorButton || textButton;
        };

        const waitFor = async (finder, milliseconds) => {
          const deadline = Date.now() + milliseconds;
          while (Date.now() < deadline) {
            const element = finder();
            if (element) return element;
            await sleep(150);
          }
          return finder();
        };

        const editor = await waitFor(findEditor, Math.min(5000, timeoutMs));

        if (!editor) {
          finish({ ok: false, reason: "editor_not_found" });
          return;
        }

        editor.focus();
        editor.dispatchEvent(new MouseEvent("mousedown", { bubbles: true }));
        editor.dispatchEvent(new MouseEvent("mouseup", { bubbles: true }));
        editor.click();

        const readText = (target) => {
          if ("value" in target) return target.value || "";
          return target.innerText || target.textContent || "";
        };

        const readRenderedText = (target) => [
          readText(target),
          document.querySelector(".vditor-reset")?.innerText || "",
          document.querySelector(".vditor-ir textarea")?.value || "",
          document.querySelector(".milkdown .editor")?.innerText || "",
          document.querySelector(".ProseMirror")?.innerText || "",
          document.querySelector("[contenteditable='true']")?.innerText || ""
        ].join("\\n");

        const setText = async (target, text) => {
          const assignText = (value) => {
            if ("value" in target) {
              const descriptor = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(target), "value");
              if (descriptor && descriptor.set) {
                descriptor.set.call(target, value);
              } else {
                target.value = value;
              }
            } else {
              target.textContent = value;
            }
            target.dispatchEvent(new InputEvent("input", {
              inputType: "insertText",
              data: value,
              bubbles: true,
              cancelable: true
            }));
            target.dispatchEvent(new Event("change", { bubbles: true }));
          };

          assignText("");
          if ("select" in target) {
            target.select();
          }
          document.execCommand("selectAll", false, null);

          if ("value" in target) {
            try {
              target.setSelectionRange(0, target.value.length);
            } catch (_) {}
          }

          try {
            target.dispatchEvent(new InputEvent("beforeinput", {
              inputType: "insertFromPaste",
              data: text,
              bubbles: true,
              cancelable: true
            }));
          } catch (_) {}

          try {
            const dataTransfer = new DataTransfer();
            dataTransfer.setData("text/plain", text);
            target.dispatchEvent(new ClipboardEvent("paste", {
              clipboardData: dataTransfer,
              bubbles: true,
              cancelable: true
            }));
          } catch (_) {}

          await sleep(120);

          if (!readRenderedText(target).includes(text)) {
            assignText(text);
          }

          await sleep(120);

          if (!readRenderedText(target).includes(text)) {
            try {
              if ("select" in target) {
                target.select();
              }
              document.execCommand("selectAll", false, null);
              document.execCommand("insertText", false, text);
              target.dispatchEvent(new InputEvent("input", {
                inputType: "insertText",
                data: text,
                bubbles: true,
                cancelable: true
              }));
            } catch (_) {}
          }

          await sleep(120);

          if (!readRenderedText(target).includes(text)) {
            if ("select" in target) {
              target.select();
            }
            document.execCommand("selectAll", false, null);
            for (const char of text) {
              document.execCommand("insertText", false, char);
              target.dispatchEvent(new InputEvent("input", {
                inputType: "insertText",
                data: char,
                bubbles: true,
                cancelable: true
              }));
              await sleep(8);
            }
          }

          target.dispatchEvent(new KeyboardEvent("keydown", { key: " ", keyCode: 32, bubbles: true }));
          target.dispatchEvent(new KeyboardEvent("keyup", { key: " ", keyCode: 32, bubbles: true }));
        };

        await setText(editor, commentText);

        if (!readRenderedText(editor).includes(commentText)) {
          finish({ ok: false, reason: "fill_failed", body: readRenderedText(editor) });
          return;
        }

        if (originalFetch) {
          window.fetch = function(input, init) {
            const requestURL = typeof input === "string" ? input : (input && input.url);
            const promise = originalFetch.apply(this, arguments);
            if (isCommentRequest(requestURL)) {
              promise
                .then((response) => response.clone().text()
                  .then((body) => parseResponseBody(response.status, body))
                  .catch(() => parseResponseBody(response.status, "")))
                .catch((error) => finish({
                  ok: false,
                  reason: "network_error",
                  message: String(error && error.message ? error.message : error)
                }));
            }
            return promise;
          };
        }

        if (originalXHROpen && originalXHRSend) {
          window.XMLHttpRequest.prototype.open = function(method, url) {
            this.__nodeseekCommentURL = url;
            return originalXHROpen.apply(this, arguments);
          };
          window.XMLHttpRequest.prototype.send = function() {
            if (isCommentRequest(this.__nodeseekCommentURL)) {
              this.addEventListener("loadend", () => {
                parseResponseBody(this.status, this.responseText || "");
              });
              this.addEventListener("error", () => finish({ ok: false, reason: "network_error" }));
            }
            return originalXHRSend.apply(this, arguments);
          };
        }

        const submitButton = await waitFor(findSubmitButton, Math.min(5000, timeoutMs));

        if (!submitButton || !visible(submitButton) || submitButton.disabled) {
          finish({ ok: false, reason: "submit_button_not_found" });
          return;
        }

        timer = window.setTimeout(() => {
          finish({ ok: false, reason: "submit_timeout" });
        }, timeoutMs);

        submitButton.dispatchEvent(new MouseEvent("mousedown", { bubbles: true }));
        submitButton.dispatchEvent(new MouseEvent("mouseup", { bubbles: true }));
        submitButton.click();
      } catch (error) {
        finish({
          ok: false,
          reason: "javascript_exception",
          message: String(error && error.message ? error.message : error)
        });
      }
    });
    """
}
