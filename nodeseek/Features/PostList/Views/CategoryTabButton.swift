//
//  CategoryTabButton.swift
//  nodeseek
//

import UIKit

final class CategoryTabButton: UIButton {
    private enum Layout {
        static let horizontalInset: CGFloat = 3
    }

    var category: PostListCategory?

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
        titleLabel?.font = .systemFont(ofSize: 17, weight: .regular)
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
        titleLabel?.font = isSelected ? .systemFont(ofSize: 17, weight: .semibold) : .systemFont(ofSize: 17, weight: .regular)
        setTitleColor(isSelected ? .label : .secondaryLabel, for: .normal)
        invalidateIntrinsicContentSize()
        indicatorView.isHidden = !isSelected
    }
}
