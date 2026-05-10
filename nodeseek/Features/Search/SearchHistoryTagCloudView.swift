//
//  SearchHistoryTagCloudView.swift
//  nodeseek
//
//  Created by Codex on 2026/5/3.
//

import UIKit

final class SearchHistoryTagCloudView: UIView {
    private let horizontalSpacing: CGFloat = 8
    private let verticalSpacing: CGFloat = 8
    private var buttons: [UIButton] = []
    private var lastLayoutWidth: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setButtons(_ buttons: [UIButton]) {
        self.buttons.forEach { $0.removeFromSuperview() }
        self.buttons = buttons
        buttons.forEach(addSubview)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(bounds.width - lastLayoutWidth) > 0.5 {
            lastLayoutWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
        _ = layoutButtons(width: bounds.width, applyFrames: true)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: layoutHeight(for: bounds.width))
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        let width = targetSize.width > 0 ? targetSize.width : bounds.width
        return CGSize(width: targetSize.width, height: layoutHeight(for: width))
    }

    private func layoutHeight(for width: CGFloat) -> CGFloat {
        guard width > 0 else {
            return buttons.map { $0.sizeThatFits(UIView.layoutFittingCompressedSize).height }.max() ?? 0
        }
        return layoutButtons(width: width, applyFrames: false)
    }

    private func layoutButtons(width: CGFloat, applyFrames: Bool) -> CGFloat {
        guard !buttons.isEmpty else { return 0 }

        let availableWidth = max(width, 1)
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0

        for button in buttons {
            let fittingSize = button.sizeThatFits(
                CGSize(width: availableWidth, height: UIView.layoutFittingCompressedSize.height)
            )
            let buttonSize = CGSize(
                width: min(ceil(fittingSize.width), availableWidth),
                height: ceil(fittingSize.height)
            )

            if origin.x > 0, origin.x + buttonSize.width > availableWidth {
                origin.x = 0
                origin.y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            if applyFrames {
                button.frame = CGRect(origin: origin, size: buttonSize)
            }

            origin.x += buttonSize.width + horizontalSpacing
            rowHeight = max(rowHeight, buttonSize.height)
        }

        return origin.y + rowHeight
    }
}
