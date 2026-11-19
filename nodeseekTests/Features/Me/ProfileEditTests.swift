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
    @Test func loadReadsSignatureMarkdown() async throws {
        ProfileEditMockURLProtocol.body = ##"{"success":true,"detail":{"member_id":1,"bio":"hi","signature":"<p>html</p>","signature_markdown":"**md**","readme":"# r"}}"##
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileEditMockURLProtocol.self]
        let client = NodeSeekProfileEditClient(session: URLSession(configuration: configuration), submitter: ProfileSubmitterStub())

        let introduction = try await client.loadIntroduction(uid: 31037)

        #expect(introduction == ProfileIntroduction(bio: "hi", signature: "**md**", readme: "# r"))
        #expect(ProfileEditMockURLProtocol.lastRequest?.url?.absoluteString == "https://www.nodeseek.com/api/account/getInfo/31037?readme=1&signature=1")
    }

    @Test func saveSubmitsAllThreeFields() async throws {
        let submitter = ProfileSubmitterStub()
        let client = NodeSeekProfileEditClient(submitter: submitter)

        try await client.saveIntroduction(ProfileIntroduction(bio: "b", signature: "s", readme: "r"))

        let call = try #require(submitter.calls.first)
        #expect(call.apiPath == "/api/account/introduction")
        let body = try JSONSerialization.jsonObject(with: Data(call.bodyJSON.utf8)) as? [String: String]
        #expect(body == ["bio": "b", "signature": "s", "readme": "r"])
    }
}

private final class ProfileEditClientStub: ProfileEditClienting {
    var saved: [ProfileIntroduction] = []
    var error: Error?

    func loadIntroduction(uid: Int) async throws -> ProfileIntroduction { ProfileIntroduction() }

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
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
