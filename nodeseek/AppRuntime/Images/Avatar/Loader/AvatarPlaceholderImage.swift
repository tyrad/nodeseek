//
//  AvatarPlaceholderImage.swift
//  nodeseek
//
//  Created by Codex on 2026/5/10.
//

import UIKit

enum AvatarPlaceholderImage {
    // 夜间改用深灰，避免黑底上出现大块亮色；通过 UIImageAsset 让 UIImageView 随深浅色自动切换。
    static let image: UIImage = {
        let asset = UIImageAsset()
        let color = UIColor(named: "AvatarPlaceholder")!
        asset.register(
            filled(color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))),
            with: UITraitCollection(userInterfaceStyle: .light)
        )
        asset.register(
            filled(color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))),
            with: UITraitCollection(userInterfaceStyle: .dark)
        )
        return asset.image(with: UITraitCollection(userInterfaceStyle: .light))
    }()

    private static func filled(_ color: UIColor) -> UIImage {
        let size = CGSize(width: 8, height: 8)
        return UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
