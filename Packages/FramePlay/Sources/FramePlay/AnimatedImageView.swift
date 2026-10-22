#if canImport(UIKit)
import UIKit

/// UIKit 适配层。显式 setPlaybackVisible(false) 可用于列表中仍在窗口内、但已滚出屏幕的视图。
@MainActor
public final class AnimatedImageView: UIView {
    public var onFallback: (@MainActor (PlaybackFailure) -> Void)?
    public var onStateChange: (@MainActor (PlaybackState) -> Void)?
    public var state: PlaybackState { player.state }
    public var displayedImage: UIImage? { imageView.image }
    public var autoPlay = true
    public var imageContentMode: UIView.ContentMode {
        get { imageView.contentMode }
        set { imageView.contentMode = newValue }
    }

    private let player: AnimatedImagePlayer
    private let environment: PlaybackEnvironment
    private let imageView = UIImageView()
    private var requestedPlayback = true
    private var playbackVisible = true
    private var fallbackImage: UIImage?

    public init(environment: PlaybackEnvironment = .shared) {
        self.environment = environment
        player = AnimatedImagePlayer(environment: environment)
        super.init(frame: .zero)
        configure()
    }

    public override init(frame: CGRect) {
        environment = .shared
        player = AnimatedImagePlayer()
        super.init(frame: frame)
        configure()
    }

    public required init?(coder: NSCoder) {
        environment = .shared
        player = AnimatedImagePlayer()
        super.init(coder: coder)
        configure()
    }

    public func load(_ source: AnimatedImageSource, configuration: PlaybackConfiguration = PlaybackConfiguration(), fallbackImage: UIImage? = nil) {
        requestedPlayback = autoPlay
        self.fallbackImage = fallbackImage
        imageView.image = fallbackImage
        player.load(source, configuration: configuration, fallbackImage: fallbackImage?.cgImage,
                    autoplay: shouldPlay)
    }

    public func play() { requestedPlayback = true; updatePlayback() }
    public func pause() { requestedPlayback = false; player.pause() }
    public func stop() { requestedPlayback = false; player.stop() }

    public func setPlaybackVisible(_ visible: Bool) {
        playbackVisible = visible
        updatePlayback()
    }

    public func prepareForReuse() {
        requestedPlayback = false
        fallbackImage = nil
        player.reset()
        imageView.image = nil
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePlayback()
    }

    private var shouldPlay: Bool {
        requestedPlayback && playbackVisible && window != nil && UIApplication.shared.applicationState != .background
    }

    private func configure() {
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        player.onFrame = { [weak self] frame in
            guard let self else { return }
            if let fallbackImage, frame == nil || frame === fallbackImage.cgImage { imageView.image = fallbackImage }
            else { imageView.image = frame.map { UIImage(cgImage: $0) } }
        }
        player.onFallback = { [weak self] reason in self?.onFallback?(reason) }
        player.onStateChange = { [weak self] state in self?.onStateChange?(state) }
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    private func updatePlayback() { if shouldPlay { player.play() } else { player.pause() } }

    @objc private func background() { player.pause(); environment.trimMemory() }
    @objc private func foreground() { updatePlayback() }
}
#endif
