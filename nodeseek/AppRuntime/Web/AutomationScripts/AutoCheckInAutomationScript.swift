//
//  AutoCheckInAutomationScript.swift
//  nodeseek
//

import Foundation

enum AutoCheckInAutomationScript {
    static let boardStateSource = """
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
        if (body.trim().length === 0) {
          return { value: null, error: "empty response" };
        }
        try {
          return { value: JSON.parse(body), error: null };
        } catch (error) {
          return {
            value: null,
            error: String(error && error.message ? error.message : error)
          };
        }
      };

      const pageDiagnostics = () => ({
        pageHref: String(location.href || ""),
        hasConfigUser: Boolean(window.__config__ && window.__config__.user)
      });

      const boardDiagnostics = (response, body, json) => {
        const record = json && json.record;
        const recordType = record === null ? "null" : (record && typeof record === "object" && !Array.isArray(record) ? "object" : typeof record);
        const gain = record && typeof record === "object" && typeof record.gain === "number" ? record.gain : null;
        return Object.assign(pageDiagnostics(), {
          fetchURL: String(response && response.url || ""),
          contentType: String(response && response.headers && response.headers.get("content-type") || ""),
          bodyLength: typeof body === "string" ? body.length : 0,
          recordType,
          keys: json && typeof json === "object" ? Object.keys(json).sort() : [],
          listLength: json && Array.isArray(json.list) ? json.list.length : null,
          order: json && typeof json.order === "number" ? json.order : null,
          total: json && typeof json.total === "number" ? json.total : null,
          gain
        });
      };

      try {
        timer = window.setTimeout(() => {
          finish({
            ok: false,
            statusCode: null,
            reason: "board_state_timeout",
            message: "board state timeout",
            response: null,
            diagnostics: pageDiagnostics()
          });
        }, timeoutMs);

        const response = await window.fetch("/api/attendance/board?page=1", {
          method: "GET",
          credentials: "include",
          headers: { "Accept": "application/json" }
        });
        const isSuccessfulStatus = response.status >= 200 && response.status < 300;
        const body = await response.text();
        const parsed = parseJSON(body);
        if (parsed.error) {
          finish({
            ok: false,
            statusCode: response.status,
            reason: "invalid_json",
            message: parsed.error,
            response: null,
            diagnostics: Object.assign(pageDiagnostics(), {
              fetchURL: String(response.url || ""),
              contentType: String(response.headers && response.headers.get("content-type") || ""),
              bodyLength: body.length,
              bodyHead: body.split("\\n").join(" ").split("\\r").join(" ").slice(0, 80)
            })
          });
          return;
        }

        const json = parsed.value && typeof parsed.value === "object" && !Array.isArray(parsed.value) ? parsed.value : null;
        if (!json) {
          finish({
            ok: false,
            statusCode: response.status,
            reason: "invalid_board_payload",
            message: "board payload is not an object",
            response: null,
            diagnostics: Object.assign(pageDiagnostics(), {
              fetchURL: String(response.url || ""),
              bodyLength: body.length
            })
          });
          return;
        }

        finish({
          ok: isSuccessfulStatus,
          statusCode: response.status,
          reason: isSuccessfulStatus ? "loaded" : "server_error",
          response: json,
          diagnostics: boardDiagnostics(response, body, json)
        });
      } catch (error) {
        finish({
          ok: false,
          statusCode: null,
          reason: "network_error",
          message: String(error && error.message ? error.message : error),
          response: null,
          diagnostics: pageDiagnostics()
        });
      }
    });
    """

    static let submitSource = """
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
        if ((body || "").trim().length === 0) {
          return { value: null, error: "empty response" };
        }
        try {
          return { value: JSON.parse(body), error: null };
        } catch (error) {
          return {
            value: null,
            error: String(error && error.message ? error.message : error)
          };
        }
      };

      const pageDiagnostics = () => ({
        pageHref: String(location.href || ""),
        hasConfigUser: Boolean(window.__config__ && window.__config__.user),
        randomValue: String(randomValue)
      });

      try {
        timer = window.setTimeout(() => {
          finish({
            ok: false,
            statusCode: null,
            reason: "submit_timeout",
            response: {
              success: false,
              message: "submit timeout",
              current: null
            },
            diagnostics: pageDiagnostics()
          });
        }, timeoutMs);

        const response = await window.fetch("/api/attendance?random=" + randomValue, {
          method: "POST",
          credentials: "include",
          headers: { "Accept": "application/json" }
        });
        const body = await response.text();
        const parsed = parseJSON(body);
        if (parsed.error) {
          finish({
            ok: false,
            statusCode: response.status,
            reason: "invalid_json",
            message: parsed.error,
            response: {
              success: null,
              message: parsed.error,
              current: null
            },
            diagnostics: Object.assign(pageDiagnostics(), {
              fetchURL: String(response.url || ""),
              contentType: String(response.headers && response.headers.get("content-type") || ""),
              bodyLength: body.length,
              bodyHead: body.split("\\n").join(" ").split("\\r").join(" ").slice(0, 80)
            })
          });
          return;
        }

        const json = parsed.value && typeof parsed.value === "object" && !Array.isArray(parsed.value) ? parsed.value : {};
        const success = typeof json.success === "boolean" ? json.success : null;
        const isSuccess = json.success === true;
        const isSuccessfulStatus = response.status >= 200 && response.status < 300;
        const reason = isSuccessfulStatus && isSuccess ? "submitted" : (isSuccessfulStatus && success === null ? "invalid_script_result" : "server_error");
        finish({
          ok: isSuccessfulStatus && isSuccess,
          statusCode: response.status,
          response: {
            success,
            message: json.message || json.msg || json.error || null,
            current: typeof json.current === "number" ? json.current : null
          },
          reason,
          diagnostics: Object.assign(pageDiagnostics(), {
            fetchURL: String(response.url || ""),
            contentType: String(response.headers && response.headers.get("content-type") || ""),
            bodyLength: body.length,
            keys: Object.keys(json).sort(),
            successType: typeof json.success
          })
        });
      } catch (error) {
        const message = String(error && error.message ? error.message : error);
        finish({
          ok: false,
          statusCode: null,
          reason: "network_error",
          message,
          response: {
            success: null,
            message,
            current: null
          },
          diagnostics: pageDiagnostics()
        });
      }
    });
    """
}
