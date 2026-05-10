//
//  DetailImageCallbackQueue.swift
//  nodeseek
//
//  Created by Codex on 2026/5/10.
//

enum DetailImageCallbackQueue {
    static func enqueue<Key: Hashable, Callback>(
        _ callback: Callback,
        for key: Key,
        in callbacksByKey: inout [Key: [Callback]]
    ) -> Bool {
        if var callbacks = callbacksByKey[key] {
            callbacks.append(callback)
            callbacksByKey[key] = callbacks
            return false
        }

        callbacksByKey[key] = [callback]
        return true
    }

    static func take<Key: Hashable, Callback>(
        for key: Key,
        from callbacksByKey: inout [Key: [Callback]]
    ) -> [Callback] {
        callbacksByKey.removeValue(forKey: key) ?? []
    }
}
