import XCTest
@testable import FramePlay

@MainActor
final class PlayerTests: XCTestCase {
    func testIndividualDurationsAndFinitePlaysFinishOnLastFrame() async throws {
        let decoder = FakeDecoder(plays: 2)
        let env = environment(decoder)
        let clock = ManualClock()
        let player = AnimatedImagePlayer(environment: env, clock: clock)
        player.load(AnimatedImageSource(data: Data([1])))
        try await eventually { env.statistics.bufferedFrames == 3 }
        XCTAssertEqual(player.currentFrameIndex, 0)
        for play in 0 ..< 2 {
            clock.advance(0.101)
            XCTAssertEqual(player.currentFrameIndex, 1)
            clock.advance(0.201)
            XCTAssertEqual(player.currentFrameIndex, 2)
            clock.advance(0.301)
            XCTAssertEqual(player.state, play == 0 ? .playing : .finished)
        }
        XCTAssertTrue(player.currentFrame === decoder.frames[2])
        XCTAssertFalse(clock.running)
    }

    func testPreserveTimingCanSkipAndFinishesWithLastFrame() async throws {
        let decoder = FakeDecoder(plays: 1)
        let env = environment(decoder)
        let clock = ManualClock()
        let player = AnimatedImagePlayer(environment: env, clock: clock)
        player.load(AnimatedImageSource(data: Data([1])), configuration: PlaybackConfiguration(frameDropPolicy: .preserveTiming))
        try await eventually { env.statistics.bufferedFrames == 3 }
        clock.advance(0.35)
        XCTAssertEqual(player.currentFrameIndex, 2)
        clock.advance(1)
        XCTAssertEqual(player.state, .finished)
        XCTAssertTrue(player.currentFrame === decoder.frames[2])
    }

    func testPauseResumeDoesNotCatchUpBackgroundTimeAndStopRestarts() async throws {
        let decoder = FakeDecoder()
        let env = environment(decoder)
        let clock = ManualClock()
        let player = AnimatedImagePlayer(environment: env, clock: clock)
        player.load(AnimatedImageSource(data: Data([1])))
        try await eventually { env.statistics.bufferedFrames == 3 }
        clock.advance(0.05)
        player.pause()
        clock.advance(10)
        XCTAssertEqual(player.currentFrameIndex, 0)
        player.play()
        clock.advance(0.02)
        XCTAssertEqual(player.currentFrameIndex, 0)
        clock.advance(0.04)
        try await eventually { player.currentFrameIndex == 1 }
        player.stop()
        XCTAssertEqual(player.state, .ready)
        player.play()
        try await eventually { player.currentFrameIndex == 0 }
        XCTAssertEqual(player.state, .playing)
    }

    func testSameAssetSharesDecoderButPlaybackIsIndependent() async throws {
        let probe = DecodeProbe()
        let env = environment(FakeDecoder(probe: probe))
        let firstClock = ManualClock(), secondClock = ManualClock()
        let first = AnimatedImagePlayer(environment: env, clock: firstClock)
        let second = AnimatedImagePlayer(environment: env, clock: secondClock)
        let source = AnimatedImageSource(data: Data([1]))
        first.load(source)
        second.load(source)
        try await eventually { env.statistics.bufferedFrames == 3 && second.currentFrameIndex == 0 }
        XCTAssertEqual(env.statistics.resourceCount, 1)
        XCTAssertEqual(probe.snapshot.factories, 1)
        XCTAssertEqual(probe.snapshot.counts, [0: 1, 1: 1, 2: 1])
        first.pause()
        secondClock.advance(0.11)
        XCTAssertEqual(first.currentFrameIndex, 0)
        XCTAssertEqual(second.currentFrameIndex, 1)
        first.reset()
        XCTAssertEqual(env.statistics.resourceCount, 1)
        second.reset()
        XCTAssertEqual(env.statistics.resourceCount, 0)
        XCTAssertEqual(env.statistics.bufferedBytes, 0)
    }

    func testResetClearsFrameAndCallbacksCanLoadNewSource() async throws {
        let firstDecoder = FakeDecoder(), secondDecoder = FakeDecoder(frames: [TestFixtures.frame(0.9), TestFixtures.frame(0.8), TestFixtures.frame(0.7)])
        let env = PlaybackEnvironment(decoderFactory: { data, _ in data.first == 1 ? firstDecoder : secondDecoder }, posterFactory: { _, _ in nil })
        let clock = ManualClock()
        let player = AnimatedImagePlayer(environment: env, clock: clock)
        var switched = false
        player.onFrame = { image in
            if image === firstDecoder.frames[0], !switched {
                switched = true
                player.load(AnimatedImageSource(data: Data([2])))
            }
        }
        player.load(AnimatedImageSource(data: Data([1])))
        try await eventually { player.currentFrame === secondDecoder.frames[0] }
        XCTAssertEqual(player.state, .playing)
        player.reset()
        XCTAssertNil(player.currentFrame)
        XCTAssertNil(player.metadata)
        XCTAssertEqual(player.state, .idle)
        XCTAssertFalse(clock.running)
    }

    func testPausingFromFrameCallbackDoesNotRestartClockOrPrefetch() async throws {
        let probe = DecodeProbe()
        let env = environment(FakeDecoder(probe: probe))
        let clock = ManualClock()
        let player = AnimatedImagePlayer(environment: env, clock: clock)
        player.onFrame = { image in if image != nil { player.pause() } }
        player.load(AnimatedImageSource(data: Data([1])))
        try await eventually { player.state == .paused }
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertFalse(clock.running)
        XCTAssertEqual(probe.snapshot.counts, [0: 1])
    }

    func testStaticImageDoesNotStartAnimationOrReportFailure() async throws {
        let clock = ManualClock()
        let player = AnimatedImagePlayer(environment: PlaybackEnvironment(), clock: clock)
        var failures = 0
        player.onFallback = { _ in failures += 1 }
        player.load(AnimatedImageSource(data: try TestFixtures.encoded(type: "public.png", delays: [0.1])))
        try await eventually { player.state == .staticImage }
        XCTAssertNotNil(player.currentFrame)
        XCTAssertFalse(clock.running)
        XCTAssertEqual(failures, 0)
    }

    func testDeinitializationReleasesResource() async throws {
        let env = environment(FakeDecoder())
        let clock = ManualClock()
        var player: AnimatedImagePlayer? = AnimatedImagePlayer(environment: env, clock: clock)
        weak var weakPlayer = player
        player?.load(AnimatedImageSource(data: Data([1])))
        try await eventually { player?.state == .playing }
        player = nil
        try await eventually { env.statistics.resourceCount == 0 }
        XCTAssertNil(weakPlayer)
        XCTAssertFalse(clock.running)
        weakPlayer = nil
    }

    func testPauseDuringMissingFrameDoesNotAdvanceUntilResume() async throws {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let decoder = FakeDecoder(blockAt: 1, gate: gate)
        let env = environment(decoder)
        let clock = ManualClock()
        let player = AnimatedImagePlayer(environment: env, clock: clock)
        player.load(AnimatedImageSource(data: Data([1])), configuration: PlaybackConfiguration(maximumBufferedFrames: 1))
        try await eventually { player.state == .playing }
        clock.advance(0.11)
        try await eventually { decoder.probe.snapshot.counts[1] == 1 }
        player.pause()
        gate.signal()
        try await eventually { env.statistics.pendingOperations == 0 }
        XCTAssertEqual(player.state, .paused)
        XCTAssertEqual(player.currentFrameIndex, 0)
        gate.signal()
        player.play()
        try await eventually { player.currentFrameIndex == 1 }
        XCTAssertEqual(player.state, .playing)
    }
}
