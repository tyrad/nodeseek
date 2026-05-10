//
//  AvatarImageLoadFailure.swift
//  nodeseek
//
//  Created by Codex on 2026/5/10.
//

import Foundation
import Kingfisher

enum AvatarImageLoadFailure {
    static func isHTMLPayload(_ error: KingfisherError) -> Bool {
        guard let data = processorInputData(from: error) else { return false }
        return HTMLPayloadInspector.looksLikeHTMLPayload(data)
    }

    static func details(for error: KingfisherError) -> String {
        var message = error.localizedDescription
        guard let data = processorInputData(from: error) else { return message }

        let snippet = String(data: data.prefix(120), encoding: .utf8)?
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            ?? ""
        let isHTML = HTMLPayloadInspector.looksLikeHTMLPayload(data)

        message += ", dataBytes=\(data.count), looksHTML=\(isHTML)"
        if !snippet.isEmpty {
            message += ", snippet=\(snippet)"
        }
        return message
    }

    private static func processorInputData(from error: KingfisherError) -> Data? {
        guard case let .processorError(reason) = error else { return nil }
        guard case let .processingFailed(processor: _, item: item) = reason else { return nil }
        guard case let .data(data) = item else { return nil }
        return data
    }
}
