//
//  NodeSeekStickerPickerView.swift
//  nodeseek
//
//  Created by Codex on 2026/5/3.
//

import Kingfisher
import UIKit

/// 回复输入区使用的贴纸选择视图。
final class NodeSeekStickerPickerView: UIView {
    var onSelectSticker: ((NodeSeekStickerItem) -> Void)?

    private var packs: [NodeSeekStickerPack] = []
    private var selectedPackIndex = 0

    private lazy var segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl()
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(packChanged), for: .valueChanged)
        control.accessibilityIdentifier = "post-detail-sticker-pack-control"
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: Layout.cellSide, height: Layout.cellSide)
        layout.minimumInteritemSpacing = Layout.cellSpacing
        layout.minimumLineSpacing = Layout.cellSpacing
        layout.sectionInset = UIEdgeInsets(top: 10, left: 12, bottom: 12, right: 12)

        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.dataSource = self
        view.delegate = self
        view.alwaysBounceVertical = true
        view.register(StickerCell.self, forCellWithReuseIdentifier: StickerCell.reuseIdentifier)
        view.accessibilityIdentifier = "post-detail-sticker-grid"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        configure(packs: NodeSeekStickerLibrary.defaultPacks)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(packs: [NodeSeekStickerPack]) {
        self.packs = packs
        selectedPackIndex = min(selectedPackIndex, max(0, packs.count - 1))

        segmentedControl.removeAllSegments()
        for (index, pack) in packs.enumerated() {
            segmentedControl.insertSegment(withTitle: pack.title, at: index, animated: false)
        }
        segmentedControl.selectedSegmentIndex = packs.isEmpty ? UISegmentedControl.noSegment : selectedPackIndex
        collectionView.reloadData()
    }

    private func setupUI() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        clipsToBounds = true
        isHidden = true
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(segmentedControl)
        addSubview(collectionView)

        NSLayoutConstraint.activate([
            segmentedControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            segmentedControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            segmentedControl.topAnchor.constraint(equalTo: topAnchor, constant: 10),

            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 4),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @objc
    private func packChanged() {
        selectedPackIndex = segmentedControl.selectedSegmentIndex
        collectionView.setContentOffset(.zero, animated: false)
        collectionView.reloadData()
    }

    private var selectedPack: NodeSeekStickerPack? {
        guard packs.indices.contains(selectedPackIndex) else { return nil }
        return packs[selectedPackIndex]
    }

    private enum Layout {
        static let cellSide: CGFloat = 72
        static let cellSpacing: CGFloat = 12
    }
}

extension NodeSeekStickerPickerView: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        selectedPack?.items.count ?? 0
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: StickerCell.reuseIdentifier,
            for: indexPath
        )
        guard let stickerCell = cell as? StickerCell,
              let item = selectedPack?.items[indexPath.item] else {
            return cell
        }
        stickerCell.configure(with: item)
        return stickerCell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = selectedPack?.items[indexPath.item] else { return }
        onSelectSticker?(item)
    }
}

private final class StickerCell: UICollectionViewCell {
    static let reuseIdentifier = "NodeSeekStickerPickerView.StickerCell"

    private static let downloader: ImageDownloader = {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 20

        let downloader = ImageDownloader(name: "NodeSeekStickerDownloader")
        downloader.sessionConfiguration = configuration
        return downloader
    }()

    private let imageView = AnimatedImageView()
    private let fallbackLabel = UILabel()
    private var representedToken: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedToken = nil
        imageView.kf.cancelDownloadTask()
        imageView.image = nil
        fallbackLabel.text = nil
        fallbackLabel.isHidden = true
    }

    func configure(with item: NodeSeekStickerItem) {
        representedToken = item.token
        accessibilityLabel = item.token
        fallbackLabel.text = item.token
        loadImageCandidates(item.imageURLs, token: item.token)
    }

    private func setupUI() {
        contentView.backgroundColor = .tertiarySystemBackground
        contentView.layer.cornerRadius = 8
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true

        imageView.autoPlayAnimatedImage = true
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        fallbackLabel.font = .preferredFont(forTextStyle: .caption2)
        fallbackLabel.textAlignment = .center
        fallbackLabel.textColor = .tertiaryLabel
        fallbackLabel.adjustsFontSizeToFitWidth = true
        fallbackLabel.minimumScaleFactor = 0.55
        fallbackLabel.isHidden = true
        fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(fallbackLabel)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),

            fallbackLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 3),
            fallbackLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -3),
            fallbackLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    private func loadImageCandidates(_ urls: [URL], token: String) {
        let imageURLs = urls.filter { Self.supportedImageExtensions.contains($0.pathExtension.lowercased()) }
        loadImageCandidateURLs(imageURLs, token: token)
    }

    private func loadImageCandidateURLs(_ urls: [URL], token: String) {
        guard let url = urls.first else {
            showFallback(for: token)
            return
        }

        imageView.kf.setImage(
            with: url,
            options: [
                .requestModifier(AnyModifier { request in
                    var modifiedRequest = request
                    WebRequestFingerprint.applyImageHeaders(to: &modifiedRequest)
                    return modifiedRequest
                }),
                .downloader(Self.downloader),
                .cacheOriginalImage
            ]
        ) { [weak self] result in
            guard let self, self.representedToken == token else { return }
            switch result {
            case .success:
                self.fallbackLabel.isHidden = true
            case .failure:
                self.loadImageCandidateURLs(Array(urls.dropFirst()), token: token)
            }
        }
    }

    private func showFallback(for token: String) {
        guard representedToken == token else { return }
        fallbackLabel.isHidden = false
    }

    private static let supportedImageExtensions: Set<String> = ["gif", "jpg", "jpeg", "png", "webp"]
}
