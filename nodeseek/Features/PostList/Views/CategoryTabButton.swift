//
//  CategoryTabButton.swift
//  nodeseek
//

import UIKit

final class CategoryTabButton: UIButton {
    private enum Layout {
        static let horizontalInset: CGFloat = 3
    }

    var category: PostListCategoryItem?

    private let indicatorView: UIView = {
        let view = UIView()
        view.backgroundColor = .label
        view.layer.cornerRadius = 1
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel?.font = .systemFont(
            ofSize: PostListTopBarStyle.Tab.pointSize,
            weight: PostListTopBarStyle.Tab.normalWeight
        )
        setTitleColor(.secondaryLabel, for: .normal)
        applySelectedStyle(isSelected: false)
        addSubview(indicatorView)
        NSLayoutConstraint.activate([
            indicatorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            indicatorView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            indicatorView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            indicatorView.heightAnchor.constraint(equalToConstant: 3)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let titleWidth = titleLabel?.intrinsicContentSize.width ?? 0
        return CGSize(
            width: ceil(titleWidth + Layout.horizontalInset * 2),
            height: UIView.noIntrinsicMetric
        )
    }

    func applySelectedStyle(isSelected: Bool) {
        titleLabel?.font = .systemFont(
            ofSize: PostListTopBarStyle.Tab.pointSize,
            weight: isSelected ? PostListTopBarStyle.Tab.selectedWeight : PostListTopBarStyle.Tab.normalWeight
        )
        setTitleColor(isSelected ? .label : .secondaryLabel, for: .normal)
        invalidateIntrinsicContentSize()
        indicatorView.isHidden = !isSelected
    }
}
