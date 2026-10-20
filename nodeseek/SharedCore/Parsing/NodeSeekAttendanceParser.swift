//
//  NodeSeekAttendanceParser.swift
//  nodeseek
//

import Foundation

enum NodeSeekAttendanceParser {
    struct BoardPayload: Equatable, Sendable {
        let isCheckedIn: Bool
        let gain: Int?
        let order: Int?
        let topLevelKeys: [String]
    }

    struct SubmitPayload: Equatable, Sendable {
        let success: Bool
        let message: String?
        let current: Int?
    }

    enum ParseError: Error, Equatable, Sendable {
        case empty
        case invalidJSON
        case missingRecordKey
        case invalidBoardPayload
        case challenge
        case htmlPayload
    }

    static func parseBoard(from data: Data) -> Result<BoardPayload, ParseError> {
        if data.isEmpty {
            return .failure(.empty)
        }
        if HTMLPayloadInspector.containsCloudflareChallenge(data) {
            return .failure(.challenge)
        }
        if HTMLPayloadInspector.looksLikeHTMLDocument(data) {
            return .failure(.htmlPayload)
        }
        guard let object = jsonObject(from: data) else {
            return .failure(.invalidJSON)
        }
        return parseBoard(from: object)
    }

    static func parseBoard(from object: [String: Any]) -> Result<BoardPayload, ParseError> {
        let keys = object.keys.sorted()
        guard object.keys.contains("record") else {
            return .failure(.missingRecordKey)
        }

        let recordValue = object["record"]
        if isNull(recordValue) {
            return .success(BoardPayload(isCheckedIn: false, gain: nil, order: intValue(object["order"]), topLevelKeys: keys))
        }
        guard let record = recordValue as? [String: Any] else {
            return .failure(.invalidBoardPayload)
        }
        return .success(BoardPayload(
            isCheckedIn: true,
            gain: intValue(record["gain"]),
            order: intValue(object["order"]),
            topLevelKeys: keys
        ))
    }

    static func parseSubmit(from data: Data) -> Result<SubmitPayload, ParseError> {
        if data.isEmpty {
            return .failure(.empty)
        }
        if HTMLPayloadInspector.containsCloudflareChallenge(data) {
            return .failure(.challenge)
        }
        if HTMLPayloadInspector.looksLikeHTMLDocument(data) {
            return .failure(.htmlPayload)
        }
        guard let object = jsonObject(from: data) else {
            return .failure(.invalidJSON)
        }
        return parseSubmit(from: object)
    }

    static func parseSubmit(from object: [String: Any]) -> Result<SubmitPayload, ParseError> {
        .success(SubmitPayload(
            success: boolValue(object["success"]) == true,
            message: stringValue(object["message"]) ?? stringValue(object["msg"]) ?? stringValue(object["error"]),
            current: intValue(object["current"])
        ))
    }

    private static func jsonObject(from data: Data) -> [String: Any]? {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let object = json as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func isNull(_ value: Any?) -> Bool {
        value == nil || value is NSNull
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
