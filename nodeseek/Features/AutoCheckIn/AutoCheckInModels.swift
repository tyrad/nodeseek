//
//  AutoCheckInModels.swift
//  nodeseek
//

import Foundation

struct AutoCheckInSettings: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var mode: AutoCheckInMode

    static let `default` = AutoCheckInSettings(isEnabled: false, mode: .fixedChickenLeg)
}

enum AutoCheckInMode: String, Codable, CaseIterable, Sendable {
    case fixedChickenLeg
    case random

    var displayName: String {
        switch self {
        case .fixedChickenLeg:
            return "鸡腿 x 5"
        case .random:
            return "试试手气"
        }
    }

    var randomQueryValue: String {
        switch self {
        case .fixedChickenLeg:
            return "false"
        case .random:
            return "true"
        }
    }
}

enum AutoCheckInTrigger: String, Sendable {
    case postListAllFirstPage
}

struct AutoCheckInState: Codable, Equatable, Sendable {
    var completedDayIdentifier: String?
    var lastSuccessfulAt: Date?

    static let empty = AutoCheckInState(completedDayIdentifier: nil, lastSuccessfulAt: nil)
}

enum AutoCheckInDayIdentifier {
    static func current(calendar: Calendar = .current, timeZone: TimeZone = .current) -> String {
        string(for: Date(), calendar: calendar, timeZone: timeZone)
    }

    static func string(for date: Date, calendar: Calendar, timeZone: TimeZone) -> String {
        var calendar = calendar
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

struct AutoCheckInBoardState: Equatable, Sendable {
    let ok: Bool
    let isLoggedIn: Bool
    let isCheckedIn: Bool
    let message: String?
    let detectionSource: String
    let reason: String
    let statusCode: Int?
    let responseKeys: [String]
}

struct AutoCheckInSubmitResult: Equatable, Sendable {
    let ok: Bool
    let statusCode: Int?
    let success: Bool?
    let message: String?
    let current: Int?
    let reason: String
}

enum AutoCheckInRunOutcome: Equatable, Sendable {
    case skipped(String)
    case alreadyCheckedIn
    case submitted(message: String?)
    case failed(String)
}
