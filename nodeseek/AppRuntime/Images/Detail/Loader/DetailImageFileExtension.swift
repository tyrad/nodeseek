//
//  DetailImageFileExtension.swift
//  nodeseek
//
//  Created by Codex on 2026/5/10.
//

import Foundation

enum DetailImageFileExtension {
    static func suggested(for imageURL: URL, mimeType: String?) -> String {
        let extensionFromURL = imageURL.pathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if extensionFromURL.isEmpty == false {
            return extensionFromURL == "jpeg" ? "jpg" : extensionFromURL
        }

        switch mimeType?.lowercased().split(separator: ";", maxSplits: 1).first.map(String.init) {
        case "image/jpeg", "image/jpg":
            return "jpg"
        case "image/png":
            return "png"
        case "image/gif":
            return "gif"
        case "image/webp":
            return "webp"
        case "image/heic":
            return "heic"
        case "image/heif":
            return "heif"
        case "image/tiff":
            return "tiff"
        case "image/bmp":
            return "bmp"
        default:
            return "jpg"
        }
    }
}
