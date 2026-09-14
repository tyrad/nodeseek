import Testing
@testable import nodeseek

struct PushNotificationForegroundEchoTests {
    @Test func detectsEchoFlag() {
        #expect(PushNotificationForegroundEcho.isEcho(["ns_local_echo": 1]))
        #expect(PushNotificationForegroundEcho.isEcho(["ns_local_echo": true]))
        #expect(!PushNotificationForegroundEcho.isEcho(["type": "reply"]))
    }
}
