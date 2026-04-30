//
//  ChallengeDetectorTests.swift
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

@MainActor
struct ChallengeDetectorTests {
    @Test func detectsCloudflareChallengeFromRealResponseShape() throws {
        let html = try FixtureLoader.html(named: "cloudflare-challenge")
        let url = URL(string: "https://www.nodeseek.com/")!
        let response = HTMLResponse(
            statusCode: 403,
            headers: [:],
            finalURL: url,
            html: html
        )

        let challenge = ChallengeDetector().detect(response: response)

        #expect(challenge == .cloudflare(url))
    }

    @Test func doesNotTreatNormalCloudflareServerHeaderAsChallenge() throws {
        let html = try FixtureLoader.html(named: "post-list-basic")
        let url = URL(string: "https://www.nodeseek.com/")!
        let response = HTMLResponse(
            statusCode: 200,
            headers: ["Server": "cloudflare"],
            finalURL: url,
            html: html
        )

        let challenge = ChallengeDetector().detect(response: response)

        #expect(challenge == nil)
    }

    @Test func doesNotTreatUsableNodeSeekHTMLAsChallengeEvenIfChallengeMarkersRemain() {
        let html = """
        <html>
        <head>
          <script>window._cf_chl_opt = {}</script>
          <script src="/cdn-cgi/challenge-platform/h/g/orchestrate/chl_page/v1"></script>
        </head>
        <body>
          <div id="nsk-body" class="nsk-container">
            <ul class="post-list">
              <li class="post-list-item">ok</li>
            </ul>
          </div>
        </body>
        </html>
        """
        let url = URL(string: "https://www.nodeseek.com/page-1")!
        let response = HTMLResponse(
            statusCode: 200,
            headers: [:],
            finalURL: url,
            html: html
        )

        let challenge = ChallengeDetector().detect(response: response)

        #expect(challenge == nil)
    }
}
