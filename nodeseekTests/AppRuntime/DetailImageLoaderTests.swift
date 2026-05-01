//
//  DetailImageLoaderTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/5/1.
//

import Foundation
import Testing
import UIKit
@testable import nodeseek

@MainActor
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

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": stub.mimeType]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
