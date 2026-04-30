//
//  ChallengeSessionStoreTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import Testing

#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

struct ChallengeSessionStoreTests {
    @Test func recordsChallengeStateAndReturnsUnifiedMessage() async {
        let store = NodeSeekSessionStore()
        let url = URL(string: "https://www.nodeseek.com/")!

        let message = await store.recordChallenge(.cloudflare(url))
        let state = await store.currentState()

        #expect(message == "站点当前需要 Cloudflare 验证，请稍后重试。")
        switch state {
        case .challengeRequired(.cloudflare(let challengeURL), _):
            #expect(challengeURL == url)
        default:
            Issue.record("命中 challenge 后应进入统一的 challenge 状态")
        }
    }

    @Test func recordsSuccessStateAfterRequestSucceeds() async {
        let store = NodeSeekSessionStore()
        let url = URL(string: "https://www.nodeseek.com/")!

        _ = await store.recordChallenge(.cloudflare(url))
        await store.recordSuccess()
        let state = await store.currentState()

        guard case .ready = state else {
            Issue.record("请求成功后应进入 ready 状态")
            return
        }
    }
}
