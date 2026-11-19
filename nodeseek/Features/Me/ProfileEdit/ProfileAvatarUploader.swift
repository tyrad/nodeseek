//
//  ProfileAvatarUploader.swift
//  nodeseek
//

import Foundation

protocol ProfileAvatarUploading: AnyObject {
    /// 上传已裁好的 PNG；失败时抛出可直接展示的错误。
    @MainActor func upload(pngData: Data) async throws
}

/// 上传头像，表单字段与网页设置页的裁剪上传组件一致。
/// 和保存资料一样，App 直接 POST 会被站点拒绝，所以在隐藏 WebView 的首页里发同源请求。
final class WebViewProfileAvatarUploader: ProfileAvatarUploading {
    private let timeoutInterval: TimeInterval

    init(timeoutInterval: TimeInterval = 30) {
        self.timeoutInterval = timeoutInterval
    }

    @MainActor
    func upload(pngData: Data) async throws {
        let startedAt = Date()
        let timeoutInterval = timeoutInterval
        let object = try await withHiddenWebViewPageActionLoader(
            logMessage: "准备通过隐藏 WebView 上传头像: bytes=\(pngData.count)"
        ) { loader in
            try await loader.runPageAutomationScript(
                pageURL: NodeSeekSite.baseURL,
                source: Self.script,
                arguments: ["imageBase64": pngData.base64EncodedString()],
                timeoutInterval: timeoutInterval,
                actionName: "上传头像"
            )
        }
        let ok = object["ok"] as? Bool ?? false
        let status = (object["statusCode"] as? NSNumber)?.intValue
        let message = object["message"] as? String
        AppLog.info(
            .webView,
            "上传头像 WebView 请求结束: ok=\(ok), status=\(status.map(String.init) ?? "nil"), message=\(message ?? "nil"), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))"
        )
        guard ok else {
            throw UserContentClientError.rejected(Self.failureMessage(status: status, message: message))
        }
    }

    static func failureMessage(status: Int?, message: String?) -> String {
        if status == 429 {
            return NSLocalizedString("上传时间最短间隔为一分钟", tableName: "Me", comment: "")
        }
        if let message, !message.isEmpty { return message }
        if let status {
            return String(format: NSLocalizedString("头像上传失败（HTTP %ld）", tableName: "Me", comment: ""), status)
        }
        return NSLocalizedString("头像上传失败，请稍后重试", tableName: "Me", comment: "")
    }

    private static let script = """
    return await new Promise(async (resolve) => {
      let resolved = false;
      const finish = (payload) => {
        if (resolved) return;
        resolved = true;
        resolve(payload);
      };
      window.setTimeout(() => finish({ ok: false, reason: "submit_timeout" }), timeoutMs);
      try {
        const binary = atob(imageBase64);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
        const form = new FormData();
        form.append("token", "123456798");
        form.append("name", "avatar");
        form.append("img", new Blob([bytes], { type: "image/png" }), "img.png");
        const response = await window.fetch("/api/avatar/upload", {
          method: "POST",
          credentials: "include",
          headers: { "x-csrf-challenge": "simple-token" },
          body: form
        });
        const body = await response.text();
        let json = {};
        try { json = JSON.parse(body) || {}; } catch (_) {}
        const ok = response.status >= 200 && response.status < 300 && json.success !== false;
        finish({ ok, statusCode: response.status, message: json.message || null });
      } catch (error) {
        finish({ ok: false, reason: "network_error", message: String(error && error.message ? error.message : error) });
      }
    });
    """
}
