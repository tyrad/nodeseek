import Foundation
import Testing
@testable import nodeseek

@Suite @MainActor
struct SiriDraftTests {
    @available(iOS 16, *)
    @Test func firstDictationNeedsNoConfirmation() async throws {
        let store = try makeStore()
        let saved = await DictatePostDraftIntent.save("第一行\n第二行", in: store) {
            Issue.record("首次保存不应询问替换")
            return false
        }
        #expect(saved)
        #expect(store.load()?.content == "第一行\n第二行")
    }

    @available(iOS 16, *)
    @Test(arguments: [false, true])
    func replacementRequiresApproval(approved: Bool) async throws {
        let store = try makeStore()
        store.save(.init(content: "旧正文"))
        let saved = await DictatePostDraftIntent.save("新正文", in: store) { approved }
        #expect(saved == approved)
        #expect(store.load()?.content == (approved ? "新正文" : "旧正文"))
    }

    @available(iOS 16, *)
    @Test func concurrentEditSurvivesConfirmation() async throws {
        let store = try makeStore()
        store.save(.init(content: "旧正文"))
        let saved = await DictatePostDraftIntent.save("口述", in: store) {
            store.save(.init(content: "刚编辑的正文"))
            return true
        }
        #expect(!saved)
        #expect(store.load()?.content == "刚编辑的正文")
    }

    private func makeStore() throws -> UserDefaultsNewDiscussionDraftStore {
        let defaults = try #require(UserDefaults(suiteName: "siri-draft-" + UUID().uuidString))
        return UserDefaultsNewDiscussionDraftStore(userDefaults: defaults)
    }
}
