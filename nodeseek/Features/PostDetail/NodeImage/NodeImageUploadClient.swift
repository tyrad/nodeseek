//
//  NodeImageUploadClient.swift
//  nodeseek
//
//  Created by Codex on 2026/5/9.
//

import Foundation
import ImageIO
import UIKit

struct NodeImageUploadResult: Equatable, Sendable {
    let imageURL: URL
    let markdownText: String
}

nonisolated struct NodeImageUploadPayload: Equatable {
    let data: Data
    let fileName: String
    let mimeType: String
}

nonisolated enum NodeImageUploadImageCompressor {
    static let maxUploadByteCount = 1_000_000

    static func compressedPayload(data: Data, fileName: String, mimeType: String) -> NodeImageUploadPayload {
        guard data.count > maxUploadByteCount,
              let jpegData = compressedJPEGData(from: data) else {
            return NodeImageUploadPayload(data: data, fileName: fileName, mimeType: mimeType)
        }

        return NodeImageUploadPayload(
            data: jpegData,
            fileName: jpegFileName(from: fileName),
            mimeType: "image/jpeg"
        )
    }

    private static func compressedJPEGData(from data: Data) -> Data? {
        var bestData: Data?
        for maxDimension in [2048, 1600, 1280, 1024, 800, 640, 512, 384, 256, 128] {
            guard let workingImage = downsampledImage(from: data, maxPixelSize: maxDimension) else { continue }
            for quality in stride(from: CGFloat(0.82), through: CGFloat(0.30), by: CGFloat(-0.08)) {
                guard let data = workingImage.jpegData(compressionQuality: quality) else { continue }
                if bestData == nil || data.count < bestData!.count {
                    bestData = data
                }
                if data.count <= maxUploadByteCount {
                    return data
                }
            }
        }
        return bestData
    }

    private static func downsampledImage(from data: Data, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    private static func jpegFileName(from fileName: String) -> String {
        let url = URL(fileURLWithPath: fileName)
        let baseName = url.deletingPathExtension().lastPathComponent
        return "\(baseName.isEmpty ? "nodeseek-image" : baseName).jpg"
    }
}

protocol NodeImageUploading: Sendable {
    func uploadImage(data: Data, fileName: String, mimeType: String, apiKey: String) async throws -> NodeImageUploadResult
}

enum NodeImageUploadError: LocalizedError {
    case invalidResponse
    case uploadFailed(String)
    case missingImageURL

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "NodeImage 返回异常。"
        case .uploadFailed(let message):
            return message
        case .missingImageURL:
            return "NodeImage 未返回图片链接。"
        }
    }
}

struct NodeImageUploadClient: NodeImageUploading {
    private let endpoint: URL
    private let session: URLSession

    init(
        endpoint: URL = URL(string: "https://api.nodeimage.com/api/upload")!,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.session = session
    }

    func uploadImage(data: Data, fileName: String, mimeType: String, apiKey: String) async throws -> NodeImageUploadResult {
        let boundary = "NodeSeekBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            data: data,
            name: "image",
            fileName: fileName,
            mimeType: mimeType,
            boundary: boundary
        )

        let (responseData, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NodeImageUploadError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = NodeImageUploadResponseParser.errorMessage(from: responseData)
                ?? "NodeImage 上传失败，状态码 \(httpResponse.statusCode)。"
            throw NodeImageUploadError.uploadFailed(message)
        }

        guard let result = NodeImageUploadResponseParser.uploadResult(from: responseData) else {
            throw NodeImageUploadError.missingImageURL
        }
        return result
    }

    private static func multipartBody(
        data: Data,
        name: String,
        fileName: String,
        mimeType: String,
        boundary: String
    ) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n")
        return body
    }
}

enum NodeImageUploadResponseParser {
    static func uploadResult(from data: Data) -> NodeImageUploadResult? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let markdown = firstStringValue(in: object, matching: ["markdown", "md"]),
           let url = firstURL(in: object) {
            return NodeImageUploadResult(imageURL: url, markdownText: markdown)
        }
        guard let url = firstURL(in: object) else { return nil }
        return NodeImageUploadResult(imageURL: url, markdownText: "![](\(url.absoluteString))")
    }

    static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return firstStringValue(in: object, matching: ["message", "error", "msg"])
    }

    private static func firstURL(in object: Any) -> URL? {
        if let string = object as? String,
           let url = URL(string: string),
           ["http", "https"].contains(url.scheme?.lowercased()) {
            return url
        }

        if let array = object as? [Any] {
            for value in array {
                if let url = firstURL(in: value) {
                    return url
                }
            }
        }

        if let dictionary = object as? [String: Any] {
            let preferredKeys = ["url", "direct", "direct_url", "image_url", "src", "link"]
            for key in preferredKeys {
                if let value = dictionary[key], let url = firstURL(in: value) {
                    return url
                }
            }
            for value in dictionary.values {
                if let url = firstURL(in: value) {
                    return url
                }
            }
        }

        return nil
    }

    private static func firstStringValue(in object: Any, matching keys: Set<String>) -> String? {
        if let dictionary = object as? [String: Any] {
            for key in keys {
                if let value = dictionary[key] as? String, value.isEmpty == false {
                    return value
                }
            }
            for value in dictionary.values {
                if let nested = firstStringValue(in: value, matching: keys) {
                    return nested
                }
            }
        }

        if let array = object as? [Any] {
            for value in array {
                if let nested = firstStringValue(in: value, matching: keys) {
                    return nested
                }
            }
        }

        return nil
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
