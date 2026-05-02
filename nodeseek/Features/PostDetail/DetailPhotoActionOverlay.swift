//
//  DetailPhotoActionOverlay.swift
//  nodeseek
//
//  Created by Codex on 2026/5/2.
//

import JXPhotoBrowser
import UIKit

final class DetailPhotoActionOverlay: UIView, JXPhotoBrowserOverlay {
    var onTap: ((JXPhotoBrowserViewController, UIView) -> Void)?

    private weak var browser: JXPhotoBrowserViewController?

    private lazy var button: UIButton = {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "ellipsis")
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.48)
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        button.configuration = configuration
        button.accessibilityLabel = "图片操作"
        button.accessibilityIdentifier = "detail-photo-action-button"
        button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    func setup(with browser: JXPhotoBrowserViewController) {
        self.browser = browser
        guard let container = superview else { return }
        NSLayoutConstraint.activate([
            trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor, constant: -22)
        ])
    }

    func reloadData(numberOfItems: Int, pageIndex: Int) {
        isHidden = numberOfItems == 0
    }

    func didChangedPageIndex(_ index: Int) {}

    private func setupUI() {
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.widthAnchor.constraint(equalToConstant: 48),
            button.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    @objc private func buttonTapped() {
        guard let browser else { return }
        onTap?(browser, button)
    }
}
