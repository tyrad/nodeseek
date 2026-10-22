import XCTest
@testable import FramePlay

/// 共享资源在不同位置暂停时，显示帧由播放器持有，不应挤占解码需求。
@MainActor
final class ReviewReproductionTests: XCTestCase {
    func testSharedPausedPositionsShouldNotForceEveryPlayerIntoFallback() async throws {
        let decoder = FakeDecoder(durations: Array(repeating: 0.1, count: 10))
        let env = environment(decoder)
        let source = AnimatedImageSource(data: Data([1]))
        var players: [AnimatedImagePlayer] = []
        var clocks: [ManualClock] = []
        defer { players.forEach { $0.reset() } }
        for position in 0 ..< 7 {
            let clock = ManualClock()
            clocks.append(clock)
            let player = AnimatedImagePlayer(environment: env, clock: clock)
            players.append(player)
            player.load(source)
            try await eventually { player.state == .playing && env.statistics.pendingOperations == 0 }
            for target in 1 ..< (position + 1) {
                clock.advance(0.101)
                try await eventually { player.currentFrameIndex == target || player.state != .playing }
                try await eventually { env.statistics.pendingOperations == 0 }
                if player.state != .playing { break }
            }
            if player.state == .playing { player.pause() }
        }
        try await eventually { env.statistics.pendingOperations == 0 }
        XCTAssertTrue(players.allSatisfy { $0.state == .paused }, "实际状态：\(players.map(\.state))")
        XCTAssertEqual(players.map(\.currentFrameIndex), (0 ..< 7).map { Optional($0) })
        XCTAssertTrue(clocks.allSatisfy { !$0.running })
        let pausedFrames = players.map(\.currentFrame)
        let decoded = decoder.probe.snapshot.counts
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(decoder.probe.snapshot.counts, decoded, "暂停后不应继续预取")
        players[6].play()
        clocks[6].advance(0.101)
        try await eventually { players[6].currentFrameIndex == 7 }
        XCTAssertTrue(players.prefix(6).allSatisfy { $0.state == .paused })
        for index in 0 ..< 6 { XCTAssertTrue(players[index].currentFrame === pausedFrames[index]) }
    }

    func testMoreSimultaneousRequestsThanCapacityAreDeliveredWithoutSharedFailure() async throws {
        let decoder = FakeDecoder(durations: Array(repeating: 0.1, count: 10))
        let env = environment(decoder)
        let source = AnimatedImageSource(data: Data([1]))
        let clocks = (0 ..< 7).map { _ in ManualClock() }
        let players = clocks.map { AnimatedImagePlayer(environment: env, clock: $0) }
        defer { players.forEach { $0.reset() } }
        for position in players.indices {
            let player = players[position]
            player.load(source, configuration: PlaybackConfiguration(bufferBytes: 256, maximumBufferedFrames: 1))
            try await eventually { player.state == .playing && env.statistics.pendingOperations == 0 }
            for target in 1 ..< (position + 1) {
                clocks[position].advance(0.101)
                try await eventually { player.currentFrameIndex == target }
            }
            player.pause()
        }
        for index in players.indices {
            players[index].play()
            clocks[index].advance(0.101)
        }
        try await eventually { players.indices.allSatisfy { players[$0].currentFrameIndex == $0 + 1 } }
        XCTAssertTrue(players.allSatisfy { $0.state == .playing })
        XCTAssertLessThanOrEqual(env.statistics.bufferedFrames, 1)
        players.forEach { $0.pause() }
        try await eventually { env.statistics.pendingOperations == 0 }
        let decoded = decoder.probe.snapshot.counts
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(decoder.probe.snapshot.counts, decoded, "容量不足时不能空转解码")
    }

    func testIndependentPlayersDoNotFailWhenSharedFrameLimitWouldBeExceeded() async throws {
        let decoder = FakeDecoder(durations: Array(repeating: 0.1, count: 10))
        let env = environment(decoder)
        var players: [AnimatedImagePlayer] = []
        defer { players.forEach { $0.reset() } }
        for position in 0 ..< 7 {
            let clock = ManualClock()
            let player = AnimatedImagePlayer(environment: env, clock: clock)
            players.append(player)
            player.load(AnimatedImageSource(data: Data([1])))
            try await eventually { player.state == .playing && env.statistics.pendingOperations == 0 }
            for _ in 0 ..< position {
                clock.advance(0.101)
                try await eventually { env.statistics.pendingOperations == 0 }
            }
            player.pause()
        }
        XCTAssertTrue(players.allSatisfy { $0.state == .paused })
        XCTAssertEqual(env.statistics.resourceCount, 7)
    }

    func testTemporaryGlobalBudgetCompetitionResumesAfterOtherResourceIsReleased() async throws {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let blocked = FakeDecoder(blockAt: 0, gate: gate)
        let ready = FakeDecoder()
        let env = PlaybackEnvironment(maximumBufferBytes: 256, decoderFactory: { data, _ in
            data.first == 1 ? blocked : ready
        }, posterFactory: { _, _ in nil })
        let first = AnimatedImagePlayer(environment: env, clock: ManualClock())
        let second = AnimatedImagePlayer(environment: env, clock: ManualClock())
        defer { first.reset(); second.reset() }
        first.load(AnimatedImageSource(data: Data([1])), autoplay: false)
        try await eventually { blocked.probe.snapshot.counts[0] == 1 }
        second.load(AnimatedImageSource(data: Data([2])), autoplay: false)
        try await eventually { second.metadata != nil }
        XCTAssertEqual(second.state, .loading, "暂时缺少预算应等待，而非永久回退")
        first.reset()
        try await eventually { second.state == .ready }
        XCTAssertTrue(second.currentFrame === ready.frames[0])
        XCTAssertLessThanOrEqual(env.statistics.bufferedBytes, 256)
        gate.signal()
        try await eventually { env.statistics.pendingOperations == 0 }
    }

    func testStaggeredWindowsReuseDecodedFramesWithinByteBudget() async throws {
        let decoder = FakeDecoder(durations: Array(repeating: 0.1, count: 25))
        let env = environment(decoder)
        let source = AnimatedImageSource(data: Data([1]))
        let clocks = (0 ..< 4).map { _ in ManualClock() }
        let players = clocks.map { AnimatedImagePlayer(environment: env, clock: $0) }
        defer { players.forEach { $0.reset() } }
        for index in players.indices {
            players[index].load(source, configuration: PlaybackConfiguration(bufferBytes: 6_144))
            try await eventually { players[index].state == .playing && env.statistics.pendingOperations == 0 }
            for target in 1 ..< (index * 3 + 1) {
                clocks[index].advance(0.101)
                try await eventually { players[index].currentFrameIndex == target && env.statistics.pendingOperations == 0 }
            }
            players[index].pause()
        }
        players.forEach { $0.play() }
        try await eventually { env.statistics.bufferedFrames == 15 && env.statistics.pendingOperations == 0 }
        XCTAssertEqual(env.statistics.bufferedFrames, 15, "合并四个错开的六帧窗口")
        let before = decoder.probe.snapshot.counts.values.reduce(0, +)
        for step in 1 ... 8 {
            clocks.forEach { $0.advance(0.101) }
            try await eventually {
                players.indices.allSatisfy { players[$0].currentFrameIndex == $0 * 3 + step }
                    && env.statistics.bufferedFrames == 15
                    && env.statistics.pendingOperations == 0
            }
            XCTAssertLessThanOrEqual(env.statistics.bufferedBytes, 6_144)
        }
        let after = decoder.probe.snapshot.counts.values.reduce(0, +)
        XCTAssertEqual(after - before, 8, "每步只需准备一张新帧，其余播放位置复用已有帧")
    }

    func testMovingAlignedWindowDuringDecodeDoesNotEvictItsNextFrame() async throws {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let decoder = FakeDecoder(durations: Array(repeating: 0.1, count: 10), blockAt: 4, gate: gate)
        let env = environment(decoder)
        let source = AnimatedImageSource(data: Data([1]))
        let configuration = PlaybackConfiguration(maximumBufferedFrames: 3)
        let key = StoreKey(source: source, configuration: configuration)
        let clocks = [ManualClock(), ManualClock()]
        let players = clocks.map { AnimatedImagePlayer(environment: env, clock: $0) }
        defer { players.forEach { $0.reset() } }
        for player in players { player.load(source, configuration: configuration) }
        try await eventually { env.cache.contains(store: key, index: 3) && env.statistics.pendingOperations == 0 }
        clocks[0].advance(0.101)
        try await eventually { decoder.probe.snapshot.counts[4] == 1 }
        clocks[1].advance(0.101)
        XCTAssertTrue(players.allSatisfy { $0.currentFrameIndex == 1 })
        gate.signal()
        try await eventually {
            env.cache.contains(store: key, index: 2) && env.cache.contains(store: key, index: 4)
                && env.statistics.pendingOperations == 0
        }
        XCTAssertEqual(decoder.probe.snapshot.counts[2], 1, "交接新帧前应移除过期缓存，保留即将显示的帧")
    }
}
