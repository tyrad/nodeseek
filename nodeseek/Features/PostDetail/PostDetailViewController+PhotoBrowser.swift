//
//  PostDetailViewController+PhotoBrowser.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import UIKit

extension PostDetailViewController {
    func presentPhotoBrowser(imageURLs: [URL], initialIndex: Int) {
        guard imageURLs.isEmpty == false else { return }
        AppLog.info(.postDetail, "打开详情大图: count=\(imageURLs.count), initialIndex=\(initialIndex)")
        let presenter = DetailPhotoBrowserPresenter(imageURLs: imageURLs)
        photoBrowserPresenter = presenter
        presenter.present(from: self, initialIndex: initialIndex)
    }
}
