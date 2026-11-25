//
//  AutoCheckInStateStore.swift
//  nodeseek
//

import Foundation

final class AutoCheckInStateStore {
    static let shared = AutoCheckInStateStore()

    private let userDefaults: UserDefaults
    private let storageKey: String
    private let byUIDStorageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "autoCheckIn.state",
        byUIDStorageKey: String? = nil
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.byUIDStorageKey = byUIDStorageKey ?? "\(storageKey).byUID"
    }

    var state: AutoCheckInState {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? decoder.decode(AutoCheckInState.self, from: data) else {
            return .empty
        }
        return decoded
    }

    func isCompleted(on dayIdentifier: String) -> Bool {
        state.completedDayIdentifier == dayIdentifier
    }

    func markCompleted(dayIdentifier: String, at date: Date) {
        persist(AutoCheckInState(completedDayIdentifier: dayIdentifier, lastSuccessfulAt: date))
    }

    func state(forUID uid: Int?) -> AutoCheckInState {
        guard let uid else { return state }
        return loadStatesByUID()[String(uid)] ?? .empty
    }

    func isCompleted(forUID uid: Int?, on dayIdentifier: String) -> Bool {
        state(forUID: uid).completedDayIdentifier == dayIdentifier
    }

    func markCompleted(forUID uid: Int?, dayIdentifier: String, at date: Date) {
        let next = AutoCheckInState(completedDayIdentifier: dayIdentifier, lastSuccessfulAt: date)
        guard let uid else {
            persist(next)
            return
        }
        var map = loadStatesByUID()
        map[String(uid)] = next
        persistStatesByUID(map)
    }

    private func loadStatesByUID() -> [String: AutoCheckInState] {
        guard let data = userDefaults.data(forKey: byUIDStorageKey),
              let decoded = try? decoder.decode([String: AutoCheckInState].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func persistStatesByUID(_ states: [String: AutoCheckInState]) {
        guard let data = try? encoder.encode(states) else {
            AppLog.error(.autoCheckIn, "state by UID persist failed: encode")
            return
        }
        userDefaults.set(data, forKey: byUIDStorageKey)
    }

    private func persist(_ state: AutoCheckInState) {
        guard let data = try? encoder.encode(state) else {
            AppLog.error(.autoCheckIn, "state persist failed: encode")
            return
        }
        userDefaults.set(data, forKey: storageKey)
    }
}
