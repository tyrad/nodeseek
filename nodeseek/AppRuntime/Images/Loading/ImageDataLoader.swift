//
//  ImageDataLoader.swift
//  nodeseek
//
//  Created by Codex on 2026/5/9.
//

import Foundation

struct ImageDataPayload: Equatable {
    let data: Data
    let mimeType: String?
    let resolvedURL: URL
    let source: ImageDataSource
}

enum ImageDataSource: String, Equatable {
    case dataURL
    case disk
    case network
}

enum ImageDataError: Error, Equatable {
    case invalidURL
    case unavailable
}

final class ImageDataLoader {
    typealias Completion = (Result<ImageDataPayload, ImageDataError>) -> Void

    static let shared = ImageDataLoader()

    private let session: URLSession
    private let diskCache: ImageDiskCache
    private let stateQueue = DispatchQueue(label: "com.nodeseek.app.imageData.state")
    private var callbacksByURL: [URL: [Completion]] = [:]

    convenience init() {
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Images", isDirectory: true)
            .appendingPathComponent("originals", isDirectory: true)
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("Images", isDirectory: true)
                .appendingPathComponent("originals", isDirectory: true)
        self.init(
            session: URLSession(configuration: ImageRequestFactory.makeSessionConfiguration()),
            diskCache: ImageDiskCache(directory: cacheDirectory)
        )
    }

    init(session: URLSession, diskCache: ImageDiskCache) {
        self.session = session
        self.diskCache = diskCache
    }

    func loadData(for imageURL: URL, completion: @escaping Completion) {
        if let dataURLPayload = Self.decodeDataURL(imageURL) {
            completion(.success(ImageDataPayload(
                data: dataURLPayload.data,
                mimeType: dataURLPayload.mimeType,
                resolvedURL: imageURL,
                source: .dataURL
            )))
            return
        }

        guard let resolvedURL = ImageURLResolver.resolve(imageURL) else {
            completion(.failure(.invalidURL))
            return
        }

        if let diskData = diskCache.data(for: resolvedURL),
           HTMLPayloadInspector.looksLikeHTMLPayload(diskData) == false
        {
            completion(.success(ImageDataPayload(
                data: diskData,
                mimeType: nil,
                resolvedURL: resolvedURL,
                source: .disk
            )))
            return
        }

        let shouldStartRequest = stateQueue.sync { () -> Bool in
            if var callbacks = callbacksByURL[resolvedURL] {
                callbacks.append(completion)
                callbacksByURL[resolvedURL] = callbacks
                return false
            }
            callbacksByURL[resolvedURL] = [completion]
            return true
        }
        guard shouldStartRequest else { return }

        session.dataTask(with: ImageRequestFactory.makeRequest(url: resolvedURL)) { [weak self] data, response, _ in
            guard let self else { return }
            let result: Result<ImageDataPayload, ImageDataError>
            if let data, HTMLPayloadInspector.looksLikeHTMLPayload(data) == false {
                try? self.diskCache.store(data, for: resolvedURL)
                result = .success(ImageDataPayload(
                    data: data,
                    mimeType: response?.mimeType,
                    resolvedURL: resolvedURL,
                    source: .network
                ))
            } else {
                result = .failure(.unavailable)
            }

            let callbacks = self.stateQueue.sync {
                self.callbacksByURL.removeValue(forKey: resolvedURL) ?? []
            }
            callbacks.forEach { $0(result) }
        }.resume()
    }

    func cachedData(for imageURL: URL) -> Data? {
        guard let resolvedURL = ImageURLResolver.resolve(imageURL) else { return nil }
        return diskCache.data(for: resolvedURL)
    }

    func cacheByteSize() -> Int {
        diskCache.byteSize()
    }

    func clearCache() throws {
        try diskCache.clear()
    }

    private static func decodeDataURL(_ url: URL) -> (data: Data, mimeType: String?)? {
        let raw = url.absoluteString
        guard raw.lowercased().hasPrefix("data:"),
              let commaIndex = raw.firstIndex(of: ",")
        else {
            return nil
        }

        let header = String(raw[raw.startIndex ..< commaIndex]).lowercased()
        let payloadStart = raw.index(after: commaIndex)
        let payload = String(raw[payloadStart...])

        guard header.contains(";base64"),
              let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
        else {
            return nil
        }

        let mimeType = header
            .replacingOccurrences(of: "data:", with: "")
            .components(separatedBy: ";")
            .first
        return (data, mimeType)
    }
}
