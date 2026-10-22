import CoreGraphics
import Foundation

/// 复制该值或在不同播放器中复用它，可共享同一像素规格的解码帧。
public struct AnimatedImageSource: Sendable {
    internal let id = UUID()
    internal let data: Data

    public init(data: Data) { self.data = data }
}

public enum FrameDropPolicy: Sendable, Hashable {
    /// 等待缺失帧，保留内容，允许播放变慢。
    case preserveFrames
    /// 跳过已经过期的显示帧，尽量跟随原始时间轴。
    case preserveTiming
}

public struct DecodeLimits: Sendable, Hashable {
    public var maximumDataBytes = 64 * 1_024 * 1_024
    public var maximumCanvasPixels = 40_000_000
    public var maximumFrameCount = 5_000

    public init() {}
}

public struct PlaybackConfiguration: Sendable, Hashable {
    public var maximumPixelSize: Int
    public var bufferBytes: Int
    /// 每个活动播放位置的预取窗口；共享池合并这些窗口，仍受字节预算约束。
    public var maximumBufferedFrames: Int
    public var bufferTimeout: TimeInterval
    public var frameDropPolicy: FrameDropPolicy
    public var limits: DecodeLimits

    public init(
        maximumPixelSize: Int = 512,
        bufferBytes: Int = 8 * 1_024 * 1_024,
        maximumBufferedFrames: Int = 6,
        bufferTimeout: TimeInterval = 2,
        frameDropPolicy: FrameDropPolicy = .preserveFrames,
        limits: DecodeLimits = DecodeLimits()
    ) {
        self.maximumPixelSize = maximumPixelSize
        self.bufferBytes = bufferBytes
        self.maximumBufferedFrames = maximumBufferedFrames
        self.bufferTimeout = bufferTimeout
        self.frameDropPolicy = frameDropPolicy
        self.limits = limits
    }

    internal var isValid: Bool {
        maximumPixelSize > 0 && maximumPixelSize <= 16_384
            && bufferBytes > 0 && maximumBufferedFrames > 0 && maximumBufferedFrames <= 5_000
            && bufferTimeout.isFinite && bufferTimeout > 0
            && limits.maximumDataBytes > 0 && limits.maximumCanvasPixels > 0 && limits.maximumFrameCount > 0
    }
}

public enum PlaybackFailure: Error, Sendable, Equatable {
    case invalidConfiguration
    case invalidImageData
    case invalidMetadata
    case unsupportedAnimatedFormat
    case resourceLimitExceeded
    case frameDecodingFailed(index: Int)
    case bufferTimeout
}

public enum PlaybackState: Sendable, Equatable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case finished
    case staticImage
    case staticFallback(PlaybackFailure)
}

public struct AnimationMetadata: Sendable, Equatable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let frameDurations: [TimeInterval]
    /// 总播放轮数；nil 表示无限播放。
    public let totalPlayCount: Int?

    public var frameCount: Int { frameDurations.count }
    public var duration: TimeInterval { frameDurations.reduce(0, +) }

    internal init(pixelWidth: Int, pixelHeight: Int, frameDurations: [TimeInterval], totalPlayCount: Int?) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.frameDurations = frameDurations
        self.totalPlayCount = totalPlayCount
    }
}

public struct FrameCacheStatistics: Sendable, Equatable {
    public let bufferedBytes: Int
    public let bufferedFrames: Int
    public let resourceCount: Int
    public let pendingOperations: Int
}
