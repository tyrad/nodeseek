import CoreGraphics
import Foundation

@MainActor
public final class AnimatedImagePlayer {
    public var onFrame: (@MainActor (CGImage?) -> Void)?
    public var onStateChange: (@MainActor (PlaybackState) -> Void)?
    public var onFallback: (@MainActor (PlaybackFailure) -> Void)?
    public private(set) var state: PlaybackState = .idle
    public private(set) var currentFrame: CGImage?
    public private(set) var currentFrameIndex: Int?
    public private(set) var metadata: AnimationMetadata?

    private let environment: PlaybackEnvironment
    private let clock: any PlaybackClock
    private var store: FrameStore?
    private var lease: (key: StoreKey, observer: UUID)?
    private var generation: UInt64 = 0
    private var configuration = PlaybackConfiguration()
    private var suppliedFallback: CGImage?
    private var lastDecodedFrame: CGImage?
    private var wantsPlayback = false
    private var needsRestart = false
    private var waitingIndex: Int?
    private var resumeIndex: Int?
    private var stalledSince: TimeInterval?
    private var previousTick: TimeInterval?
    private var frameElapsed: TimeInterval = 0
    private var timelineElapsed: TimeInterval = 0
    private var completedPlays = 0
    private var finishesAfterPendingFrame = false
    private var frameEnds: [TimeInterval] = []

    public convenience init(environment: PlaybackEnvironment = .shared) {
        self.init(environment: environment, clock: SystemPlaybackClock())
    }

    internal init(environment: PlaybackEnvironment, clock: any PlaybackClock) {
        self.environment = environment
        self.clock = clock
        clock.onTick = { [weak self] time in self?.tick(at: time) }
    }

    deinit {
        let environment = environment
        let clock = clock, lease = lease
        Task { @MainActor in
            clock.stop()
            if let lease { environment.release(key: lease.key, observer: lease.observer) }
        }
    }

    public func load(
        _ source: AnimatedImageSource,
        configuration: PlaybackConfiguration = PlaybackConfiguration(),
        fallbackImage: CGImage? = nil,
        autoplay: Bool = true
    ) {
        detach()
        generation &+= 1
        let token = generation
        self.configuration = configuration
        suppliedFallback = fallbackImage
        lastDecodedFrame = nil
        currentFrameIndex = nil
        metadata = nil
        frameEnds = []
        frameElapsed = 0
        timelineElapsed = 0
        completedPlays = 0
        finishesAfterPendingFrame = false
        needsRestart = false
        wantsPlayback = autoplay
        waitingIndex = 0
        resumeIndex = nil
        stalledSince = clock.now
        previousTick = clock.now
        publish(frame: .value(fallbackImage), state: .loading)
        guard generation == token else { return }
        guard configuration.isValid else { fallback(.invalidConfiguration); return }
        guard source.data.count <= configuration.limits.maximumDataBytes else { fallback(.resourceLimitExceeded); return }
        let store = environment.acquire(source: source, configuration: configuration)
        let observer = UUID()
        self.store = store
        lease = (store.key, observer)
        store.addObserver(observer) { [weak self] in
            guard let self, self.generation == token else { return }
            self.receive()
        }
        store.interest(observer, index: 0, prefetch: wantsPlayback)
        guard generation == token else { return }
        clock.start()
        receive()
    }

    public func play() {
        guard store != nil else { return }
        if state == .playing && wantsPlayback { return }
        wantsPlayback = true
        if state == .loading { stalledSince = clock.now; previousTick = clock.now; clock.start(); return }
        guard let metadata, metadata.frameCount > 1 else { return }
        let token = generation
        if needsRestart || state == .finished {
            frameElapsed = 0
            timelineElapsed = 0
            completedPlays = 0
            finishesAfterPendingFrame = false
            waitingIndex = 0
            stalledSince = clock.now
            needsRestart = false
            resumeIndex = nil
        } else if let resumeIndex {
            waitingIndex = resumeIndex
            stalledSince = clock.now
            self.resumeIndex = nil
        }
        previousTick = clock.now
        publish(state: .playing)
        guard generation == token, state == .playing else { return }
        clock.start()
        request(index: waitingIndex ?? ((currentFrameIndex ?? 0) + 1) % metadata.frameCount,
                prefetch: true, required: waitingIndex != nil)
        receive()
    }

    public func pause() {
        let token = generation
        wantsPlayback = false
        clock.stop()
        previousTick = nil
        if state == .loading {
            // 准备阶段仍需要时钟来执行初始化超时回退。
            clock.start()
            return
        }
        guard state == .playing else { return }
        resumeIndex = waitingIndex
        waitingIndex = nil
        finishesAfterPendingFrame = false
        stalledSince = nil
        request(index: nil, prefetch: false)
        guard generation == token else { return }
        publish(state: .paused)
    }

    /// 停止并保留当前画面；下一次 play 从首帧重新开始。
    public func stop() {
        let token = generation
        wantsPlayback = false
        clock.stop()
        previousTick = nil
        needsRestart = true
        resumeIndex = nil
        if state == .loading { clock.start(); return }
        waitingIndex = nil
        finishesAfterPendingFrame = false
        stalledSince = nil
        guard state == .playing || state == .paused || state == .finished else { return }
        request(index: nil, prefetch: false)
        guard generation == token else { return }
        publish(state: .ready)
    }

    public func reset() {
        detach()
        generation &+= 1
        wantsPlayback = false
        metadata = nil
        currentFrameIndex = nil
        lastDecodedFrame = nil
        suppliedFallback = nil
        waitingIndex = nil
        resumeIndex = nil
        stalledSince = nil
        frameEnds.removeAll()
        publish(frame: .value(nil), state: .idle)
    }

    private func receive() {
        guard let store else { return }
        if let failure = store.failure { fallback(failure.reason, poster: failure.poster); return }
        if metadata == nil, let metadata = store.metadata {
            self.metadata = metadata
            var end: TimeInterval = 0
            frameEnds = metadata.frameDurations.map { end += $0; return end }
        }
        guard let index = waitingIndex, let image = store.frame(at: index), let metadata else { return }
        let token = generation
        currentFrameIndex = index
        lastDecodedFrame = image
        waitingIndex = nil
        stalledSince = nil
        let nextState: PlaybackState
        if finishesAfterPendingFrame {
            finishesAfterPendingFrame = false
            wantsPlayback = false
            needsRestart = true
            nextState = .finished
        } else {
            nextState = metadata.frameCount == 1 ? .staticImage : wantsPlayback ? .playing : .ready
        }
        if nextState == .playing { previousTick = clock.now; clock.start() }
        else { clock.stop() }
        publish(frame: .value(image), state: nextState)
        guard generation == token, state == nextState else { return }
        request(index: nextState == .playing ? (index + 1) % metadata.frameCount : nil,
                prefetch: nextState == .playing, required: false)
    }

    private func request(index: Int?, prefetch: Bool, required: Bool = true) {
        guard let lease else { return }
        store?.interest(lease.observer, index: index, prefetch: prefetch, required: required)
    }

    private func tick(at time: TimeInterval) {
        guard time.isFinite else { return }
        let delta = max(0, time - (previousTick ?? time))
        previousTick = time
        if let stalledSince, time - stalledSince >= configuration.bufferTimeout {
            fallback(.bufferTimeout)
            return
        }
        guard state == .playing, let metadata, let currentIndex = currentFrameIndex else { return }
        if configuration.frameDropPolicy == .preserveTiming {
            timelineElapsed += delta
            if let plays = metadata.totalPlayCount, timelineElapsed >= metadata.duration * Double(plays) {
                let token = generation
                finishesAfterPendingFrame = true
                displayOrWait(index: metadata.frameCount - 1, time: time)
                if generation == token && state == .playing && waitingIndex == nil { finish() }
                return
            }
            let phase = timelineElapsed.truncatingRemainder(dividingBy: metadata.duration)
            if metadata.totalPlayCount == nil { timelineElapsed = phase }
            guard phase.isFinite else { return }
            let target = frameIndex(at: phase)
            if target != currentIndex || waitingIndex != nil { displayOrWait(index: target, time: time) }
        } else {
            if waitingIndex != nil { return }
            frameElapsed += delta
            guard frameElapsed >= metadata.frameDurations[currentIndex] else { return }
            if currentIndex == metadata.frameCount - 1 {
                completedPlays += 1
                if let plays = metadata.totalPlayCount, completedPlays >= plays { finish(); return }
            }
            let next = (currentIndex + 1) % metadata.frameCount
            frameElapsed = min(frameElapsed - metadata.frameDurations[currentIndex], metadata.frameDurations[next])
            displayOrWait(index: next, time: time)
        }
    }

    private func displayOrWait(index: Int, time: TimeInterval) {
        guard let store else { return }
        let token = generation
        if let failure = store.failure { fallback(failure.reason, poster: failure.poster); return }
        if let image = store.frame(at: index) {
            currentFrameIndex = index
            lastDecodedFrame = image
            waitingIndex = nil
            stalledSince = nil
            publish(frame: .value(image))
            guard generation == token, state == .playing, let metadata else { return }
            request(index: (index + 1) % metadata.frameCount, prefetch: true, required: false)
        } else {
            waitingIndex = index
            if stalledSince == nil { stalledSince = time }
            request(index: index, prefetch: true)
        }
    }

    private func frameIndex(at phase: TimeInterval) -> Int {
        var low = 0, high = frameEnds.count - 1
        while low < high {
            let middle = (low + high) / 2
            if phase < frameEnds[middle] { high = middle } else { low = middle + 1 }
        }
        return low
    }

    private func finish() {
        let token = generation
        wantsPlayback = false
        needsRestart = true
        clock.stop()
        waitingIndex = nil
        stalledSince = nil
        finishesAfterPendingFrame = false
        request(index: nil, prefetch: false)
        guard generation == token else { return }
        publish(state: .finished)
    }

    private func fallback(_ reason: PlaybackFailure, poster: CGImage? = nil) {
        let image = lastDecodedFrame ?? poster ?? suppliedFallback
        generation &+= 1
        detach()
        wantsPlayback = false
        resumeIndex = nil
        waitingIndex = nil
        stalledSince = nil
        publish(frame: .value(image), state: .staticFallback(reason), failure: reason)
    }

    private func detach() {
        clock.stop()
        if let lease { environment.release(key: lease.key, observer: lease.observer) }
        lease = nil
        store = nil
    }

    /// 先提交状态再通知；用户回调重入 load/reset 后，不再发送旧资源事件。
    private enum FrameUpdate { case unchanged; case value(CGImage?) }

    private func publish(frame: FrameUpdate = .unchanged, state newState: PlaybackState? = nil, failure: PlaybackFailure? = nil) {
        let token = generation
        let changed = newState.map { $0 != state } ?? false
        if let newState { state = newState }
        if case .value(let frame) = frame { currentFrame = frame; onFrame?(frame) }
        guard generation == token else { return }
        if changed, let newState, state == newState { onStateChange?(state) }
        guard generation == token else { return }
        if let failure { onFallback?(failure) }
    }
}
