//
//  HTMLPayloadInspectorTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/5/10.
//

import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

struct HTMLPayloadInspectorTests {
    @Test func detectsHTMLDocumentFromDataPrefix() {
        let data = Data("<!doctype html><html><body>blocked</body></html>".utf8)

        #expect(HTMLPayloadInspector.looksLikeHTMLDocument(data))
    }

    @Test func detectsCloudflareChallengeFromDataPrefix() {
        let data = Data("""
        <html>
          <head>
            <script>window._cf_chl_opt = {}</script>
            <script src="/cdn-cgi/challenge-platform/h/g/orchestrate/chl_page/v1"></script>
          </head>
          <body>Enable JavaScript and cookies to continue</body>
        </html>
        """.utf8)

        #expect(HTMLPayloadInspector.containsCloudflareChallenge(data))
    }

    @Test func doesNotTreatImageBytesAsHTMLDocument() {
        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let svg = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>".utf8)

        #expect(HTMLPayloadInspector.looksLikeHTMLDocument(pngHeader) == false)
        #expect(HTMLPayloadInspector.looksLikeHTMLDocument(svg) == false)
    }
}
