//
//  NewDiscussionDraftTests.swift
//  nodeseekTests
//

import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

struct NewDiscussionDraftTests {
    @Test func categoryRawValuesMatchWebForm() {
        #expect(DiscussionCategory.allCases.map(\.rawValue) == [
            "daily", "tech", "info", "review", "trade", "carpool", "promotion",
            "life", "dev", "photo-share", "expose", "inside", "sandbox"
        ])
        #expect(DiscussionCategory.regularCases.contains(.inside) == false)
        #expect(DiscussionCategory.regularCases.count == 12)
        #expect(DiscussionCategory.inside.chickenLegFee == 5)
        #expect(DiscussionCategory.tech.chickenLegFee == nil)
    }

    @Test func readRankOptionsFollowUserLevel() {
        #expect(DiscussionReadRank.options(userLevel: 4).map(\.rawValue) == [0, 1, 2, 3, 4, 255])
        #expect(DiscussionReadRank.options(userLevel: 4).map(\.title) == ["公开", "Lv1", "Lv2", "Lv3", "Lv4", "私有"])
        #expect(DiscussionReadRank.options(userLevel: 0).map(\.rawValue) == [0, 255])
        #expect(DiscussionReadRank.options(userLevel: -1).map(\.rawValue) == [0, 255])
    }

    @Test func draftWithOnlySettingsHasNoContent() {
        let draft = NewDiscussionDraft(title: "  ", content: "\n", category: .tech, rank: .level(2))
        #expect(draft.hasContent == false)
        #expect(NewDiscussionDraft(content: "hi").hasContent)
    }

    @Test func validationReportsFirstMissingFieldWithWebWording() {
        #expect(throws: NewDiscussionValidationError.titleEmpty) {
            try NewDiscussionDraft(title: " ", content: "正文", category: .tech).validatedSubmission()
        }
        #expect(throws: NewDiscussionValidationError.categoryMissing) {
            try NewDiscussionDraft(title: "标题", content: "正文").validatedSubmission()
        }
        #expect(throws: NewDiscussionValidationError.contentEmpty) {
            try NewDiscussionDraft(title: "标题", content: "  \n", category: .tech).validatedSubmission()
        }
        #expect(NewDiscussionValidationError.titleEmpty.errorDescription == "标题不能为空")
        #expect(NewDiscussionValidationError.categoryMissing.errorDescription == "请选择正确的板块")
    }

    @Test func submissionTrimsTitleButKeepsContentAsWritten() throws {
        let submission = try NewDiscussionDraft(
            title: "  求推荐小鸡 \n",
            content: "  缩进的代码\n\n",
            category: .photoShare,
            rank: .onlyMe
        ).validatedSubmission()

        #expect(submission.title == "求推荐小鸡")
        #expect(submission.content == "  缩进的代码\n\n")

        let json = try #require(
            JSONSerialization.jsonObject(with: submission.jsonData()) as? [String: Any]
        )
        #expect(json["mode"] as? String == "new-discussion")
        #expect(json["title"] as? String == "求推荐小鸡")
        #expect(json["category"] as? String == "photo-share")
        #expect(json["rank"] as? Int == 255)
        #expect(json["content"] as? String == "  缩进的代码\n\n")
    }

    @Test func draftRoundTripsThroughJSON() throws {
        let draft = NewDiscussionDraft(
            title: "标题",
            content: "## 正文",
            category: .inside,
            rank: .level(3),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let decoded = try JSONDecoder().decode(NewDiscussionDraft.self, from: JSONEncoder().encode(draft))
        #expect(decoded == draft)
    }

    @Test func successfulResponseResolvesNewPostRoute() throws {
        let data = Data(##"{"success":true,"redirect":"/post-512345-1","redirectHash":"#0"}"##.utf8)
        let response = try NewDiscussionResponseParser.parse(data)

        #expect(response.success)
        let route = try #require(response.postRoute())
        #expect(route.postID == "512345")
        #expect(route.page == 1)
    }

    @Test func failedResponseKeepsServerMessage() throws {
        let data = Data(#"{"success":false,"message":"发帖过于频繁，请稍后再试"}"#.utf8)
        let response = try NewDiscussionResponseParser.parse(data)

        #expect(response.success == false)
        #expect(response.message == "发帖过于频繁，请稍后再试")
        #expect(response.postRoute() == nil)
    }

    @Test func nonJSONResponseIsRejected() {
        #expect(throws: NewDiscussionResponseParser.ParseError.invalidJSON) {
            try NewDiscussionResponseParser.parse(Data("<html>Just a moment</html>".utf8))
        }
    }
}
