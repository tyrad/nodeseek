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

      const keysOf = (value) => value && typeof value === "object" ? Object.keys(value).sort() : [];
      const hasCurrentMarker = (item) => Boolean(item && (item.current || item.isCurrent || item.self || item.isSelf || item.mine));
      const configUser = window.__config__ && window.__config__.user;
      const bodyText = String(document.body && document.body.innerText || "");
      const hasGuestSignInHint = bodyText.includes("登录后签到") || Boolean(document.querySelector("a[href='/signIn.html'], a[href='signIn.html']"));

      try {
        timer = window.setTimeout(() => {
          finish({
            ok: false,
            statusCode: null,
            reason: "board_state_timeout",
            response: {
              isLoggedIn: Boolean(configUser) && !hasGuestSignInHint,
              isCheckedIn: false,
              message: "board state timeout",
              detectionSource: "timeout",
              responseKeys: []
            }
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
            response: {
              isLoggedIn: Boolean(configUser) && !hasGuestSignInHint,
              isCheckedIn: false,
              message: parsed.error,
              detectionSource: "invalid_json",
              responseKeys: []
            }
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
            response: {
              isLoggedIn: Boolean(configUser) && !hasGuestSignInHint,
              isCheckedIn: false,
              message: "board payload is not an object",
              detectionSource: "invalid_board_payload",
              responseKeys: []
            }
          });
          return;
        }

        const responseKeys = keysOf(json);
        const hasBoardPayload = Object.prototype.hasOwnProperty.call(json, "record") || Object.prototype.hasOwnProperty.call(json, "memberList");
        if (isSuccessfulStatus && !hasGuestSignInHint && !hasBoardPayload) {
          finish({
            ok: false,
            statusCode: response.status,
            reason: "invalid_board_payload",
            message: "missing attendance board fields",
            response: {
              isLoggedIn: Boolean(configUser),
              isCheckedIn: false,
              message: json.message || json.msg || json.error || "missing attendance board fields",
              detectionSource: "invalid_board_payload",
              responseKeys
            }
          });
          return;
        }

        const record = Array.isArray(json.record) ? json.record : [];
        const memberList = Array.isArray(json.memberList) ? json.memberList : [];
        const hasOwnRecordObject = json.record && typeof json.record === "object" && !Array.isArray(json.record) && Object.keys(json.record).length > 0;
        const hasCurrentRecord = hasOwnRecordObject || record.some(hasCurrentMarker) || memberList.some(hasCurrentMarker);
        const isLoggedIn = !hasGuestSignInHint && (Boolean(configUser) || hasCurrentRecord);
        const isCheckedIn = isSuccessfulStatus && hasCurrentRecord;
        finish({
          ok: isSuccessfulStatus,
          statusCode: response.status,
          reason: isSuccessfulStatus ? "loaded" : "server_error",
          response: {
            isLoggedIn,
            isCheckedIn,
            message: json.message || json.msg || json.error || null,
            detectionSource: hasGuestSignInHint ? "guest_hint" : (configUser ? "window_config_user" : "board_api"),
            responseKeys
          }
        });
      } catch (error) {
        finish({
          ok: false,
          statusCode: null,
          reason: "network_error",
          message: String(error && error.message ? error.message : error),
          response: {
            isLoggedIn: Boolean(configUser) && !hasGuestSignInHint,
            isCheckedIn: false,
            message: String(error && error.message ? error.message : error),
            detectionSource: "network_error",
            responseKeys: []
          }
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
        try {
          return JSON.parse(body || "{}");
        } catch (_) {
          return {};
        }
      };

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
            }
          });
        }, timeoutMs);

        const response = await window.fetch("/api/attendance?random=" + randomValue, {
          method: "POST",
          credentials: "include",
          headers: { "Accept": "application/json" }
        });
        const body = await response.text();
        const json = parseJSON(body);
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
          reason
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
          }
        });
      }
    });
    """
}
