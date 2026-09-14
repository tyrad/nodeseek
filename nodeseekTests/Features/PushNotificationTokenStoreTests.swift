import Foundation
import Testing
@testable import nodeseek

struct PushNotificationTokenStoreTests {
    @Test func hexStringLowercasesEachByte() {
        let data = Data([0x0A, 0xFF, 0x00, 0x10])
        #expect(PushNotificationTokenStore.hexString(from: data) == "0aff0010")
    }

    @Test func updatePersistsTokenAndClearsError() {
        let defaults = UserDefaults(suiteName: "push-token-store-tests")!
        defaults.removePersistentDomain(forName: "push-token-store-tests")
        let store = PushNotificationTokenStore(defaults: defaults)
        store.updateRegistrationError(NSError(domain: "test", code: 1))
        store.update(deviceToken: Data([0xAB, 0xCD]))
        #expect(store.deviceTokenHex == "abcd")
        #expect(store.lastError == nil)
    }
}
