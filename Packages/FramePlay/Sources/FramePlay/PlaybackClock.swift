import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
internal protocol PlaybackClock: AnyObject, Sendable {
    var now: TimeInterval { get }
    var onTick: (@MainActor (TimeInterval) -> Void)? { get set }
    func start()
    func stop()
}

@MainActor
internal final class SystemPlaybackClock: NSObject, PlaybackClock {
    var onTick: (@MainActor (TimeInterval) -> Void)?
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    #if canImport(UIKit)
    private final class Proxy: NSObject {
        weak var owner: SystemPlaybackClock?
        @MainActor @objc func tick(_ link: CADisplayLink) {
            // 所有者已释放时由下一次主线程回调清理，避免跨隔离域访问 CADisplayLink。
            guard let owner else { link.invalidate(); return }
            owner.fire()
        }
    }
    private var link: CADisplayLink?

    func start() {
        guard link == nil else { return }
        let proxy = Proxy()
        proxy.owner = self
        let link = CADisplayLink(target: proxy, selector: #selector(Proxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() { link?.invalidate(); link = nil }
    #else
    private var timer: DispatchSourceTimer?

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1 / 60)
        timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.fire() } }
        self.timer = timer
        timer.resume()
    }

    func stop() { timer?.cancel(); timer = nil }
    deinit { timer?.cancel() }
    #endif

    private func fire() { onTick?(now) }
}
