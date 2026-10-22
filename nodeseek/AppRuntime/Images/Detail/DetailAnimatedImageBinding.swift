import FramePlay
import UIKit

/// 将核心播放器接到已有 UIImageView，保留详情图的裁剪、手势和布局。
@MainActor
final class DetailAnimatedImageBinding: NSObject {
    private weak var imageView: UIImageView?
    private let environment: PlaybackEnvironment
    private let player: AnimatedImagePlayer
    private var asset: DetailAnimatedImageAsset?
    private var fallbackImage: UIImage?
    private var isVisible = false

    var hasAnimation: Bool { asset != nil }
    var state: PlaybackState { player.state }
    var isPlaying: Bool { player.state == .playing }

    convenience init(imageView: UIImageView) {
        self.init(imageView: imageView, environment: .shared)
    }

    init(imageView: UIImageView, environment: PlaybackEnvironment) {
        self.imageView = imageView
        self.environment = environment
        player = AnimatedImagePlayer(environment: environment)
        super.init()
        player.onFrame = { [weak self] frame in
            guard let self else { return }
            self.imageView?.image = frame.map { UIImage(cgImage: $0) } ?? self.fallbackImage
        }
        NotificationCenter.default.addObserver(self, selector: #selector(background),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updatePlayback),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    func load(_ asset: DetailAnimatedImageAsset, poster: UIImage?, maximumPixelSize: Int) {
        self.asset = asset
        fallbackImage = poster
        player.load(asset.source, configuration: PlaybackConfiguration(
            maximumPixelSize: max(1, min(maximumPixelSize, DetailWebPAnimation.maximumPixelSize)),
            bufferBytes: 16 * 1_024 * 1_024
        ), fallbackImage: poster?.cgImage, autoplay: false)
        updatePlayback()
    }

    func setVisible(_ visible: Bool) { isVisible = visible; updatePlayback() }
    func windowDidChange() { updatePlayback() }

    func reset() {
        asset = nil
        fallbackImage = nil
        player.reset()
    }

    @objc private func updatePlayback() {
        if isVisible, imageView?.window != nil, UIApplication.shared.applicationState != .background {
            player.play()
        } else {
            player.pause()
        }
    }

    @objc private func background() { player.pause(); environment.trimMemory() }
}
