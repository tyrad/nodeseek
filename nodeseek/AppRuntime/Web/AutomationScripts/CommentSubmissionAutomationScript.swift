//
//  CommentSubmissionAutomationScript.swift
//  nodeseek
//

import Foundation

enum CommentSubmissionAutomationScript {
    static let source = """
    return await new Promise(async (resolve) => {
      const startedAt = Date.now();
      const diagnostics = [];
      const logStep = (name, details) => {
        diagnostics.push(`${Date.now() - startedAt}ms ${name}${details ? " " + details : ""}`);
      };
      let resolved = false;
      let timer = null;
      let originalFetch = window.fetch;
      const originalXHROpen = window.XMLHttpRequest && window.XMLHttpRequest.prototype.open;
      const originalXHRSend = window.XMLHttpRequest && window.XMLHttpRequest.prototype.send;
      logStep("script_start", `readyState=${document.readyState} url=${window.location.href}`);

      const finish = (payload) => {
        if (resolved) return;
        resolved = true;
        logStep("finish", `ok=${payload.ok} reason=${payload.reason || "unknown"} status=${payload.statusCode || "nil"}`);
        if (timer) window.clearTimeout(timer);
        if (originalFetch) window.fetch = originalFetch;
        if (originalXHROpen) window.XMLHttpRequest.prototype.open = originalXHROpen;
        if (originalXHRSend) window.XMLHttpRequest.prototype.send = originalXHRSend;
        resolve(Object.assign({ diagnostics }, payload));
      };

      try {
        const isCommentRequest = (url) => String(url || "").includes("/api/content/new-comment");

        const parseResponseBody = (statusCode, body) => {
          logStep("comment_response_received", `status=${statusCode} bodyLength=${(body || "").length}`);
          let json;
          try {
            json = JSON.parse(body);
          } catch (_) {
            json = null;
          }
          const httpOK = statusCode >= 200 && statusCode < 300;
          // 非 2xx 返回 HTML（登录失效、验证页、限流）时保留状态码，不归为结果未知。
          if (json === null && httpOK) {
            finish({ ok: false, statusCode, reason: "invalid_response", body: body || "" });
            return;
          }
          const message = typeof json?.message === "string" ? json.message : null;
          const success = httpOK && json?.success === true;
          const reason = success ? "submitted"
            : (!httpOK || json?.success === false ? "server_error" : "invalid_response");
          finish({ ok: success, statusCode, message, reason, body: body || "" });
        };

        const visible = (element) => {
          if (!element) return false;
          const style = window.getComputedStyle(element);
          const rect = element.getBoundingClientRect();
          return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0;
        };

        const describeElement = (element) => {
          if (!element) return "nil";
          const rect = element.getBoundingClientRect();
          const text = (element.innerText || element.textContent || element.value || "").trim().slice(0, 40);
          return `tag=${element.tagName} id=${element.id || "nil"} class=${element.className || "nil"} visible=${visible(element)} rect=${Math.round(rect.width)}x${Math.round(rect.height)} text=${text || "nil"}`;
        };

        const sleep = (milliseconds) => new Promise((done) => window.setTimeout(done, milliseconds));

        let editorAPI = null;
        const findEditor = () => {
          const root = document.querySelector("#editor");
          if (!root) return null;
          // 隐藏 WebView 的几何尺寸不能代表编辑器是否就绪。
          try {
            const api = window.editor?.cme?.();
            if (typeof api?.setValue === "function" && typeof api?.getValue === "function") {
              editorAPI = api;
              return root;
            }
          } catch (_) {}
          return Array.from(root.querySelectorAll("textarea, [contenteditable='true']"))
            .find((element) => !element.disabled && !element.readOnly) || null;
        };

        const findSubmitButton = () => {
          const root = document.querySelector("#editor");
          if (!root) return null;
          return Array.from(root.querySelectorAll("button.submit.btn"))
            .find((button) => !button.disabled) || null;
        };

        const waitFor = async (finder, milliseconds) => {
          const deadline = Date.now() + milliseconds;
          let attempts = 0;
          while (Date.now() < deadline) {
            attempts += 1;
            const element = finder();
            if (element) {
              logStep("wait_for_found", `attempts=${attempts} budgetMs=${milliseconds} ${describeElement(element)}`);
              return element;
            }
            await sleep(150);
          }
          logStep("wait_for_timeout", `attempts=${attempts} budgetMs=${milliseconds}`);
          return finder();
        };

        logStep("editor_wait_begin", `timeoutMs=${Math.min(5000, timeoutMs)}`);
        const editor = await waitFor(findEditor, Math.min(5000, timeoutMs));

        if (!editor) {
          logStep("editor_not_found");
          finish({ ok: false, reason: "editor_not_found" });
          return;
        }

        logStep("editor_found", describeElement(editor));
        if (!editorAPI) {
          editor.focus();
          editor.dispatchEvent(new MouseEvent("mousedown", { bubbles: true }));
          editor.dispatchEvent(new MouseEvent("mouseup", { bubbles: true }));
          editor.click();
          logStep("editor_focus_click_done", describeElement(editor));
        }

        const readText = (target) => {
          if ("value" in target) return target.value || "";
          return target.innerText || target.textContent || "";
        };

        const readRenderedText = (target) => editorAPI ? editorAPI.getValue() : readText(target);

        const setText = async (target, text) => {
          logStep("set_text_begin", `target=${describeElement(target)} textLength=${text.length}`);
          if (editorAPI) {
            editorAPI.setValue(text);
            await sleep(0);
            logStep("set_text_editor_api", "verified=" + (readRenderedText(target) === text));
            return;
          }
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
          logStep("set_text_clear_done", `renderedLength=${readRenderedText(target).length}`);
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

          logStep("set_text_before_paste_done");
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
          logStep("set_text_after_paste", `contains=${(readRenderedText(target) === text)} renderedLength=${readRenderedText(target).length}`);

          if (!(readRenderedText(target) === text)) {
            assignText(text);
            logStep("set_text_direct_assign_fallback", `renderedLength=${readRenderedText(target).length}`);
          }

          await sleep(120);
          logStep("set_text_after_direct_assign", `contains=${(readRenderedText(target) === text)} renderedLength=${readRenderedText(target).length}`);

          if (!(readRenderedText(target) === text)) {
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
              logStep("set_text_exec_command_fallback", `renderedLength=${readRenderedText(target).length}`);
            } catch (_) {}
          }

          await sleep(120);
          logStep("set_text_after_exec_command", `contains=${(readRenderedText(target) === text)} renderedLength=${readRenderedText(target).length}`);

          if (!(readRenderedText(target) === text)) {
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
            logStep("set_text_char_insert_fallback", `renderedLength=${readRenderedText(target).length}`);
          }

          target.dispatchEvent(new KeyboardEvent("keydown", { key: " ", keyCode: 32, bubbles: true }));
          target.dispatchEvent(new KeyboardEvent("keyup", { key: " ", keyCode: 32, bubbles: true }));
          logStep("set_text_end", `contains=${(readRenderedText(target) === text)} renderedLength=${readRenderedText(target).length}`);
        };

        await setText(editor, commentText);

        if (readRenderedText(editor) !== commentText) {
          logStep("fill_failed", `bodyLength=${readRenderedText(editor).length}`);
          finish({ ok: false, reason: "fill_failed", body: readRenderedText(editor) });
          return;
        }
        logStep("fill_verified", `commentLength=${commentText.length}`);

        if (originalFetch) {
          logStep("fetch_hook_install");
          window.fetch = function(input, init) {
            const requestURL = typeof input === "string" ? input : (input && input.url);
            const promise = originalFetch.apply(this, arguments);
            if (isCommentRequest(requestURL)) {
              logStep("fetch_comment_request_seen", `url=${requestURL}`);
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
          logStep("xhr_hook_install");
          window.XMLHttpRequest.prototype.open = function(method, url) {
            this.__nodeseekCommentURL = url;
            return originalXHROpen.apply(this, arguments);
          };
          window.XMLHttpRequest.prototype.send = function() {
            if (isCommentRequest(this.__nodeseekCommentURL)) {
              logStep("xhr_comment_request_seen", `url=${this.__nodeseekCommentURL}`);
              this.addEventListener("loadend", () => {
                parseResponseBody(this.status, this.responseText || "");
              });
              this.addEventListener("error", () => finish({ ok: false, reason: "network_error" }));
            }
            return originalXHRSend.apply(this, arguments);
          };
        }

        logStep("submit_button_wait_begin", `timeoutMs=${Math.min(5000, timeoutMs)}`);
        const submitButton = await waitFor(findSubmitButton, Math.min(5000, timeoutMs));

        if (!submitButton || submitButton.disabled) {
          logStep("submit_button_not_found", describeElement(submitButton));
          finish({ ok: false, reason: "submit_button_not_found" });
          return;
        }

        logStep("submit_button_found", describeElement(submitButton));
        timer = window.setTimeout(() => {
          logStep("submit_timeout_fired", `timeoutMs=${timeoutMs}`);
          finish({ ok: false, reason: "submit_timeout" });
        }, timeoutMs);

        logStep("submit_click_dispatch_begin", describeElement(submitButton));
        submitButton.dispatchEvent(new MouseEvent("mousedown", { bubbles: true }));
        submitButton.dispatchEvent(new MouseEvent("mouseup", { bubbles: true }));
        submitButton.click();
        logStep("submit_click_dispatch_end", describeElement(submitButton));
      } catch (error) {
        logStep("javascript_exception", String(error && error.message ? error.message : error));
        finish({
          ok: false,
          reason: "javascript_exception",
          message: String(error && error.message ? error.message : error)
        });
      }
    });
    """
}
