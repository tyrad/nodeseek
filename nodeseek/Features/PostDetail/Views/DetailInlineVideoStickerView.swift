//
//  DetailInlineVideoStickerView.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import AVFoundation
import UIKit

/// 帖子详情富文本中的内联视频贴纸视图。
final class DetailInlineVideoStickerView: UIView {
    private let videoURL: URL
    private let thumbnailView = UIImageView()
    private let playButton = UIButton(type: .system)
    private let playerLayer = AVPlayerLayer()
    private var thumbnailToken: UUID?
    private var thumbnailTask: Task<Void, Never>?
    private var thumbnailGenerator: AVAssetImageGenerator?
    private var playbackToken: UUID?
    private var playbackTask: Task<Void, Never>?
    private var isPlaying = false

    init(frame: CGRect, videoURL: URL) {
        self.videoURL = videoURL
        super.init(frame: frame)

        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = true
        isUserInteractionEnabled = true

        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        addSubview(thumbnailView)

        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.isHidden = true
        layer.addSublayer(playerLayer)

        playButton.tintColor = .white
        playButton.backgroundColor = UIColor.black.withAlphaComponent(0.38)
        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.accessibilityLabel = "播放贴纸"
        playButton.isUserInteractionEnabled = false
        addSubview(playButton)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        thumbnailView.frame = bounds
        playerLayer.frame = bounds
        let side = min(bounds.width, bounds.height, 30)
        playButton.frame = CGRect(
            x: (bounds.width - side) / 2,
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        )
        playButton.layer.cornerRadius = side / 2
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()

        guard superview != nil else {
            StickerVideoPlaybackCoordinator.shared.stop(owner: self)
            thumbnailTask?.cancel()
            thumbnailTask = nil
            thumbnailToken = nil
            thumbnailGenerator?.cancelAllCGImageGeneration()
            thumbnailGenerator = nil
            playbackTask?.cancel()
            playbackTask = nil
            playbackToken = nil
            return
        }

        loadThumbnailIfNeeded()
    }

    func playbackCoordinatorDidStop() {
        playbackTask?.cancel()
        playbackTask = nil
        playbackToken = nil
        isPlaying = false
        playerLayer.player = nil
        playerLayer.isHidden = true
        thumbnailView.isHidden = false
        playButton.isHidden = false
    }

    private func loadThumbnailIfNeeded() {
        guard thumbnailTask == nil,
              thumbnailToken == nil,
              thumbnailView.image == nil,
              let resolvedURL = ImageURLResolver.resolve(videoURL) else { return }

        let token = UUID()
        thumbnailToken = token
        thumbnailTask = Task { @MainActor [weak self] in
            let asset = await DetailVideoAssetProvider.shared.makeAsset(for: resolvedURL)
            guard let self,
                  Task.isCancelled == false,
                  self.thumbnailToken == token,
                  self.superview != nil else { return }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 180, height: 180)
            self.thumbnailGenerator = generator
            generator.generateCGImageAsynchronously(for: .zero) { [weak self] cgImage, _, _ in
                DispatchQueue.main.async {
                    guard let self, self.thumbnailToken == token else { return }
                    self.thumbnailTask = nil
                    self.thumbnailGenerator = nil
                    self.thumbnailView.image = cgImage.map(UIImage.init(cgImage:))
                }
            }
        }
    }

    @objc
    private func handleTap() {
        if isPlaying {
            StickerVideoPlaybackCoordinator.shared.stop(owner: self)
            return
        }

        guard playbackTask == nil,
              let resolvedURL = ImageURLResolver.resolve(videoURL) else { return }

        let token = UUID()
        playbackToken = token
        playbackTask = Task { @MainActor [weak self] in
            let asset = await DetailVideoAssetProvider.shared.makeAsset(for: resolvedURL)
            guard let self else { return }
            defer {
                if self.playbackToken == token {
                    self.playbackTask = nil
                }
            }
            guard Task.isCancelled == false,
                  self.playbackToken == token,
                  self.superview != nil else { return }

            self.isPlaying = true
            self.playerLayer.isHidden = false
            self.thumbnailView.isHidden = true
            self.playButton.isHidden = true
            StickerVideoPlaybackCoordinator.shared.play(asset, in: self.playerLayer, owner: self)
        }
    }
}

private final class StickerVideoPlaybackCoordinator {
    static let shared = StickerVideoPlaybackCoordinator()

    private let player = AVPlayer()
    private weak var activeView: DetailInlineVideoStickerView?
    private weak var activeLayer: AVPlayerLayer?
    private var endObserver: NSObjectProtocol?

    private init() {
        player.isMuted = true
    }

    func play(_ asset: AVURLAsset, in layer: AVPlayerLayer, owner: DetailInlineVideoStickerView) {
        if activeView !== owner {
            activeView?.playbackCoordinatorDidStop()
            activeLayer?.player = nil
        }

        removeEndObserver()
        let item = AVPlayerItem(asset: asset)
        activeView = owner
        activeLayer = layer
        layer.player = player
        player.replaceCurrentItem(with: item)
        player.isMuted = true
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.player.seek(to: .zero)
            self?.player.play()
        }
        player.play()
    }

    func stop(owner: DetailInlineVideoStickerView) {
        guard activeView === owner else { return }
        stopCurrent()
    }

    private func stopCurrent() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        removeEndObserver()
        let view = activeView
        activeView = nil
        activeLayer?.player = nil
        activeLayer = nil
        view?.playbackCoordinatorDidStop()
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}
