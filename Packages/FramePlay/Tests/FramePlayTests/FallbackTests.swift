import XCTest
@testable import FramePlay

@MainActor
final class FallbackTests: XCTestCase {
    func testInvalidDataUsesSuppliedStaticImageAndReportsOnce() async throws {
        let env = PlaybackEnvironment()
        let clock = ManualClock()
        let player = AnimatedImagePlayer(environment: env, clock: clock)
        let fallback = TestFixtures.frame()
        var failures: [PlaybackFailure] = []
        player.onFallback = { failures.append($0) }
        player.load(AnimatedImageSource(data: Data([1])), fallbackImage: fallback)
        try await eventually { player.state == .staticFallback(.invalidImageData) }
        XCTAssertTrue(player.currentFrame === fallback)
        XCTAssertFalse(clock.running)
        player.play()
        clock.advance(10)
        XCTAssertEqual(failures, [.invalidImageData])
        XCTAssertEqual(env.statistics.resourceCount, 0)
    }

    func testNoStaticImageLeavesNilAndDecoderInitializationCanRecoverPoster() async throws {
        let player = AnimatedImagePlayer(environment: PlaybackEnvironment(), clock: ManualClock())
        player.load(AnimatedImageSource(data: Data([1])))
        try await eventually { player.state == .staticFallback(.invalidImageData) }
        XCTAssertNil(player.currentFrame)

        let poster = TestFixtures.frame(0.3), supplied = TestFixtures.frame(0.9)
        let env = PlaybackEnvironment(decoderFactory: { _, _ in throw PlaybackFailure.invalidMetadata }, posterFactory: { _, _ in poster })
        let recoverable = AnimatedImagePlayer(environment: env, clock: ManualClock())
        recoverable.load(AnimatedImageSource(data: Data([2])), fallbackImage: supplied)
        try await eventually { recoverable.state == .staticFallback(.invalidMetadata) }
        XCTAssertTrue(recoverable.currentFrame === poster)
    }

    func testFirstFrameFailureUsesSuppliedImage() async throws {
        let decoder = FakeDecoder(failAt: [0])
        let clock = ManualClock()
        let player = AnimatedImagePlayer(environment: environment(decoder), clock: clock)
        let supplied = TestFixtures.frame(0.8)
        player.load(AnimatedImageSource(data: Data([1])), fallbackImage: supplied)
        try await eventually { player.state == .staticFallback(.frameDecodingFailed(index: 0)) }
        XCTAssertTrue(player.currentFrame === supplied)
        XCTAssertFalse(clock.running)
        XCTAssertEqual(decoder.probe.snapshot.counts, [0: 1])
    }

    func testMidPlaybackFailureHoldsLastSuccessfulFrameAndCancelsPrefetch() async throws {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let decoder = FakeDecoder(failAt: [1], blockAt: 1, gate: gate)
        let env = environment(decoder)
        let clock = ManualClock()
        let player = AnimatedImagePlayer(environment: env, clock: clock)
        var failures = 0
        player.onFallback = { _ in failures += 1 }
        player.load(AnimatedImageSource(data: Data([1])), configuration: PlaybackConfiguration(maximumBufferedFrames: 1))
        try await eventually { player.state == .playing }
        clock.advance(0.11)
        gate.signal()
        try await eventually { player.state == .staticFallback(.frameDecodingFailed(index: 1)) }
        XCTAssertTrue(player.currentFrame === decoder.frames[0])
        XCTAssertEqual(failures, 1)
        XCTAssertFalse(clock.running)
        XCTAssertEqual(env.statistics.bufferedFrames, 0)
        XCTAssertEqual(env.statistics.resourceCount, 0)
    }

    func testTemporaryBufferMissWaitsAndRecoversWithoutFallback() async throws {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let decoder = FakeDecoder(blockAt: 1, gate: gate)
        let clock = ManualClock()
        let player = AnimatedImagePlayer(environment: environment(decoder), clock: clock)
        player.load(AnimatedImageSource(data: Data([1])), configuration: PlaybackConfiguration(maximumBufferedFrames: 1, bufferTimeout: 1))
        try await eventually { player.state == .playing }
        clock.advance(0.11)
        try await eventually { decoder.probe.snapshot.counts[1] == 1 }
        clock.advance(0.3)
        XCTAssertEqual(player.state, .playing)
        XCTAssertTrue(player.currentFrame === decoder.frames[0])
        gate.signal()
        try await eventually { player.currentFrameIndex == 1 }
        XCTAssertEqual(player.state, .playing)
    }

    func testContinuousMissTimesOutAndLateResultCannotReviveAnimation() async throws {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let decoder = FakeDecoder(blockAt: 1, gate: gate)
        let env = environment(decoder)
        let clock = ManualClock()
        let player = AnimatedImagePlayer(environment: env, clock: clock)
        player.load(AnimatedImageSource(data: Data([1])), configuration: PlaybackConfiguration(maximumBufferedFrames: 1, bufferTimeout: 0.5))
        try await eventually { player.state == .playing }
        clock.advance(0.11)
        try await eventually { decoder.probe.snapshot.counts[1] == 1 }
        clock.advance(0.51)
        XCTAssertEqual(player.state, .staticFallback(.bufferTimeout))
        gate.signal()
        try await eventually { env.statistics.pendingOperations == 0 }
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(player.state, .staticFallback(.bufferTimeout))
        XCTAssertTrue(player.currentFrame === decoder.frames[0])
        XCTAssertFalse(clock.running)
        XCTAssertEqual(env.statistics.bufferedBytes, 0)
    }

    func testInitializationTimeoutAndSourceReplacementIgnoreOldWork() async throws {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let old = FakeDecoder(), fresh = FakeDecoder(frames: [TestFixtures.frame(0.9), TestFixtures.frame(0.8), TestFixtures.frame(0.7)])
        let env = PlaybackEnvironment(decoderFactory: { data, _ in
            if data.first == 1 { _ = gate.wait(timeout: .now() + 5); return old }
            return fresh
        }, posterFactory: { _, _ in nil })
        let clock = ManualClock()
        let player = AnimatedImagePlayer(environment: env, clock: clock)
        player.load(AnimatedImageSource(data: Data([1])), configuration: PlaybackConfiguration(bufferTimeout: 0.5))
        clock.advance(0.6)
        XCTAssertEqual(player.state, .staticFallback(.bufferTimeout))
        player.load(AnimatedImageSource(data: Data([2])))
        try await eventually { player.currentFrame === fresh.frames[0] }
        gate.signal()
        try await eventually { env.statistics.pendingOperations == 0 }
        XCTAssertTrue(player.currentFrame === fresh.frames[0])
        XCTAssertEqual(player.state, .playing)
    }

    func testInvalidConfigurationAndTinyBudgetUseStaticFallback() async throws {
        let fallback = TestFixtures.frame()
        let clock = ManualClock()
        let env = environment(FakeDecoder())
        let player = AnimatedImagePlayer(environment: env, clock: clock)
        player.load(AnimatedImageSource(data: Data([1])), configuration: PlaybackConfiguration(maximumPixelSize: 0), fallbackImage: fallback)
        XCTAssertEqual(player.state, .staticFallback(.invalidConfiguration))
        XCTAssertTrue(player.currentFrame === fallback)
        player.load(AnimatedImageSource(data: Data([1])), configuration: PlaybackConfiguration(bufferBytes: 1), fallbackImage: fallback)
        try await eventually { player.state == .staticFallback(.resourceLimitExceeded) }
        XCTAssertTrue(player.currentFrame === fallback)
        XCTAssertFalse(clock.running)
        XCTAssertEqual(env.statistics.bufferedBytes, 0)
    }
}
