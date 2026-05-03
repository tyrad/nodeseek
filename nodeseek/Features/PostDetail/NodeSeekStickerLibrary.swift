//
//  NodeSeekStickerLibrary.swift
//  nodeseek
//
//  Created by Codex on 2026/5/3.
//

import Foundation

struct NodeSeekStickerItem: Hashable {
    let token: String
    let imageURLs: [URL]
}

struct NodeSeekStickerPack: Hashable {
    let title: String
    let items: [NodeSeekStickerItem]
}

enum NodeSeekStickerLibrary {
    nonisolated static let defaultPacks: [NodeSeekStickerPack] = [
        makePack(title: "AC娘", directory: "ac", group: "ac", files: acFiles),
        makePack(title: "洋葱头", directory: "yct", group: "yct", files: yctFiles),
        makePack(title: "小黄鸡", directory: "xhj", group: "xhj", files: xhjFiles),
        makePack(title: "Fluent", directory: "emoji", group: "emoji", files: emojiFiles.map { "\($0).png" })
    ]

    private nonisolated static func makePack(
        title: String,
        directory: String,
        group: String,
        files: [String]
    ) -> NodeSeekStickerPack {
        let items = files.map { file in
            let name = file.replacingOccurrences(of: #"\.[^.]+$"#, with: "", options: .regularExpression)
            let token = "\(group)\(name)"
            let url = NodeSeekSite.baseURL
                .appendingPathComponent("static")
                .appendingPathComponent("image")
                .appendingPathComponent("sticker")
                .appendingPathComponent(directory)
                .appendingPathComponent(file)
            let urls = [url]
            return NodeSeekStickerItem(token: token, imageURLs: urls)
        }
        return NodeSeekStickerPack(title: title, items: items)
    }

    private nonisolated static let acFiles: [String] = {
        let normal = (1...54).map { String(format: "%02d.png", $0) }
        let firstExtended = (1001...1040).map { "\($0).png" }
        let secondExtended = (2001...2055).map { "\($0).png" }
        return normal + firstExtended + secondExtended
    }()

    private nonisolated static let yctFiles: [String] = (1...22).map { String(format: "%03d.gif", $0) }

    private nonisolated static let xhjFiles: [String] = [
        "001.png", "002.png", "003.png", "004.gif", "005.png", "006.png", "007.png", "008.gif",
        "009.gif", "010.gif", "011.png", "012.gif", "013.gif", "014.gif", "015.gif", "016.gif",
        "017.gif", "018.gif", "019.gif", "020.gif", "021.gif", "022.png", "023.gif", "024.png",
        "025.png", "026.gif", "027.gif", "028.gif", "029.gif", "030.gif", "031.png", "032.png"
    ]

    private nonisolated static let emojiFiles: [String] = (0...48).map { String(format: "%02d", $0) }
}
