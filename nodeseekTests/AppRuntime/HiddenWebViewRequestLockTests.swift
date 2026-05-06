//
//  HiddenWebViewRequestLockTests.swift
//  nodeseekTests
//

import Testing
@testable import nodeseek

@MainActor
@Suite(.serialized)
struct HiddenWebViewRequestLockTests {
    @Test func cancelledWaiterDoesNotAcquireLockOrBlockNextRequest() async throws {
        let lock = HiddenWebViewRequestLock()
        try await lock.acquire()

        let cancelledWaiter = Task { () -> String in
            do {
                try await lock.acquire()
                await lock.release()
                return "acquired"
            } catch is CancellationError {
                return "cancelled"
            } catch {
                return "other-error"
            }
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        cancelledWaiter.cancel()
        try await Task.sleep(nanoseconds: 20_000_000)

        await lock.release()

        #expect(await cancelledWaiter.value == "cancelled")

        try await lock.acquire()
        await lock.release()
    }
}
