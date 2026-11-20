//
//  NodeSeekProfileEditClient.swift
//  nodeseek
//

import Foundation

protocol ProfileEditClienting: AnyObject {
    func loadIntroduction(uid: Int) async throws -> ProfileIntroduction
    func saveIntroduction(_ introduction: ProfileIntroduction) async throws
}

/// 读写个人信息设置页的 Bio、签名、Readme，接口与网页 /setting#introduction 一致。
final class NodeSeekProfileEditClient: ProfileEditClienting {
    private let session: URLSession
    private let baseURL: URL
    private let fallbackSubmitter: UserFollowSubmitting

    init(
        session: URLSession = .shared,
        baseURL: URL = NodeSeekSite.baseURL,
        fallbackSubmitter: UserFollowSubmitting? = nil
    ) {
        self.session = session
        self.baseURL = baseURL
        self.fallbackSubmitter = fallbackSubmitter ?? WebViewUserFollowSubmitter(actionName: "保存个人信息")
    }

    func loadIntroduction(uid: Int) async throws -> ProfileIntroduction {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/account/getInfo/\(uid)"
        // 签名要取 Markdown 原文，默认返回的是渲染后的 HTML。
        components?.queryItems = [URLQueryItem(name: "readme", value: "1"), URLQueryItem(name: "signature", value: "1")]
        var request = URLRequest(url: components?.url ?? baseURL)
        WebRequestFingerprint.applyJSONHeaders(to: &request, referer: NodeSeekSite.profileSettingsURL)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UserContentClientError.httpStatus(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(IntroductionResponse.self, from: data)
        guard decoded.success, let detail = decoded.detail else {
            throw decoded.message.map(UserContentClientError.rejected) ?? UserContentClientError.unsuccessfulResponse
        }
        return ProfileIntroduction(bio: detail.bio ?? "", signature: detail.signatureMarkdown ?? "", readme: detail.readme ?? "")
    }

    /// 直接调接口；被站点拦下（403 或验证页）时退回隐藏 WebView 里的同源请求再试一次。
    func saveIntroduction(_ introduction: ProfileIntroduction) async throws {
        let body = try JSONEncoder().encode([
            "bio": introduction.bio,
            "signature": introduction.signature,
            "readme": introduction.readme
        ])
        var request = URLRequest(url: baseURL.appendingPathComponent("api/account/introduction"))
        request.httpMethod = "POST"
        WebRequestFingerprint.applyJSONHeaders(to: &request, referer: NodeSeekSite.profileSettingsURL)
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let result = ProfileWriteResult(status: status, data: data) else {
            AppLog.warning(.webView, "保存个人信息直接请求被拦截，改用隐藏 WebView: status=\(status)")
            try await fallbackSubmitter.submit(
                apiPath: "/api/account/introduction",
                bodyJSON: String(decoding: body, as: UTF8.self),
                referer: baseURL
            )
            return
        }
        guard result.success else {
            throw result.message.map(UserContentClientError.rejected)
                ?? UserContentClientError.httpStatus(status)
        }
    }
}

/// 写接口的返回：站点正常处理时总是 JSON；拿不到 JSON（403、验证页）说明请求被拦，返回 nil 让调用方兜底。
nonisolated struct ProfileWriteResult: Equatable {
    let success: Bool
    let message: String?

    init?(status: Int, data: Data) {
        guard status != 403,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // 限流等错误可能不带 success 字段，按状态码判断。
        success = (200..<300).contains(status) && (object["success"] as? Bool ?? true)
        message = object["message"] as? String
    }
}

private struct IntroductionResponse: Decodable {
    let success: Bool
    let message: String?
    let detail: Detail?

    struct Detail: Decodable {
        let bio: String?
        let signatureMarkdown: String?
        let readme: String?

        private enum CodingKeys: String, CodingKey {
            case bio
            case signatureMarkdown = "signature_markdown"
            case readme
        }
    }
}
