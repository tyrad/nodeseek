//
//  DetailImageLoaderTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/5/1.
//

import Foundation
import CryptoKit
import Testing
import UIKit
@testable import nodeseek

@MainActor
@Suite(.serialized)
struct DetailImageLoaderTests {
    @Test func defaultOptimizationConfigEnablesThumbnailCache() {
        #expect(DetailImageConfig.optimizationMode == .enabled(
            maxPixelSide: 900,
            maxThumbnailBytes: 300 * 1024,
            loggingEnabled: false
        ))
    }

    @Test func optimizedInlineLoadCachesOriginalAndBoundedThumbnailForPreviewReuse() async throws {
        let url = try #require(URL(string: "https://images.example.com/photo.jpg"))
        let sourceData = try Self.makeNoisyJPEGData(width: 1200, height: 900, quality: 0.95)
        let cacheDirectory = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let protocolType = DetailImageURLProtocol.self
        protocolType.reset()
        protocolType.stub(data: sourceData, mimeType: "image/jpeg", for: url)
        let session = URLSession(configuration: Self.urlSessionConfiguration(protocolType: protocolType))
        let loader = DetailImageLoader(
            session: session,
            cacheDirectory: cacheDirectory,
            optimizationModeProvider: {
                .enabled(maxPixelSide: 360, maxThumbnailBytes: 80 * 1024, loggingEnabled: true)
            }
        )

        let inlineImage = await Self.loadInlineImage(loader: loader, url: url, maxPixelWidth: 900)
        let previewImage = await Self.loadPreviewImage(loader: loader, url: url)
        let requestCount = protocolType.totalRequestCount()
        let originalData = try #require(loader.cachedOriginalData(for: url))
        let thumbnailData = try #require(loader.cachedThumbnailData(for: url))

        #expect(inlineImage != nil)
        #expect(previewImage != nil)
        #expect(requestCount == 1)
        #expect(originalData == sourceData)
        #expect(thumbnailData.count <= 80 * 1024)
        #expect(thumbnailData.count < sourceData.count)
        #expect(max(inlineImage?.size.width ?? 0, inlineImage?.size.height ?? 0) <= 360)
    }

    @Test func disabledOptimizationKeepsExistingInlinePathWithoutDetailDiskCache() async throws {
        let url = try #require(URL(string: "https://images.example.com/plain.jpg"))
        let sourceData = try Self.makeNoisyJPEGData(width: 640, height: 480, quality: 0.9)
        let cacheDirectory = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let protocolType = DetailImageURLProtocol.self
        protocolType.reset()
        protocolType.stub(data: sourceData, mimeType: "image/jpeg", for: url)
        let session = URLSession(configuration: Self.urlSessionConfiguration(protocolType: protocolType))
        let loader = DetailImageLoader(
            session: session,
            cacheDirectory: cacheDirectory,
            optimizationModeProvider: { .disabled }
        )

        let inlineImage = await Self.loadInlineImage(loader: loader, url: url, maxPixelWidth: 320)

        #expect(inlineImage != nil)
        #expect(loader.cachedOriginalData(for: url) == nil)
        #expect(loader.cachedThumbnailData(for: url) == nil)
    }

    @Test func optimizedInlineLoadDoesNotCacheThumbnailWhenByteLimitCannotBeMet() async throws {
        let url = try #require(URL(string: "https://images.example.com/tiny-limit.jpg"))
        let sourceData = try Self.makeNoisyJPEGData(width: 900, height: 700, quality: 0.95)
        let cacheDirectory = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let protocolType = DetailImageURLProtocol.self
        protocolType.reset()
        protocolType.stub(data: sourceData, mimeType: "image/jpeg", for: url)
        let session = URLSession(configuration: Self.urlSessionConfiguration(protocolType: protocolType))
        let loader = DetailImageLoader(
            session: session,
            cacheDirectory: cacheDirectory,
            optimizationModeProvider: {
                .enabled(maxPixelSide: 360, maxThumbnailBytes: 256, loggingEnabled: false)
            }
        )

        let inlineImage = await Self.loadInlineImage(loader: loader, url: url, maxPixelWidth: 900)

        #expect(inlineImage != nil)
        #expect(loader.cachedOriginalData(for: url) == sourceData)
        #expect(loader.cachedThumbnailData(for: url) == nil)
    }

    @Test func originalImagePayloadPreservesNetworkDataAndSuggestsExtensionFromURL() async throws {
        let url = try #require(URL(string: "https://images.example.com/photo.webp?token=abc"))
        let sourceData = try Self.makeNoisyJPEGData(width: 80, height: 60, quality: 0.85)
        let cacheDirectory = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let protocolType = DetailImageURLProtocol.self
        protocolType.reset()
        protocolType.stub(data: sourceData, mimeType: "image/webp", for: url)
        let session = URLSession(configuration: Self.urlSessionConfiguration(protocolType: protocolType))
        let loader = DetailImageLoader(session: session, cacheDirectory: cacheDirectory)

        let payload = try await Self.loadOriginalImagePayload(loader: loader, url: url)

        #expect(payload.data == sourceData)
        #expect(payload.mimeType == "image/webp")
        #expect(payload.suggestedFileExtension == "webp")
        #expect(protocolType.totalRequestCount() == 1)
    }

    @Test func suggestedFileExtensionUsesMimeTypeWhenURLHasNoExtension() throws {
        let url = try #require(URL(string: "https://images.example.com/download?id=1"))

        #expect(DetailImageLoader.suggestedFileExtension(for: url, mimeType: "image/png") == "png")
        #expect(DetailImageLoader.suggestedFileExtension(for: url, mimeType: "image/jpeg; charset=binary") == "jpg")
    }

    @Test func originalImagePayloadFailsForInvalidImageDataInsteadOfReturningFallback() async throws {
        let url = try #require(URL(string: "https://images.example.com/broken.gif"))
        let cacheDirectory = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let protocolType = DetailImageURLProtocol.self
        protocolType.reset()
        protocolType.stub(data: Data("<html>not an image</html>".utf8), mimeType: "text/html", for: url)
        let session = URLSession(configuration: Self.urlSessionConfiguration(protocolType: protocolType))
        let loader = DetailImageLoader(session: session, cacheDirectory: cacheDirectory)

        await #expect(throws: DetailOriginalImageError.unavailable) {
            try await Self.loadOriginalImagePayload(loader: loader, url: url)
        }
    }

    @Test func inlineLoadRendersToolValueCardSVG() async throws {
        let url = try #require(URL(string: "https://tool.5588.la/share/vps/9e8336414982cada098a032db6639651.svg"))
        let sourceData = Self.makeToolValueCardSVGData()
        let cacheDirectory = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let protocolType = DetailImageURLProtocol.self
        protocolType.reset()
        protocolType.stub(data: sourceData, mimeType: "image/svg+xml", for: url)
        let session = URLSession(configuration: Self.urlSessionConfiguration(protocolType: protocolType))
        let loader = DetailImageLoader(
            session: session,
            cacheDirectory: cacheDirectory,
            optimizationModeProvider: {
                .enabled(maxPixelSide: 900, maxThumbnailBytes: 300 * 1024, loggingEnabled: false)
            }
        )

        let inlineImage = await Self.loadInlineImage(loader: loader, url: url, maxPixelWidth: 600)

        #expect(loader.cachedOriginalData(for: url) == sourceData)
        #expect((inlineImage?.size.width ?? 0) > 100)
        #expect((inlineImage?.size.height ?? 0) > 100)
        #expect((inlineImage?.size.height ?? 0) > (inlineImage?.size.width ?? 0) * 0.85)
    }

    @Test func inlineLoadRendersCheckPlaceReportSVGWithFontRelativeUnitsWithoutThumbnailCache() async throws {
        let url = try #require(URL(string: "https://report.check.place/ip/NPR7IUKQC.svg"))
        let sourceData = Self.makeCheckPlaceReportSVGData()
        let cacheDirectory = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let protocolType = DetailImageURLProtocol.self
        protocolType.reset()
        protocolType.stub(data: sourceData, mimeType: "image/svg+xml", for: url)
        let session = URLSession(configuration: Self.urlSessionConfiguration(protocolType: protocolType))
        let loader = DetailImageLoader(
            session: session,
            cacheDirectory: cacheDirectory,
            optimizationModeProvider: {
                .enabled(maxPixelSide: 900, maxThumbnailBytes: 300 * 1024, loggingEnabled: false)
            }
        )

        let inlineImage = await Self.loadInlineImage(loader: loader, url: url, maxPixelWidth: 600)

        #expect(loader.cachedOriginalData(for: url) == sourceData)
        #expect(loader.cachedThumbnailData(for: url) == nil)
        #expect((inlineImage?.size.width ?? 0) > 100)
        #expect((inlineImage?.size.height ?? 0) > 100)
    }

    @Test func inlineLoadRendersReportLikeSVGWithoutThumbnailCacheRegardlessPath() async throws {
        let url = try #require(URL(string: "https://report.check.place/net/31G5DHSHP.svg"))
        let sourceData = Self.makeCheckPlaceReportSVGData(width: "82ch", height: "42em")
        let cacheDirectory = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let protocolType = DetailImageURLProtocol.self
        protocolType.reset()
        protocolType.stub(data: sourceData, mimeType: "image/svg+xml", for: url)
        let session = URLSession(configuration: Self.urlSessionConfiguration(protocolType: protocolType))
        let loader = DetailImageLoader(
            session: session,
            cacheDirectory: cacheDirectory,
            optimizationModeProvider: {
                .enabled(maxPixelSide: 900, maxThumbnailBytes: 300 * 1024, loggingEnabled: false)
            }
        )

        let inlineImage = await Self.loadInlineImage(loader: loader, url: url, maxPixelWidth: 600)

        #expect(loader.cachedOriginalData(for: url) == sourceData)
        #expect(loader.cachedThumbnailData(for: url) == nil)
        #expect((inlineImage?.size.width ?? 0) > 300)
        #expect((inlineImage?.size.height ?? 0) > 300)
    }

    @Test func optimizedInlineLoadRefreshesReportSVGWhenOldThumbnailCacheExists() async throws {
        let url = try #require(URL(string: "https://report.check.place/net/31G5DHSHP.svg"))
        let sourceData = Self.makeCheckPlaceReportSVGData(width: "82ch", height: "42em")
        let staleThumbnailData = try Self.makeNoisyJPEGData(width: 80, height: 50, quality: 0.8)
        let cacheDirectory = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        try Self.writeCachedThumbnail(staleThumbnailData, for: url, in: cacheDirectory)

        let protocolType = DetailImageURLProtocol.self
        protocolType.reset()
        protocolType.stub(data: sourceData, mimeType: "image/svg+xml", for: url)
        let session = URLSession(configuration: Self.urlSessionConfiguration(protocolType: protocolType))
        let loader = DetailImageLoader(
            session: session,
            cacheDirectory: cacheDirectory,
            optimizationModeProvider: {
                .enabled(maxPixelSide: 900, maxThumbnailBytes: 300 * 1024, loggingEnabled: false)
            }
        )

        let inlineImage = await Self.loadInlineImage(loader: loader, url: url, maxPixelWidth: 600)

        #expect(protocolType.totalRequestCount() == 1)
        #expect(loader.cachedOriginalData(for: url) == sourceData)
        #expect(loader.cachedThumbnailData(for: url) == nil)
        #expect((inlineImage?.size.width ?? 0) > 300)
        #expect((inlineImage?.size.height ?? 0) > 300)
    }

    @Test func clearsDetailImageDiskAndMemoryCaches() async throws {
        let url = try #require(URL(string: "https://images.example.com/clear.jpg"))
        let sourceData = try Self.makeNoisyJPEGData(width: 900, height: 700, quality: 0.9)
        let cacheDirectory = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let protocolType = DetailImageURLProtocol.self
        protocolType.reset()
        protocolType.stub(data: sourceData, mimeType: "image/jpeg", for: url)
        let session = URLSession(configuration: Self.urlSessionConfiguration(protocolType: protocolType))
        let loader = DetailImageLoader(
            session: session,
            cacheDirectory: cacheDirectory,
            optimizationModeProvider: {
                .enabled(maxPixelSide: 360, maxThumbnailBytes: 80 * 1024, loggingEnabled: false)
            }
        )

        _ = await Self.loadInlineImage(loader: loader, url: url, maxPixelWidth: 320)
        #expect(loader.detailImageCacheByteSize() > 0)

        try loader.clearDetailImageCache()

        #expect(loader.detailImageCacheByteSize() == 0)
        #expect(loader.cachedOriginalData(for: url) == nil)
        #expect(loader.cachedThumbnailData(for: url) == nil)
    }

    private static func loadInlineImage(
        loader: DetailImageLoader,
        url: URL,
        maxPixelWidth: CGFloat
    ) async -> UIImage? {
        await withCheckedContinuation { continuation in
            loader.loadImageForInline(
                url,
                maxPixelWidth: maxPixelWidth,
                displayScale: 1
            ) { image in
                continuation.resume(returning: image)
            }
        }
    }

    private static func loadPreviewImage(loader: DetailImageLoader, url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            loader.loadImageForPreview(url) { image in
                continuation.resume(returning: image)
            }
        }
    }

    private static func loadOriginalImagePayload(
        loader: DetailImageLoader,
        url: URL
    ) async throws -> DetailOriginalImagePayload {
        try await withCheckedThrowingContinuation { continuation in
            loader.loadOriginalImagePayload(for: url) { result in
                continuation.resume(with: result)
            }
        }
    }

    private static func urlSessionConfiguration(protocolType: URLProtocol.Type) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [protocolType]
        return configuration
    }

    private static func makeTemporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DetailImageLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func writeCachedThumbnail(_ data: Data, for url: URL, in cacheDirectory: URL) throws {
        let key = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let thumbnailURL = cacheDirectory
            .appendingPathComponent("thumbnails", isDirectory: true)
            .appendingPathComponent("\(key).jpg", isDirectory: false)
        try FileManager.default.createDirectory(
            at: thumbnailURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: thumbnailURL, options: [.atomic])
    }

    private static func makeNoisyJPEGData(width: Int, height: Int, quality: CGFloat) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                bytes[index] = UInt8((x * 13 + y * 7) % 256)
                bytes[index + 1] = UInt8((x * 5 + y * 17) % 256)
                bytes[index + 2] = UInt8((x * 23 + y * 3) % 256)
                bytes[index + 3] = 255
            }
        }

        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let cgImage = try #require(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ))
        let image = UIImage(cgImage: cgImage)
        return try #require(image.jpegData(compressionQuality: quality))
    }

    private static func makeToolValueCardSVGData() -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="600" height="810" viewBox="0 0 600 810">
          <defs>
            <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0%" stop-color="#fdf2f8"/>
              <stop offset="100%" stop-color="#eef2ff"/>
            </linearGradient>
            <linearGradient id="divider" x1="0" y1="0" x2="1" y2="0">
              <stop offset="0%" stop-color="#f43f5e"/>
              <stop offset="100%" stop-color="#f97316"/>
            </linearGradient>
          </defs>
          <rect width="600" height="810" rx="28" fill="url(#bg)"/>
          <rect x="40" y="40" width="520" height="480" rx="22" fill="#ffffff" stroke="#e2e8f0"/>
          <rect x="240" y="80" width="120" height="120" rx="24" fill="#34d399"/>
          <text x="300" y="155" text-anchor="middle" font-size="48" fill="#ffffff" font-family="sans-serif">CNY </text>
          <text x="300" y="230" text-anchor="middle" font-size="22" fill="#3b0a2a" font-family="sans-serif">剩余价值</text>
          <rect x="380" y="208" width="106" height="26" rx="8" fill="#38bdf8" fill-opacity="0.24" stroke="#38bdf8" stroke-opacity="0.9"/><text x="433" y="226" text-anchor="middle" font-size="13" font-weight="700" fill="#38bdf8" font-family="sans-serif">折扣-51.6</text>
          <text x="300" y="300" text-anchor="middle" font-size="48" fill="#16a34a" font-weight="700" font-family="sans-serif">CNY 292.5</text>
          <rect x="120" y="318" width="360" height="8" rx="4" fill="url(#divider)"/>
          <text x="80" y="364" font-size="13" fill="#94a3b8" font-family="sans-serif">品名</text>
          <text x="520" y="364" text-anchor="end" font-size="15" font-weight="600" fill="#3b0a2a" font-family="sans-serif">搬瓦工CN2 GIA-E</text>
          <text x="80" y="392" font-size="13" fill="#94a3b8" font-family="sans-serif">配置</text>
          <text x="520" y="392" text-anchor="end" font-size="15" font-weight="600" fill="#3b0a2a" font-family="sans-serif">2C / 1G / 20G</text>
          <text x="80" y="420" font-size="13" fill="#94a3b8" font-family="sans-serif">流量/网络速率</text>
          <text x="520" y="420" text-anchor="end" font-size="15" font-weight="600" fill="#3b0a2a" font-family="sans-serif">1T 单 / 25G</text>
          <text x="80" y="448" font-size="13" fill="#94a3b8" font-family="sans-serif">付费周期</text>
          <text x="520" y="448" text-anchor="end" font-size="15" font-weight="600" fill="#3b0a2a" font-family="sans-serif">季度</text>
          <text x="80" y="476" font-size="13" fill="#94a3b8" font-family="sans-serif">续费金额</text>
          <text x="520" y="476" text-anchor="end" font-size="15" font-weight="600" fill="#3b0a2a" font-family="sans-serif">49.9 USD</text>
          <text x="80" y="504" font-size="13" fill="#94a3b8" font-family="sans-serif">备注</text>
          <text x="520" y="504" text-anchor="end" font-size="15" font-weight="600" fill="#3b0a2a" font-family="sans-serif">--</text>

          <rect x="40" y="540" width="520" height="220" rx="22" fill="#ffffff" stroke="#e2e8f0"/>
          <circle cx="90" cy="600" r="26" fill="#dbeafe"/>
          <text x="90" y="608" text-anchor="middle" font-size="18" fill="#2563eb" font-family="sans-serif">⏱</text>
          <text x="140" y="600" font-size="20" fill="#3b0a2a" font-family="sans-serif">剩余时间</text>
          <text x="140" y="630" font-size="14" fill="#94a3b8" font-family="sans-serif">到期于 2026-08-03</text>
          <text x="520" y="610" text-anchor="end" font-size="42" fill="#3b82f6" font-weight="700" font-family="sans-serif">92</text>
          <text x="520" y="640" text-anchor="end" font-size="14" fill="#94a3b8" font-family="sans-serif">天</text>
          <rect x="80" y="678" width="440" height="20" rx="10" fill="#e2e8f0"/>
          <rect x="80" y="678" width="{440 * 1}" height="20" rx="10" fill="#7dd3fc"/>
          <text x="80" y="730" font-size="14" fill="#94a3b8" font-family="sans-serif">2026-05-03</text>
          <text x="520" y="730" text-anchor="end" font-size="14" fill="#94a3b8" font-family="sans-serif">2026-08-03</text>
          <text x="300" y="790" text-anchor="middle" font-size="12" fill="#94a3b8" font-family="sans-serif">由 tool.5588.la 提供</text>
        </svg>
        """.utf8)
    }

    private static func makeCheckPlaceReportSVGData(width: String = "74ch", height: String = "47em") -> Data {
        Data("""
        <svg width="\(width)" height="\(height)" xmlns="http://www.w3.org/2000/svg" xml:space="preserve">
            <style>
                * {
                    font-family: SimHei, Consolas, DejaVu Sans Mono, SF Mono, monospace;
                    font-size: 14px;
                }
                tspan, text {
                    dominant-baseline: central;
                    white-space: pre;
                    fill: #bbbbbb;
                }
                .bg { stroke-width: "0.5px"; }
                .bold { font-weight: bold; }
                .fa2 { fill: #00bb00; }
                .ba2 { stroke: #00bb00; fill: #00bb00; }
            </style>
            <rect width="100%" height="100%" x="0" y="0" style="fill: #000000"/>
            <g class="bg">
                <rect x="11ch" y="38em" width="6ch" height="1em" class="ba2"/>
            </g>
            <text x="0ch" y="0.5em"><tspan>########################################################################</tspan></text>
            <text x="0ch" y="1.5em"><tspan>                      </tspan><tspan class="bold">IP质量体检报告：</tspan><tspan class="bold fa2">128.241.*.*</tspan></text>
            <text x="0ch" y="2.5em"><tspan>                   </tspan><tspan>https://github.com/xykt/IPQuality</tspan></text>
        </svg>
        """.utf8)
    }
}

private final class DetailImageURLProtocol: URLProtocol, @unchecked Sendable {
    private struct Stub: Sendable {
        let data: Data
        let mimeType: String
    }

    private static let lock = NSLock()
    private static var stubs: [String: Stub] = [:]
    private static var requestCounts: [String: Int] = [:]

    static func reset() {
        lock.lock()
        stubs.removeAll()
        requestCounts.removeAll()
        lock.unlock()
    }

    static func stub(data: Data, mimeType: String, for url: URL) {
        lock.lock()
        stubs[url.absoluteString] = Stub(data: data, mimeType: mimeType)
        lock.unlock()
    }

    static func totalRequestCount() -> Int {
        lock.lock()
        let count = requestCounts.values.reduce(0, +)
        lock.unlock()
        return count
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        Self.lock.lock()
        Self.requestCounts[url.absoluteString, default: 0] += 1
        let stub = Self.stubs[url.absoluteString]
        Self.lock.unlock()

        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }

        let response = URLResponse(
            url: url,
            mimeType: stub.mimeType,
            expectedContentLength: stub.data.count,
            textEncodingName: nil
        )
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
