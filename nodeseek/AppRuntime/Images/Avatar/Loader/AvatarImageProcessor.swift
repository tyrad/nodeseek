//
//  AvatarImageProcessor.swift
//  nodeseek
//
//  Created by Codex on 2026/5/9.
//

import Kingfisher
import UIKit

struct AvatarImageProcessor: ImageProcessor {
    let size: CGSize
    let identifier: String

    init(size: CGSize) {
        self.size = size
        self.identifier = "com.nodeseek.avatar(\(Int(size.width))x\(Int(size.height)))"
    }

    func process(item: ImageProcessItem, options: KingfisherParsedOptionsInfo) -> KFCrossPlatformImage? {
        switch item {
        case .data(let data) where SVGContentInspector.looksLikeSVG(data):
            return SVGImageRenderer.image(from: data, size: size)
        default:
            return DownsamplingImageProcessor(size: size).process(item: item, options: options)
        }
    }
}
