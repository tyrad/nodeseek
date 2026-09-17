//
//  AutoCheckInStoreTests.swift
//  nodeseekTests
//

import Foundation
import Testing
@testable import nodeseek

@MainActor
@Suite(.serialized)
struct AutoCheckInStoreTests {
    @Test func settingsDefaultToDisabledChickenLegModeAndSummary() throws {
        let suiteName = "auto-check-in-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AutoCheckInSettingsStore(userDefaults: defaults, storageKey: "settings")

        #expect(store.settings == AutoCheckInSettings(isEnabled: false, mode: .fixedChickenLeg))
        #expect(store.summary == "未开启")
    }

    @Test func modeQueryValuesMatchNodeSeekAttendanceSemantics() {
        #expect(String(describing: AutoCheckInMode.fixedChickenLeg.randomQueryValue) == "false")
        #expect(String(describing: AutoCheckInMode.random.randomQueryValue) == "true")
    }

    @Test func settingsPersistEnabledRandomModeAndPostNotification() throws {
        let suiteName = "auto-check-in-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AutoCheckInSettingsStore(userDefaults: defaults, storageKey: "settings")
        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: AutoCheckInSettingsStore.didChangeNotification,
            object: store,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.setEnabled(true)
        store.setMode(.random)

        let reloaded = AutoCheckInSettingsStore(userDefaults: defaults, storageKey: "settings")
        #expect(reloaded.settings == AutoCheckInSettings(isEnabled: true, mode: .random))
        #expect(reloaded.summary == "已开启 · 试试手气")
        #expect(notificationCount == 2)
    }

    @Test func settingsSkipNotificationWhenValueIsUnchanged() throws {
        let suiteName = "auto-check-in-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AutoCheckInSettingsStore(userDefaults: defaults, storageKey: "settings")
        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: AutoCheckInSettingsStore.didChangeNotification,
            object: store,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.setEnabled(false)
        store.setMode(.fixedChickenLeg)

        #expect(notificationCount == 0)

        store.setEnabled(true)
        store.setMode(.random)

        #expect(notificationCount == 2)

        store.setEnabled(true)
        store.setMode(.random)

        #expect(notificationCount == 2)
    }

    @Test func stateStoreRecognizesCompletedLocalDay() throws {
        let suiteName = "auto-check-in-state-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AutoCheckInStateStore(userDefaults: defaults, storageKey: "state")
        let calendar = Calendar(identifier: .gregorian)
        let date = Date(timeIntervalSince1970: 1_777_777_777)
        let day = AutoCheckInDayIdentifier.string(
            for: date,
            calendar: calendar,
            timeZone: AutoCheckInDayIdentifier.shanghaiTimeZone
        )

        #expect(store.isCompleted(on: day) == false)

        store.markCompleted(dayIdentifier: day, at: date)

        #expect(store.isCompleted(on: day) == true)
        #expect(store.state.lastSuccessfulAt == date)
    }

    @Test func dayIdentifierUsesShanghaiCalendarDate() {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = utcCalendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 20))!

        let shanghai = AutoCheckInDayIdentifier.string(
            for: date,
            calendar: Calendar(identifier: .gregorian),
            timeZone: AutoCheckInDayIdentifier.shanghaiTimeZone
        )
        let utc = AutoCheckInDayIdentifier.string(
            for: date,
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(shanghai == "2026-09-17")
        #expect(utc == "2026-09-16")
    }

    @Test func appLogIncludesAutoCheckInCategory() throws {
        #expect(AppLogType.allCases.contains(.autoCheckIn))
        #expect(AppLogType.autoCheckIn.rawValue == "AutoCheckIn")
    }
}
