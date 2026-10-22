import CoreGraphics
import Foundation

/// 共享调度器及帧缓存；也可为不同页面创建独立环境。
@MainActor
public final class PlaybackEnvironment {
    public static let shared = PlaybackEnvironment()
    internal let cache: FrameCache
    private let queue: OperationQueue
    private let decoderFactory: DecoderFactory
    private let posterFactory: PosterFactory
    private var stores: [StoreKey: FrameStore] = [:]

    public convenience init(maximumConcurrentDecodes: Int = 2, maximumBufferBytes: Int = 32 * 1_024 * 1_024) {
        self.init(
            maximumConcurrentDecodes: maximumConcurrentDecodes, maximumBufferBytes: maximumBufferBytes,
            decoderFactory: { try ImageIODecoder(data: $0, configuration: $1) },
            posterFactory: { ImageIODecoder.poster(data: $0, configuration: $1) }
        )
    }

    internal init(
        maximumConcurrentDecodes: Int = 2, maximumBufferBytes: Int = 32 * 1_024 * 1_024,
        decoderFactory: @escaping DecoderFactory, posterFactory: @escaping PosterFactory
    ) {
        cache = FrameCache(maximumBytes: maximumBufferBytes)
        queue = OperationQueue()
        queue.name = "FramePlay.decode"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = max(1, maximumConcurrentDecodes)
        self.decoderFactory = decoderFactory
        self.posterFactory = posterFactory
    }

    public var statistics: FrameCacheStatistics {
        FrameCacheStatistics(bufferedBytes: cache.bytes, bufferedFrames: cache.count,
                             resourceCount: stores.count, pendingOperations: queue.operationCount)
    }

    /// 已显示帧由播放器/调用者持有；清理缓存不会让画面闪烁。
    public func trimMemory() { cache.removeAll() }

    internal func allowance(for key: StoreKey) -> Int {
        guard let store = stores[key] else { return 0 }
        let demand = store.memoryDemand
        let demands = stores.values.map(\.memoryDemand)
        let reserved = demands.reduce(0) { $0 + $1.minimum }
        guard reserved <= cache.maximumBytes else { return 0 }
        let room = max(0, demand.preferred - demand.minimum)
        let totalRoom = demands.reduce(0) { $0 + max(0, $1.preferred - $1.minimum) }
        let remaining = cache.maximumBytes - reserved
        let extra = totalRoom > 0 ? Int(min(Double(room), Double(remaining) * (Double(room) / Double(totalRoom)))) : 0
        return min(key.byteLimit, demand.minimum + extra)
    }

    internal func acquire(source: AnimatedImageSource, configuration: PlaybackConfiguration) -> FrameStore {
        let key = StoreKey(source: source, configuration: configuration)
        if let store = stores[key] { return store }
        let store = FrameStore(
            key: key, source: source, configuration: configuration, environment: self,
            decoderFactory: decoderFactory, posterFactory: posterFactory
        )
        stores[key] = store
        store.prepare()
        return store
    }

    internal func release(key: StoreKey, observer: UUID) {
        guard let store = stores[key] else { return }
        store.removeObserver(observer)
        if store.observerCount == 0 {
            store.close()
            cache.trim(store: key)
            stores.removeValue(forKey: key)
            // 等待预算的其他资源可在订阅释放后继续交付。
            Array(stores.values).forEach { $0.pump() }
        }
    }

    internal func schedule<T: Sendable>(
        work: @escaping @Sendable () -> T,
        completion: @escaping @MainActor @Sendable (T) -> Void
    ) -> Operation {
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak operation] in
            guard let operation, !operation.isCancelled else { return }
            let result = autoreleasepool(invoking: work)
            guard !operation.isCancelled else { return }
            Task { @MainActor in completion(result) }
        }
        queue.addOperation(operation)
        return operation
    }
}

internal struct DecodeFailure: Error, Sendable {
    let reason: PlaybackFailure
    let poster: CGImage?
}

@MainActor
internal final class FrameStore {
    private struct Interest {
        var index: Int?
        var prefetch = false
        var required = false
        let notify: @MainActor () -> Void
    }
    let key: StoreKey
    private let source: AnimatedImageSource
    private let configuration: PlaybackConfiguration
    private weak var environment: PlaybackEnvironment?
    private let decoderFactory: DecoderFactory
    private let posterFactory: PosterFactory
    private var decoder: (any FrameDecoding)?
    private var operation: Operation?
    private var closed = false
    private var observers: [UUID: Interest] = [:]
    private var observerOrder: [UUID] = []
    private var frameBytes = 1
    private(set) var metadata: AnimationMetadata?
    private(set) var failure: DecodeFailure?

    init(key: StoreKey, source: AnimatedImageSource, configuration: PlaybackConfiguration,
         environment: PlaybackEnvironment, decoderFactory: @escaping DecoderFactory, posterFactory: @escaping PosterFactory) {
        self.key = key
        self.source = source
        self.configuration = configuration
        self.environment = environment
        self.decoderFactory = decoderFactory
        self.posterFactory = posterFactory
    }

    var observerCount: Int { observers.count }

    var memoryDemand: (minimum: Int, preferred: Int) {
        guard let metadata else { return (0, 0) }
        let requested = Set(observers.values.compactMap(\.index))
        guard !requested.isEmpty else { return (0, 0) }
        let count = observers.values.contains(where: \.prefetch) ? frameLimit : requested.count
        // 显示帧已由播放器持有；只需为解码结果交接保留一帧，其余空间用于预取。
        return (frameBytes, min(configuration.bufferBytes, frameBytes * min(count, metadata.frameCount)))
    }

    func addObserver(_ id: UUID, notify: @escaping @MainActor () -> Void) {
        observers[id] = Interest(notify: notify)
        observerOrder.append(id)
    }

    func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
        observerOrder.removeAll { $0 == id }
    }

    func interest(_ id: UUID, index: Int?, prefetch: Bool, required: Bool = true) {
        guard var value = observers[id], !closed else { return }
        value.index = index
        value.prefetch = prefetch
        value.required = required
        observers[id] = value
        pump()
    }

    func frame(at index: Int) -> CGImage? { environment?.cache.image(store: key, index: index) }

    func prepare() {
        guard operation == nil, !closed, let environment else { return }
        let source = source, configuration = configuration, factory = decoderFactory, poster = posterFactory
        operation = environment.schedule(work: {
            do {
                return Result<any FrameDecoding, DecodeFailure>.success(try factory(source.data, configuration))
            } catch {
                let reason = error as? PlaybackFailure ?? .invalidImageData
                let fallback = reason == .resourceLimitExceeded ? nil : poster(source.data, configuration)
                return .failure(DecodeFailure(reason: reason, poster: fallback))
            }
        }, completion: { [weak self] result in
            guard let self, !self.closed else { return }
            self.operation = nil
            switch result {
            case .success(let decoder):
                let metadata = decoder.metadata
                guard metadata.frameCount > 0, metadata.frameCount <= configuration.limits.maximumFrameCount,
                      metadata.pixelWidth > 0, metadata.pixelHeight > 0,
                      metadata.pixelWidth <= configuration.limits.maximumCanvasPixels / metadata.pixelHeight,
                      metadata.duration.isFinite, metadata.duration > 0,
                      metadata.frameDurations.allSatisfy({ $0.isFinite && $0 > 0 }),
                      metadata.totalPlayCount == nil || metadata.totalPlayCount! > 0 else {
                    self.failure = DecodeFailure(reason: .invalidMetadata, poster: nil)
                    self.notify()
                    return
                }
                let ratio = min(1, Double(configuration.maximumPixelSize) / Double(max(metadata.pixelWidth, metadata.pixelHeight)))
                let width = max(1, Int(ceil(Double(metadata.pixelWidth) * ratio)))
                let height = max(1, Int(ceil(Double(metadata.pixelHeight) * ratio)))
                self.frameBytes = width * height * 4
                guard width <= min(configuration.bufferBytes, environment.cache.maximumBytes) / 4 / height else {
                    self.failure = DecodeFailure(reason: .resourceLimitExceeded, poster: nil)
                    self.notify()
                    return
                }
                self.decoder = decoder
                self.metadata = metadata
            case .failure(let failure): self.failure = failure
            }
            self.notify()
            self.pump()
        })
    }

    func close() {
        closed = true
        operation?.cancel()
        operation = nil
        observers.removeAll()
        observerOrder.removeAll()
        decoder = nil
    }

    private func demands() -> [Int] {
        guard let metadata else { return [] }
        let interests = observerOrder.compactMap { observers[$0] }.filter { $0.index != nil }
        // 待显示帧优先；超过容量时依次交付，不将暂时的缓冲竞争视为数据损坏。
        var result: [Int] = []
        for interest in interests where interest.required {
            if let index = interest.index, !result.contains(index) { result.append(index) }
        }
        for offset in 0 ..< min(configuration.maximumBufferedFrames, metadata.frameCount) {
            for interest in interests where interest.prefetch {
                guard let start = interest.index else { continue }
                let index = (start + offset) % metadata.frameCount
                if !result.contains(index) { result.append(index) }
            }
        }
        return Array(result.prefix(capacity))
    }

    private var capacity: Int {
        min(frameLimit, (environment?.allowance(for: key) ?? 0) / frameBytes)
    }

    private var frameLimit: Int {
        guard let metadata else { return 0 }
        let positions = Set(observers.values.compactMap(\.index)).count
        // 合并不同播放位置的窗口；同步播放不扩容，字节预算始终约束共享池。
        return min(metadata.frameCount, configuration.maximumBufferedFrames * min(positions, metadata.frameCount))
    }

    func pump() {
        guard !closed, failure == nil, operation == nil, let decoder, let environment else { return }
        guard capacity > 0 else { return }
        let demands = demands()
        environment.cache.trim(store: key, keeping: Set(demands))
        guard let index = demands.first(where: { !environment.cache.contains(store: key, index: $0) }) else { return }
        let data = source.data, configuration = configuration, poster = posterFactory
        operation = environment.schedule(work: {
            do { return Result<CGImage, DecodeFailure>.success(try decoder.frame(at: index)) }
            catch {
                return .failure(DecodeFailure(reason: error as? PlaybackFailure ?? .frameDecodingFailed(index: index),
                                              poster: index == 0 ? poster(data, configuration) : nil))
            }
        }, completion: { [weak self] result in
            guard let self, !self.closed else { return }
            self.operation = nil
            switch result {
            case .success(let image):
                // 播放位置已变化的预取结果不再进入缓存。
                let demands = Set(self.demands())
                if demands.contains(index) {
                    // 解码期间窗口可能前移；先移除过期项，避免 LRU 淘汰下一张显示帧。
                    environment.cache.trim(store: self.key, keeping: demands)
                    do { try environment.cache.insert(image, store: self.key, index: index, frameLimit: self.capacity,
                                                      preferredIndexes: Set(self.observers.values.filter(\.required).compactMap(\.index))) }
                    catch { self.failure = DecodeFailure(reason: .resourceLimitExceeded, poster: image) }
                }
            case .failure(let failure): self.failure = failure
            }
            self.notify()
            self.pump()
        })
    }

    private func notify() { Array(observers.values).forEach { $0.notify() } }
}
