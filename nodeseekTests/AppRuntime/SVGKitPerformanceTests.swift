//
//  SVGKitPerformanceTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/4/27.
//

import UIKit
import XCTest
@testable import nodeseek

final class SVGKitPerformanceTests: XCTestCase {

    private let avatarRenderSize = CGSize(width: 56, height: 56)
    private lazy var svgData: Data = makeAvatarLikeSVGData()

    func testSVGKitRenderingRunsOnMainThreadWhenRequestedFromBackgroundQueue() {
        let expectation = expectation(description: "后台请求完成")
        var observedMainThread = false

        SVGImageRenderer.renderThreadObserver = { observedMainThread = $0 }
        defer { SVGImageRenderer.renderThreadObserver = nil }

        DispatchQueue.global(qos: .userInitiated).async { [svgData, avatarRenderSize] in
            let image = SVGImageRenderer.image(from: svgData, size: avatarRenderSize)
            XCTAssertNotNil(image)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 3)
        XCTAssertTrue(observedMainThread)
    }

    func testSVGKitParseAndRasterizePerformance() throws {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            autoreleasepool {
                for _ in 0..<30 {
                    guard SVGImageRenderer.image(from: svgData, size: avatarRenderSize) != nil else {
                        XCTFail("SVG 解析失败")
                        return
                    }
                }
            }
        }
    }

    private func makeAvatarLikeSVGData() -> Data {
        var circles = ""
        for index in 0..<120 {
            let radius = 10 + (index % 20)
            let cx = 20 + (index * 11) % 360
            let cy = 20 + (index * 7) % 360
            let opacity = 0.2 + Double(index % 6) * 0.1
            circles += "<circle cx=\"\(cx)\" cy=\"\(cy)\" r=\"\(radius)\" fill=\"#4F46E5\" opacity=\"\(opacity)\"/>"
        }

        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400">
          <defs>
            <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0%" stop-color="#E5E7EB"/>
              <stop offset="100%" stop-color="#9CA3AF"/>
            </linearGradient>
          </defs>
          <rect width="400" height="400" fill="url(#bg)"/>
          \(circles)
          <circle cx="200" cy="160" r="70" fill="#111827"/>
          <rect x="110" y="250" width="180" height="95" rx="48" fill="#111827"/>
        </svg>
        """
        return Data(svg.utf8)
    }
}
