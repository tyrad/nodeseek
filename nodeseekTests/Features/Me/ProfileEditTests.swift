//
//  ProfileEditTests.swift
//  nodeseekTests
//

import Foundation
import Testing
import UIKit
@testable import nodeseek

struct ProfileSignatureValidatorTests {
    @Test func plainMarkdownSignaturePasses() {
        #expect(ProfileSignatureValidator.validationMessage(for: "[博客](https://example.com) | **粗体**") == nil)
    }

    @Test func blockquoteIsRejectedOutsideCodeFence() {
        #expect(ProfileSignatureValidator.validationMessage(for: "第一行\n  > 引用") == "签名不允许使用引用")
        #expect(ProfileSignatureValidator.validationMessage(for: "```\n> 代码里的符号\n```") == nil)
        // 缩进四格是代码块，不是引用。
        #expect(ProfileSignatureValidator.validationMessage(for: "    > code") == nil)
    }

    @Test func imagesAreRejected() {
        #expect(ProfileSignatureValidator.validationMessage(for: "![logo](https://example.com/a.png)") == "签名不允许使用图片")
        #expect(ProfileSignatureValidator.validationMessage(for: #"<IMG src="a.png">"#) == "签名不允许使用图片")
    }

    @Test func extendedEmojiAreListed() {
        let message = ProfileSignatureValidator.validationMessage(for: "你好😀 ☺ 👍")
        #expect(message == "签名只支持 Unicode 1.1，不支持扩展 emoji：😀👍")
    }
}

@MainActor
struct ProfileFieldEditorPresenterTests {
    private let original = ProfileIntroduction(bio: "一句话", signature: "旧签名", readme: "# 旧 Readme")

    @Test func unchangedSignatureCannotBeSavedAndClosesDirectly() {
        let (presenter, view, _) = makePresenter(field: .signature)
        presenter.viewDidLoad()

        #expect(view.filledDrafts.map(\.content) == ["旧签名"])
        #expect(presenter.state.saveStatus == .unchanged)
        #expect(presenter.state.fieldTitle == "签名")
        #expect(presenter.state.hiddenToolbarItems == [.photo, .sticker])
        #expect(presenter.state.allowsQuote == false)
        #expect(presenter.closeDecision() == .close)
    }

    @Test func changedContentAsksBeforeClosingWithoutLocalDraft() {
        let (presenter, _, _) = makePresenter(field: .readme)
        presenter.viewDidLoad()
        presenter.didChangeContent("# 新 Readme")

        #expect(presenter.state.saveStatus == .empty)
        #expect(presenter.state.canPublish)
        #expect(presenter.state.hiddenToolbarItems.isEmpty)
        #expect(presenter.closeDecision() == .askSaveOrDiscardEdit)
    }

    @Test func invalidSignatureShowsMessageAndDoesNotSubmit() async {
        let (presenter, view, client) = makePresenter(field: .signature)
        presenter.viewDidLoad()
        presenter.didChangeContent("> 引用")
        presenter.didTapPublish()
        await Task.yield()

        #expect(view.validationMessages == ["签名不允许使用引用"])
        #expect(client.saved.isEmpty)
    }

    @Test func savingReadmeKeepsOtherFields() async throws {
        let (presenter, _, client) = makePresenter(field: .readme)
        presenter.viewDidLoad()
        presenter.didChangeContent("# 新 Readme")
        presenter.didTapPublish()
        #expect(presenter.state.isSubmitting)
        #expect(presenter.closeDecision() == .blocked)

        for _ in 0..<20 where client.saved.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        let expected = ProfileIntroduction(bio: "一句话", signature: "旧签名", readme: "# 新 Readme")
        #expect(client.saved == [expected])
    }

    @Test func saveFailureAllowsRetry() async throws {
        let (presenter, view, client) = makePresenter(field: .signature)
        client.error = UserContentClientError.rejected("签名太长")
        presenter.viewDidLoad()
        presenter.didChangeContent("新签名")
        presenter.didTapPublish()

        for _ in 0..<20 where view.failures.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(view.failures.map(\.message) == ["签名太长"])
        #expect(view.failures.first?.allowsRetry == true)
        #expect(presenter.state.isSubmitting == false)
    }

    private func makePresenter(
        field: ProfileFieldEditorPresenter.Field,
        onSaved: @escaping (ProfileIntroduction) -> Void = { _ in }
    ) -> (ProfileFieldEditorPresenter, ProfileSpyEditorView, ProfileEditClientStub) {
        let client = ProfileEditClientStub()
        let presenter = ProfileFieldEditorPresenter(field: field, original: original, client: client, onSaved: onSaved)
        let view = ProfileSpyEditorView()
        presenter.view = view
        return (presenter, view, client)
    }
}

@Suite(.serialized)
struct NodeSeekProfileEditClientTests {
    private func mockSession(status: Int, body: String) -> URLSession {
        ProfileEditMockURLProtocol.statusCode = status
        ProfileEditMockURLProtocol.body = body
        ProfileEditMockURLProtocol.lastRequest = nil
        ProfileEditMockURLProtocol.lastBody = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileEditMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test func loadReadsSignatureMarkdown() async throws {
        let session = mockSession(status: 200, body: ##"{"success":true,"detail":{"member_id":1,"bio":"hi","signature":"<p>html</p>","signature_markdown":"**md**","readme":"# r"}}"##)
        let client = NodeSeekProfileEditClient(session: session, fallbackSubmitter: ProfileSubmitterStub())

        let introduction = try await client.loadIntroduction(uid: 31037)

        #expect(introduction == ProfileIntroduction(bio: "hi", signature: "**md**", readme: "# r"))
        #expect(ProfileEditMockURLProtocol.lastRequest?.url?.absoluteString == "https://www.nodeseek.com/api/account/getInfo/31037?readme=1&signature=1")
    }

    @Test func saveCallsAPIDirectlyWithAllThreeFields() async throws {
        let fallback = ProfileSubmitterStub()
        let client = NodeSeekProfileEditClient(session: mockSession(status: 200, body: #"{"success":true}"#), fallbackSubmitter: fallback)

        try await client.saveIntroduction(ProfileIntroduction(bio: "b", signature: "s", readme: "r"))

        let request = try #require(ProfileEditMockURLProtocol.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://www.nodeseek.com/api/account/introduction")
        let body = try JSONSerialization.jsonObject(with: try #require(ProfileEditMockURLProtocol.lastBody)) as? [String: String]
        #expect(body == ["bio": "b", "signature": "s", "readme": "r"])
        #expect(fallback.calls.isEmpty)
    }

    @Test func blockedSaveFallsBackToWebView() async throws {
        let fallback = ProfileSubmitterStub()
        let client = NodeSeekProfileEditClient(session: mockSession(status: 403, body: "<html>Just a moment...</html>"), fallbackSubmitter: fallback)

        try await client.saveIntroduction(ProfileIntroduction(bio: "b", signature: "s", readme: "r"))

        let call = try #require(fallback.calls.first)
        #expect(call.apiPath == "/api/account/introduction")
        let body = try JSONSerialization.jsonObject(with: Data(call.bodyJSON.utf8)) as? [String: String]
        #expect(body == ["bio": "b", "signature": "s", "readme": "r"])
    }

    @Test func rejectedSaveShowsServerMessageWithoutFallback() async throws {
        let fallback = ProfileSubmitterStub()
        let client = NodeSeekProfileEditClient(session: mockSession(status: 200, body: #"{"success":false,"message":"签名过长"}"#), fallbackSubmitter: fallback)

        await #expect(throws: UserContentClientError.self) {
            try await client.saveIntroduction(ProfileIntroduction(signature: "很长"))
        }
        #expect(fallback.calls.isEmpty)
    }

    @Test @MainActor func avatarUploadsDirectlyAsWebForm() async throws {
        let fallback = ProfileAvatarUploaderStub()
        let uploader = NodeSeekProfileAvatarUploader(session: mockSession(status: 200, body: #"{"success":true,"uid":1}"#), fallback: fallback)

        try await uploader.upload(pngData: Data([0x89, 0x50, 0x4E, 0x47]))

        let request = try #require(ProfileEditMockURLProtocol.lastRequest)
        #expect(request.url?.path == "/api/avatar/upload")
        #expect(request.value(forHTTPHeaderField: "x-csrf-challenge") == "simple-token")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let body = String(decoding: try #require(ProfileEditMockURLProtocol.lastBody), as: UTF8.self)
        #expect(body.contains(#"name="token""#) && body.contains("123456798"))
        #expect(body.contains(#"name="img"; filename="img.png""#))
        #expect(fallback.uploads == 0)
    }

    @Test @MainActor func blockedAvatarUploadFallsBackButRateLimitDoesNot() async throws {
        let fallback = ProfileAvatarUploaderStub()
        try await NodeSeekProfileAvatarUploader(session: mockSession(status: 403, body: "blocked"), fallback: fallback)
            .upload(pngData: Data([1]))
        #expect(fallback.uploads == 1)

        await #expect(throws: UserContentClientError.self) {
            try await NodeSeekProfileAvatarUploader(session: mockSession(status: 429, body: "Too Many Requests"), fallback: fallback)
                .upload(pngData: Data([1]))
        }
        #expect(fallback.uploads == 1)
    }
}

private final class ProfileAvatarUploaderStub: ProfileAvatarUploading {
    var uploads = 0
    func upload(pngData: Data) async throws { uploads += 1 }
}

private final class ProfileEditClientStub: ProfileEditClienting {
    var saved: [ProfileIntroduction] = []
    var error: Error?
    var loadError: Error?

    func loadIntroduction(uid: Int) async throws -> ProfileIntroduction {
        if let loadError { throw loadError }
        return ProfileIntroduction()
    }

    func saveIntroduction(_ introduction: ProfileIntroduction) async throws {
        if let error { throw error }
        saved.append(introduction)
    }
}

private final class ProfileSubmitterStub: UserFollowSubmitting, @unchecked Sendable {
    var calls: [(apiPath: String, bodyJSON: String, referer: URL)] = []
    func submit(apiPath: String, bodyJSON: String, referer: URL) async throws {
        calls.append((apiPath, bodyJSON, referer))
    }
}

private final class ProfileSpyEditorView: NewDiscussionViewProtocol {
    private(set) var filledDrafts: [NewDiscussionDraft] = []
    private(set) var validationMessages: [String] = []
    private(set) var failures: [(title: String, message: String, allowsRetry: Bool)] = []

    func render(_ state: NewDiscussionViewState) {}
    func fill(_ draft: NewDiscussionDraft) { filledDrafts.append(draft) }
    func showValidationMessage(_ message: String) { validationMessages.append(message) }
    func confirmChickenLegFee(_ fee: Int, onConfirm: @escaping () -> Void) {}
    func confirmPrivateRankFee(_ fee: Int, onConfirm: @escaping () -> Void) {}
    func showSubmitFailure(title: String, message: String, allowsRetry: Bool) {
        failures.append((title, message, allowsRetry))
    }
}

private final class ProfileEditMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var body = ""
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        // URLSession 把 httpBody 转成了流，要从流里读回来。
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map(Self.read)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

@MainActor
struct ProfileAvatarTests {
    @Test func cropOutputsWebSizedSquareFromSelectedRegion() throws {
        // 左半红、右半蓝的 200×100 图，裁右半边应该全是蓝色。
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
        }

        let cropped = ProfileAvatarCropViewController.crop(source, to: CGRect(x: 100, y: 0, width: 100, height: 100))

        #expect(cropped.size == CGSize(width: 100, height: 100))
        #expect(cropped.scale == 1)
        let pixel = try #require(Self.centerPixel(of: cropped))
        #expect(pixel.blue > 200 && pixel.red < 50)
    }

    @Test func rateLimitFailureExplainsOneMinuteInterval() {
        #expect(WebViewProfileAvatarUploader.failureMessage(status: 429, message: nil) == "上传时间最短间隔为一分钟")
        #expect(WebViewProfileAvatarUploader.failureMessage(status: 500, message: "图片太大") == "图片太大")
        #expect(WebViewProfileAvatarUploader.failureMessage(status: 403, message: nil) == "头像上传失败（HTTP 403）")
    }

    private static func centerPixel(of image: UIImage) -> (red: UInt8, blue: UInt8)? {
        guard let cgImage = image.cgImage else { return nil }
        var data = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: -50, y: -50, width: 100, height: 100))
        return (data[0], data[2])
    }
}

@MainActor
struct HiddenWebViewAutomationPageMatchTests {
    /// 站点根地址带不带 / 是同一页，否则每次保存资料都要重新加载首页。
    @Test func siteRootWithAndWithoutSlashIsSamePage() throws {
        let loaded = try #require(URL(string: "https://www.nodeseek.com/"))
        #expect(HiddenWebViewLoader.isSameAutomationPage(loaded, NodeSeekSite.baseURL))
        #expect(HiddenWebViewLoader.isSameAutomationPage(loaded, try #require(URL(string: "https://www.nodeseek.com/fans"))) == false)
        #expect(HiddenWebViewLoader.isSameAutomationPage(loaded, try #require(URL(string: "https://www.nodeseek.com/?page=2"))) == false)
    }
}

@MainActor
struct ProfileEditPageTests {
    @Test func loadFailureShowsRetryBelowAvatar() async throws {
        let client = ProfileEditClientStub()
        client.loadError = UserContentClientError.rejected("网络错误")
        let page = ProfileEditViewController(
            uid: 1,
            account: AccountResponse(displayName: "测试", isLoggedIn: true),
            client: client
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = UINavigationController(rootViewController: page)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        var retry: UIButton?
        for _ in 0..<50 {
            window.layoutIfNeeded()
            retry = Self.descendants(of: page.view).compactMap { $0 as? UIButton }
                .first { $0.configuration?.title == "重试" && !$0.isHidden && $0.window != nil }
            if retry != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let button = try #require(retry)
        let avatar = try #require(Self.descendants(of: page.view).first { $0.accessibilityIdentifier == "profile-edit-change-avatar" })
        let buttonFrame = button.convert(button.bounds, to: page.view)
        let avatarFrame = avatar.convert(avatar.bounds, to: page.view)
        #expect(buttonFrame.minY > avatarFrame.maxY)
        #expect(page.view.bounds.contains(buttonFrame))
    }

    private static func descendants(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap(descendants)
    }
}
