//
//  SVGContentInspectorTests.swift
//  nodeseekTests
//

import Foundation
import Testing
@testable import nodeseek

struct SVGContentInspectorTests {
    @Test func inspectsSVGDataFromMarkup() throws {
        let data = Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="48" height="24" viewBox="0 0 48 24"><path /></svg>"#.utf8)

        let content = try #require(SVGContentInspector.inspect(data: data))

        #expect(content.text.contains("<svg"))
        #expect(content.metadata.openingTag.contains("xmlns"))
        #expect(content.metadata.width == "48")
        #expect(content.metadata.height == "24")
        #expect(content.metadata.viewBox == "0 0 48 24")
    }

    @Test func inspectsSVGDataFromXMLDeclaration() throws {
        let data = Data(#"<?xml version="1.0"?><svg viewBox="0 0 1 1"></svg>"#.utf8)

        let content = try #require(SVGContentInspector.inspect(data: data))

        #expect(content.metadata.openingTag.contains("viewBox"))
    }

    @Test func inspectsSVGDataFromMimeType() throws {
        let data = Data((String(repeating: " ", count: 600) + #"<svg width="12"></svg>"#).utf8)

        let content = try #require(SVGContentInspector.inspect(data: data, mimeType: "image/svg+xml"))

        #expect(content.mimeType == "image/svg+xml")
        #expect(content.metadata.width == "12")
    }

    @Test func rejectsHTMLData() {
        let data = Data(#"<!doctype html><html><body>Just a moment</body></html>"#.utf8)

        #expect(SVGContentInspector.inspect(data: data) == nil)
    }
}
