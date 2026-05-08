//
//  HTMLLoadingStrategyClientTests.swift
//  nodeseekTests
//

import Foundation
import Testing
@testable import nodeseek

@MainActor
struct HTMLLoadingStrategyClientTests {
    @Test func factoryUsesConfiguredLegacyWebViewStrategy() {
        HTMLLoadingStrategyConfig.listAndDetailStrategy = .legacyWebView
        defer {
            HTMLLoadingStrategyConfig.listAndDetailStrategy = .httpWithWebViewFallback
        }

        let client = HTMLLoadingStrategyFactory.makeDefaultClient()

        #expect(client is HiddenWebViewHTMLClient)
    }

    @Test func httpWithFallbackReturnsPrimaryResponseWhenHTTPIsUsable() async throws {
        let url = URL(string: "https://www.nodeseek.com/page-1")!
        let events = StrategyEventRecorder()
        let primary = QueueHTMLClient(
            responses: [
                HTMLResponse(
                    statusCode: 200,
                    headers: [:],
                    finalURL: url,
                    html: try FixtureLoader.html(named: "post-list-basic")
                )
            ],
            label: "primary",
            events: events
        )
        let fallback = QueueHTMLClient(
            responses: [
                HTMLResponse(statusCode: 200, headers: [:], finalURL: url, html: "")
            ],
            label: "fallback",
            events: events
        )
        let client = WebViewFallbackHTMLClient(
            primaryClient: primary,
            fallbackClient: fallback,
            cookieSynchronizer: StrategySpyCookieSynchronizer(events: events)
        )

        let response = try await client.get(url)

        #expect(response.statusCode == 200)
        #expect(response.html.contains("测试帖子"))
        #expect(await events.recordedEvents() == ["sync", "primary.get"])
    }

    @Test func httpWithFallbackUsesWebViewAndRetriesHTTPOnceWhenHTTPHitsCloudflare() async throws {
        let url = URL(string: "https://www.nodeseek.com/page-1")!
        let events = StrategyEventRecorder()
        let primary = QueueHTMLClient(
            responses: [
                HTMLResponse(
                    statusCode: 403,
                    headers: ["cf-mitigated": "challenge"],
                    finalURL: url,
                    html: try FixtureLoader.html(named: "cloudflare-challenge")
                ),
                HTMLResponse(
                    statusCode: 200,
                    headers: [:],
                    finalURL: url,
                    html: try FixtureLoader.html(named: "post-list-basic")
                )
            ],
            label: "primary",
            events: events
        )
        let fallback = QueueHTMLClient(
            responses: [
                HTMLResponse(
                    statusCode: 200,
                    headers: [:],
                    finalURL: url,
                    html: try FixtureLoader.html(named: "post-list-basic")
                )
            ],
            label: "fallback",
            events: events
        )
        let client = WebViewFallbackHTMLClient(
            primaryClient: primary,
            fallbackClient: fallback,
            cookieSynchronizer: StrategySpyCookieSynchronizer(events: events)
        )

        let response = try await client.get(url)

        #expect(response.statusCode == 200)
        #expect(await events.recordedEvents() == [
            "sync",
            "primary.get",
            "fallback.get",
            "sync",
            "primary.get"
        ])
    }

    @Test func httpWithFallbackDoesNotUseWebViewForLoginRequired() async throws {
        let url = URL(string: "https://www.nodeseek.com/post-704286-1")!
        let events = StrategyEventRecorder()
        let primary = QueueHTMLClient(
            responses: [
                HTMLResponse(
                    statusCode: 404,
                    headers: [:],
                    finalURL: url,
                    html: try FixtureLoader.html(named: "post-login-required")
                )
            ],
            label: "primary",
            events: events
        )
        let fallback = QueueHTMLClient(
            responses: [
                HTMLResponse(statusCode: 200, headers: [:], finalURL: url, html: "")
            ],
            label: "fallback",
            events: events
        )
        let client = WebViewFallbackHTMLClient(
            primaryClient: primary,
            fallbackClient: fallback,
            cookieSynchronizer: StrategySpyCookieSynchronizer(events: events)
        )

        let response = try await client.get(url)

        #expect(ChallengeDetector().detect(response: response) == .loginRequired(url))
        #expect(await events.recordedEvents() == ["sync", "primary.get"])
    }

    @Test func httpWithFallbackReturnsOriginalChallengeWhenWebViewFallbackThrows() async throws {
        let url = URL(string: "https://www.nodeseek.com/page-1")!
        let events = StrategyEventRecorder()
        let originalChallenge = HTMLResponse(
            statusCode: 403,
            headers: ["cf-mitigated": "challenge"],
            finalURL: url,
            html: try FixtureLoader.html(named: "cloudflare-challenge")
        )
        let primary = QueueHTMLClient(
            responses: [originalChallenge],
            label: "primary",
            events: events
        )
        let fallback = ThrowingHTMLClient(label: "fallback", events: events)
        let client = WebViewFallbackHTMLClient(
            primaryClient: primary,
            fallbackClient: fallback,
            cookieSynchronizer: StrategySpyCookieSynchronizer(events: events)
        )

        let response = try await client.get(url)

        #expect(response.statusCode == 403)
        #expect(ChallengeDetector().detect(response: response) == .cloudflare(url))
        #expect(await events.recordedEvents() == ["sync", "primary.get", "fallback.get"])
    }

    @Test func httpWithFallbackReturnsWebViewResponseWhenRetryThrowsAfterUsableFallback() async throws {
        let url = URL(string: "https://www.nodeseek.com/page-1")!
        let events = StrategyEventRecorder()
        let primary = ChallengeThenThrowingHTMLClient(url: url, events: events)
        let fallback = QueueHTMLClient(
            responses: [
                HTMLResponse(
                    statusCode: 200,
                    headers: [:],
                    finalURL: url,
                    html: try FixtureLoader.html(named: "page-1")
                )
            ],
            label: "fallback",
            events: events
        )
        let client = WebViewFallbackHTMLClient(
            primaryClient: primary,
            fallbackClient: fallback,
            cookieSynchronizer: StrategySpyCookieSynchronizer(events: events)
        )

        let response = try await client.get(url)

        #expect(response.statusCode == 200)
        #expect(ChallengeDetector().detect(response: response) == nil)
        #expect(await events.recordedEvents() == [
            "sync",
            "primary.get",
            "fallback.get",
            "sync",
            "primary.get"
        ])
    }
}

private actor StrategyEventRecorder {
    private var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }

    func recordedEvents() -> [String] {
        events
    }
}

@MainActor
private final class StrategySpyCookieSynchronizer: CookieSynchronizing {
    private let events: StrategyEventRecorder

    init(events: StrategyEventRecorder) {
        self.events = events
    }

    func syncWebViewCookiesToURLSession() async {
        await events.record("sync")
    }
}

private actor QueueHTMLClient: HTMLClient {
    private var responses: [HTMLResponse]
    private let label: String
    private let events: StrategyEventRecorder

    init(responses: [HTMLResponse], label: String, events: StrategyEventRecorder) {
        self.responses = responses
        self.label = label
        self.events = events
    }

    func get(_ url: URL) async throws -> HTMLResponse {
        await events.record("\(label).get")
        return responses.isEmpty
            ? HTMLResponse(statusCode: 500, headers: [:], finalURL: url, html: "")
            : responses.removeFirst()
    }

    func post(_ url: URL, formFields: [String: String]) async throws -> HTMLResponse {
        await events.record("\(label).post")
        return responses.isEmpty
            ? HTMLResponse(statusCode: 500, headers: [:], finalURL: url, html: "")
            : responses.removeFirst()
    }
}

private enum StrategyTestError: Error {
    case failed
}

private actor ThrowingHTMLClient: HTMLClient {
    private let label: String
    private let events: StrategyEventRecorder

    init(label: String, events: StrategyEventRecorder) {
        self.label = label
        self.events = events
    }

    func get(_ url: URL) async throws -> HTMLResponse {
        await events.record("\(label).get")
        throw StrategyTestError.failed
    }

    func post(_ url: URL, formFields: [String: String]) async throws -> HTMLResponse {
        await events.record("\(label).post")
        throw StrategyTestError.failed
    }
}

private actor ChallengeThenThrowingHTMLClient: HTMLClient {
    private let url: URL
    private let events: StrategyEventRecorder
    private var callCount = 0

    init(url: URL, events: StrategyEventRecorder) {
        self.url = url
        self.events = events
    }

    func get(_ url: URL) async throws -> HTMLResponse {
        await events.record("primary.get")
        callCount += 1
        if callCount == 1 {
            return HTMLResponse(
                statusCode: 403,
                headers: ["cf-mitigated": "challenge"],
                finalURL: self.url,
                html: try FixtureLoader.html(named: "cloudflare-challenge")
            )
        }
        throw StrategyTestError.failed
    }

    func post(_ url: URL, formFields: [String: String]) async throws -> HTMLResponse {
        await events.record("primary.post")
        throw StrategyTestError.failed
    }
}
