import CoreGraphics
import Foundation

internal struct StoreKey: Hashable, Sendable {
    let sourceID: UUID
    let pixelSize: Int
    let frameLimit: Int
    let byteLimit: Int
    let limits: DecodeLimits

    init(source: AnimatedImageSource, configuration: PlaybackConfiguration) {
        sourceID = source.id
        pixelSize = configuration.maximumPixelSize
        frameLimit = configuration.maximumBufferedFrames
        byteLimit = configuration.bufferBytes
        limits = configuration.limits
    }
}

@MainActor
internal final class FrameCache {
    private struct Key: Hashable { let store: StoreKey; let index: Int }
    private struct Entry { let image: CGImage; let bytes: Int; var access: UInt64 }
    private var entries: [Key: Entry] = [:]
    private var access: UInt64 = 0
    private(set) var bytes = 0
    let maximumBytes: Int

    init(maximumBytes: Int) { self.maximumBytes = max(1, maximumBytes) }
    var count: Int { entries.count }

    func image(store: StoreKey, index: Int) -> CGImage? {
        let key = Key(store: store, index: index)
        guard var entry = entries[key] else { return nil }
        access &+= 1
        entry.access = access
        entries[key] = entry
        return entry.image
    }

    func contains(store: StoreKey, index: Int) -> Bool { entries[Key(store: store, index: index)] != nil }

    func insert(_ image: CGImage, store: StoreKey, index: Int, frameLimit: Int, preferredIndexes: Set<Int>) throws {
        let cost = image.bytesPerRow * image.height
        guard frameLimit > 0, cost <= min(store.byteLimit, maximumBytes) else { throw PlaybackFailure.resourceLimitExceeded }
        let key = Key(store: store, index: index)
        remove(key)
        var local = entries.filter { $0.key.store == store }
        while local.count >= frameLimit || local.values.reduce(0, { $0 + $1.bytes }) + cost > store.byteLimit {
            let victim = local.min {
                let left = preferredIndexes.contains($0.key.index)
                let right = preferredIndexes.contains($1.key.index)
                return left == right ? $0.value.access < $1.value.access : !left
            }!.key
            remove(victim)
            local.removeValue(forKey: victim)
        }
        while bytes + cost > maximumBytes, let victim = entries.min(by: { $0.value.access < $1.value.access })?.key {
            remove(victim)
        }
        access &+= 1
        entries[key] = Entry(image: image, bytes: cost, access: access)
        bytes += cost
    }

    func trim(store: StoreKey, keeping indexes: Set<Int> = []) {
        for key in Array(entries.keys) where key.store == store && !indexes.contains(key.index) { remove(key) }
    }

    func removeAll() { entries.removeAll(); bytes = 0 }

    private func remove(_ key: Key) {
        if let entry = entries.removeValue(forKey: key) { bytes -= entry.bytes }
    }
}
