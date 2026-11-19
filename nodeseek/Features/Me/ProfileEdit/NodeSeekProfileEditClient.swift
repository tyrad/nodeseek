//
//  NodeSeekProfileEditClient.swift
//  nodeseek
//

import Foundation

protocol ProfileEditClienting: AnyObject {
    func loadIntroduction(uid: Int) async throws -> ProfileIntroduction
    func saveIntroduction(_ introduction: ProfileIntroduction) async throws
    /// 提前在隐藏 WebView 里打开首页，保存和上传头像时不用再等页面加载。
    func prepareForSaving()
}

/// 读写个人信息设置页的 Bio、签名、Readme，接口与网页 /setting#introduction 一致。
final class NodeSeekProfileEditClient: ProfileEditClienting {
    private let session: URLSession
    private let baseURL: URL
    private let submitter: UserFollowSubmitting

    init(
        session: URLSession = .shared,
        baseURL: URL = NodeSeekSite.baseURL,
        submitter: UserFollowSubmitting? = nil
    ) {
        self.session = session
        self.baseURL = baseURL
        self.submitter = submitter ?? WebViewUserFollowSubmitter(actionName: "保存个人信息")
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

    func prepareForSaving() {
        let pageURL = baseURL
        Task { @MainActor in
            do {
                try await withHiddenWebViewPageActionLoader(logMessage: "预热编辑资料保存页") { loader in
                    try await loader.prepareAutomationPage(pageURL: pageURL, timeoutInterval: 20, reason: "编辑资料打开预热")
                }
            } catch {
                AppLog.warning(.webView, "编辑资料保存页预热失败: error=\(error.localizedDescription)")
            }
        }
    }

    func saveIntroduction(_ introduction: ProfileIntroduction) async throws {
        let body = try JSONEncoder().encode([
            "bio": introduction.bio,
            "signature": introduction.signature,
            "readme": introduction.readme
        ])
        // App 直接 POST 会被站点 403，和关注一样在隐藏 WebView 的首页里发同源请求。
        try await submitter.submit(
            apiPath: "/api/account/introduction",
            bodyJSON: String(decoding: body, as: UTF8.self),
            referer: baseURL
        )
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
