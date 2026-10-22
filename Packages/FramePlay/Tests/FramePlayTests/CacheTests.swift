import XCTest
@testable import FramePlay

@MainActor
final class CacheTests: XCTestCase {
    func testByteBudgetsAndSerialSchedulerRemainBoundedWithoutIdleDecodeLoop() async throws {
        let probe = DecodeProbe()
        let env = PlaybackEnvironment(maximumConcurrentDecodes: 1, maximumBufferBytes: 1_024, decoderFactory: { _, _ in
            probe.created()
            return FakeDecoder(durations: Array(repeating: 0.1, count: 10), probe: probe, delay: 0.001)
        }, posterFactory: { _, _ in nil })
        let firstClock = ManualClock(), secondClock = ManualClock()
        let first = AnimatedImagePlayer(environment: env, clock: firstClock)
        let second = AnimatedImagePlayer(environment: env, clock: secondClock)
        let configuration = PlaybackConfiguration(bufferBytes: 768)
        first.load(AnimatedImageSource(data: Data([1])), configuration: configuration)
        second.load(AnimatedImageSource(data: Data([2])), configuration: configuration)
        try await eventually { first.state == .playing && second.state == .playing && env.statistics.pendingOperations == 0 }
        XCTAssertLessThanOrEqual(env.statistics.bufferedBytes, 1_024)
        XCTAssertLessThanOrEqual(env.statistics.bufferedFrames, 4)
        let initial = probe.snapshot.counts
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(probe.snapshot.counts, initial, "缓存比帧数限制小时也不能空转解码")
        XCTAssertEqual(probe.snapshot.peak, 1)
        XCTAssertFalse(probe.snapshot.usedMain)
        for _ in 0 ..< 8 {
            firstClock.advance(0.11)
            secondClock.advance(0.11)
            try await eventually { env.statistics.pendingOperations == 0 }
            XCTAssertLessThanOrEqual(env.statistics.bufferedBytes, 1_024)
        }
        first.reset()
        second.reset()
        XCTAssertEqual(env.statistics.bufferedFrames, 0)
    }

    func testRenderingVariantsDoNotShareIncompatibleFramesAndTrimPreservesDisplay() async throws {
        let env = environment(FakeDecoder())
        let source = AnimatedImageSource(data: Data([1]))
        let first = AnimatedImagePlayer(environment: env, clock: ManualClock())
        let second = AnimatedImagePlayer(environment: env, clock: ManualClock())
        first.load(source, configuration: PlaybackConfiguration(maximumPixelSize: 160))
        second.load(source, configuration: PlaybackConfiguration(maximumPixelSize: 320))
        try await eventually { first.state == .playing && second.state == .playing }
        XCTAssertEqual(env.statistics.resourceCount, 2)
        let frame = first.currentFrame
        env.trimMemory()
        XCTAssertEqual(env.statistics.bufferedBytes, 0)
        XCTAssertTrue(first.currentFrame === frame)
    }

    func testGlobalConcurrencyIsLimitedAcrossIndependentSources() async throws {
        let probe = DecodeProbe()
        let env = PlaybackEnvironment(maximumConcurrentDecodes: 2, decoderFactory: { _, _ in
            FakeDecoder(probe: probe, delay: 0.005)
        }, posterFactory: { _, _ in nil })
        let players = (0 ..< 4).map { _ in AnimatedImagePlayer(environment: env, clock: ManualClock()) }
        for player in players { player.load(AnimatedImageSource(data: Data([1]))) }
        try await eventually { players.allSatisfy { $0.state == .playing } && env.statistics.pendingOperations == 0 }
        XCTAssertLessThanOrEqual(probe.snapshot.peak, 2)
        XCTAssertGreaterThan(probe.snapshot.peak, 0)
        XCTAssertFalse(probe.snapshot.usedMain)
        players.forEach { $0.reset() }
    }

    func testDifferentFrameSizesReserveEnoughForBothCurrentFrames() async throws {
        let large = FakeDecoder(frames: (0 ..< 3).map { _ in TestFixtures.frame(side: 16) })
        let small = FakeDecoder()
        let env = PlaybackEnvironment(maximumBufferBytes: 1_280, decoderFactory: { data, _ in
            data.first == 1 ? large : small
        }, posterFactory: { _, _ in nil })
        let first = AnimatedImagePlayer(environment: env, clock: ManualClock())
        let second = AnimatedImagePlayer(environment: env, clock: ManualClock())
        first.load(AnimatedImageSource(data: Data([1])))
        second.load(AnimatedImageSource(data: Data([2])))
        try await eventually { first.state == .playing && second.state == .playing && env.statistics.pendingOperations == 0 }
        XCTAssertEqual(env.statistics.bufferedBytes, 1_280)
        XCTAssertEqual(env.statistics.bufferedFrames, 2)
        first.reset()
        second.reset()
    }
}
