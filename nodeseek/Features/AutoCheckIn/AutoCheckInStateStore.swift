//
//  AutoCheckInStateStore.swift
//  nodeseek
//

import Foundation

final class AutoCheckInStateStore {
    static let shared = AutoCheckInStateStore()

    private let userDefaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard, storageKey: String = "autoCheckIn.state") {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
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

    private func persist(_ state: AutoCheckInState) {
        guard let data = try? encoder.encode(state) else {
            AppLog.error(.autoCheckIn, "state persist failed: encode")
            return
        }
        userDefaults.set(data, forKey: storageKey)
    }
}
