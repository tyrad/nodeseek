//
//  EditableDiscussionTests.swift
//  nodeseekTests
//

import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

struct EditableDiscussionTests {
    private let original = EditableDiscussion(
        postID: 1016685,
        title: "测试",
        content: "好的吧",
        category: .review,
        rank: .everyone,
        userLevel: 4
    )

    @Test func onlyTitleContentAndRankCountAsChanges() {
        var draft = original.draft
        #expect(original.isModified(by: draft) == false)

        draft.updatedAt = Date(timeIntervalSince1970: 0)
        draft.category = .daily
        #expect(original.isModified(by: draft) == false)

        draft.rank = .level(2)
        #expect(original.isModified(by: draft))
    }

    @Test func privateFeeOnlyWhenBecomingPrivate() {
        #expect(original.requiresPrivateFee(for: .onlyMe))
        #expect(original.requiresPrivateFee(for: .level(3)) == false)

        let alreadyPrivate = EditableDiscussion(postID: 1, title: "t", content: "c", category: .review, rank: .onlyMe, userLevel: 4)
        #expect(alreadyPrivate.requiresPrivateFee(for: .onlyMe) == false)
    }

    @Test func editSubmissionMatchesWebPayload() throws {
        var draft = original.draft
        draft.title = "  新标题 "
        draft.rank = .onlyMe
        let submission = try draft.validatedEditSubmission(postID: original.postID)
        let json = try JSONSerialization.jsonObject(with: submission.jsonData()) as? [String: Any]

        #expect(json?["mode"] as? String == "edit-discussion")
        #expect(json?["postId"] as? Int == 1016685)
        #expect(json?["title"] as? String == "新标题")
        #expect(json?["content"] as? String == "好的吧")
        #expect(json?["rank"] as? Int == 255)
        #expect(json?["category"] == nil)
    }

    @Test func editValidationNeedsTitleAndContentButNotCategory() {
        var draft = NewDiscussionDraft(title: " ", content: "正文")
        #expect(throws: NewDiscussionValidationError.titleEmpty) { try draft.validatedEditSubmission(postID: 1) }
        draft.title = "标题"
        draft.content = "\n"
        #expect(throws: NewDiscussionValidationError.contentEmpty) { try draft.validatedEditSubmission(postID: 1) }
        draft.content = "正文"
        #expect((try? draft.validatedEditSubmission(postID: 1)) != nil)
    }

    @Test func editCommentPayloadMatchesWebAndPageFollowsFloor() throws {
        let submission = try EditCommentSubmission(commentID: 13684926, content: "你好")
        let json = try JSONSerialization.jsonObject(with: submission.jsonData()) as? [String: Any]
        #expect(json?["mode"] as? String == "edit-comment")
        #expect(json?["commentId"] as? Int == 13684926)
        #expect(json?["content"] as? String == "你好")
        #expect(throws: NewDiscussionValidationError.contentEmpty) { try EditCommentSubmission(commentID: 1, content: " \n") }

        #expect([0, 1, 10, 11, 20, 21].map(EditableComment.page(forFloor:)) == [1, 1, 1, 2, 2, 3])
    }
}
