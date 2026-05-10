//
//  AvatarPlaceholderImage.swift
//  nodeseek
//
//  Created by Codex on 2026/5/10.
//

import UIKit

enum AvatarPlaceholderImage {
    static let image: UIImage = {
        let size = CGSize(width: 8, height: 8)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor(white: 0.9, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }()
}
