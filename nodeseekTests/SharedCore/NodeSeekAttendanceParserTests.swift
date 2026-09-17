//
//  NodeSeekAttendanceParserTests.swift
//  nodeseekTests
//

import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

struct NodeSeekAttendanceParserTests {
    @Test func boardNullRecordMeansNotCheckedIn() throws {
        let data = Data(#"{"list":[],"record":null,"order":null,"total":10}"#.utf8)

        let payload = try NodeSeekAttendanceParser.parseBoard(from: data).get()

        #expect(payload.isCheckedIn == false)
        #expect(payload.gain == nil)
        #expect(payload.order == nil)
        #expect(payload.topLevelKeys == ["list", "order", "record", "total"])
    }

    @Test func boardRecordObjectMeansCheckedIn() throws {
        let data = Data(#"{"list":[],"record":{"gain":5},"order":12,"total":10}"#.utf8)

        let payload = try NodeSeekAttendanceParser.parseBoard(from: data).get()

        #expect(payload.isCheckedIn)
        #expect(payload.gain == 5)
        #expect(payload.order == 12)
    }

    @Test func boardMissingRecordKeyIsInvalid() {
        let data = Data(#"{"list":[],"order":null,"total":10}"#.utf8)

        let result = NodeSeekAttendanceParser.parseBoard(from: data)

        #expect(result == .failure(.missingRecordKey))
    }

    @Test func boardDoesNotTreatLeaderboardAsSelf() throws {
        let data = Data(#"{"list":[{"member_id":1,"gain":15,"member_name":"other"}],"record":null,"order":null,"total":1}"#.utf8)

        let payload = try NodeSeekAttendanceParser.parseBoard(from: data).get()

        #expect(payload.isCheckedIn == false)
    }

    @Test func boardHTMLChallengeIsRejected() {
        let data = Data("<html>Just a moment... /cdn-cgi/challenge-platform/</html>".utf8)

        #expect(NodeSeekAttendanceParser.parseBoard(from: data) == .failure(.challenge))
    }

    @Test func submitSuccessUsesBooleanTrue() throws {
        let data = Data(#"{"success":true,"message":"签到成功","current":42}"#.utf8)

        let payload = try NodeSeekAttendanceParser.parseSubmit(from: data).get()

        #expect(payload.success)
        #expect(payload.message == "签到成功")
        #expect(payload.current == 42)
    }

    @Test func submitStringTrueIsNotSuccess() throws {
        let data = Data(#"{"success":"true","message":"签到成功"}"#.utf8)

        let payload = try NodeSeekAttendanceParser.parseSubmit(from: data).get()

        #expect(payload.success == false)
        #expect(payload.message == "签到成功")
    }

    @Test func submitNSNumberSuccessFromWebKitBridge() throws {
        let payload = try NodeSeekAttendanceParser.parseSubmit(from: [
            "success": NSNumber(value: true),
            "message": "ok",
            "current": NSNumber(value: 8)
        ]).get()

        #expect(payload.success)
        #expect(payload.current == 8)
    }

    @Test func boardNSNullRecordFromWebKitBridge() throws {
        let payload = try NodeSeekAttendanceParser.parseBoard(from: [
            "list": [],
            "record": NSNull(),
            "order": NSNull(),
            "total": NSNumber(value: 10)
        ]).get()

        #expect(payload.isCheckedIn == false)
        #expect(payload.topLevelKeys.contains("record"))
    }
}
