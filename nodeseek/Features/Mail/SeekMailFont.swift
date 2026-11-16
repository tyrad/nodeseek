//
//  SeekMailFont.swift
//  nodeseek
//

import UIKit

/// 邮箱文字统一跟随 App 的「字体大小」设置；基准字号对应系统默认档的文字样式。
enum SeekMailFont {
    static func of(_ style: UIFont.TextStyle, weight: UIFont.Weight = .regular,
                   pointOffset: CGFloat = AppTextSizeSettings.shared.pointOffset) -> UIFont {
        AppTypography.font(basePointSize: basePointSize(for: style), weight: weight, pointOffset: pointOffset)
    }

    static func system(_ basePointSize: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        AppTypography.font(basePointSize: basePointSize, weight: weight)
    }

    static func digits(_ basePointSize: CGFloat, weight: UIFont.Weight) -> UIFont {
        UIFont.monospacedDigitSystemFont(ofSize: AppTextSizeSettings.adjustedPointSize(basePointSize: basePointSize), weight: weight)
    }

    /// HTML 正文的字号（px），和纯文本正文一致。
    static var bodyPixelSize: Int { Int(AppTextSizeSettings.adjustedPointSize(basePointSize: 17)) }

    private static func basePointSize(for style: UIFont.TextStyle) -> CGFloat {
        switch style {
        case .title2: return 22
        case .subheadline: return 15
        case .footnote: return 13
        case .caption1: return 12
        default: return 17
        }
    }
}
