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

    @Test func doesNotTreatNotificationSPAAsChallengeEvenIfChallengeMarkersRemain() {
        let html = """
        <html>
        <head>
          <title>NodeSeek-通知中心</title>
          <script>window._cf_chl_opt = {}</script>
          <script src="/cdn-cgi/challenge-platform/h/g/orchestrate/chl_page/v1"></script>
        </head>
        <body>
          <a href="#/atMe">@我</a>
          <a href="#/reply">回复主题</a>
          <button>全部标为已读</button>
        </body>
        </html>
        """
        let url = URL(string: "https://www.nodeseek.com/notification#/atMe")!
        let response = HTMLResponse(
            statusCode: 200,
            headers: [:],
            finalURL: url,
            html: html
        )

        let challenge = ChallengeDetector().detect(response: response)

        #expect(ChallengeDetector.containsUsableNodeSeekHTML(html))
        #expect(challenge == nil)
    }

    @Test func stillTreatsChromeOnlyErrorPageAsBlocked() {
        let html = """
        <html>
        <body>
          <div id="nsk-head" class="nsk-container">NodeSeek</div>
          <section id="nsk-frame">出错了</section>
        </body>
        </html>
        """
        let url = URL(string: "https://www.nodeseek.com/page-1")!
        let response = HTMLResponse(
            statusCode: 403,
            headers: [:],
            finalURL: url,
            html: html
        )

        let challenge = ChallengeDetector().detect(response: response)

        #expect(ChallengeDetector.containsUsableNodeSeekHTML(html) == false)
        #expect(challenge == .blocked(url))
    }

    @Test func stillDetectsChallengeHeaderOnChromeOnlyPage() {
        let html = """
        <html>
        <body>
          <div id="nsk-head" class="nsk-container">NodeSeek</div>
          <section id="nsk-frame"></section>
        </body>
        </html>
        """
        let url = URL(string: "https://www.nodeseek.com/page-1")!
        let response = HTMLResponse(
            statusCode: 403,
            headers: ["cf-mitigated": "challenge"],
            finalURL: url,
            html: html
        )

        let challenge = ChallengeDetector().detect(response: response)

        #expect(ChallengeDetector.containsUsableNodeSeekHTML(html) == false)
        #expect(challenge == .cloudflare(url))
    }

    @Test func stillDetectsBareCloudflareChallengeWithoutNodeSeekChrome() throws {
        let html = try FixtureLoader.html(named: "cloudflare-challenge")
        let url = URL(string: "https://www.nodeseek.com/notification")!
        let response = HTMLResponse(
            statusCode: 200,
            headers: [:],
            finalURL: url,
            html: html
        )

        let challenge = ChallengeDetector().detect(response: response)

        #expect(ChallengeDetector.containsUsableNodeSeekHTML(html) == false)
        #expect(challenge == .cloudflare(url))
    }
}
