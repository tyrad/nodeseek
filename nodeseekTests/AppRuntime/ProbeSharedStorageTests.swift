import XCTest
@testable import nodeseek

/// 升级后探针配置从本机存储搬到 App Group，只搬一次，不覆盖已有数据。
final class ProbeSharedStorageTests: XCTestCase {
    private func makeDefaults(_ name: String) -> UserDefaults {
        let suite = "ProbeSharedStorageTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testMigratesProbeKeysOnce() {
        let legacy = makeDefaults("legacy"), group = makeDefaults("group")
        legacy.set(Data([1]), forKey: "probe.instances.v1")
        legacy.set(Data([2]), forKey: "probe.snapshot.v1.abc")
        legacy.set("keep", forKey: "other.setting")
        XCTAssertFalse(ProbeSharedStorage.hasMigrated(group))

        XCTAssertTrue(ProbeSharedStorage.migrate(from: legacy, to: group), "第一次搬，App 据此通知小组件刷新")
        XCTAssertEqual(group.data(forKey: "probe.instances.v1"), Data([1]))
        XCTAssertEqual(group.data(forKey: "probe.snapshot.v1.abc"), Data([2]))
        XCTAssertNil(group.object(forKey: "other.setting"), "只搬探针相关的键")
        XCTAssertTrue(ProbeSharedStorage.hasMigrated(group))
        XCTAssertEqual(legacy.data(forKey: "probe.instances.v1"), Data([1]), "旧数据保留")

        // 第二次不再搬，避免旧数据覆盖小组件或 App 后来写的新数据。
        legacy.set(Data([9]), forKey: "probe.instances.v1")
        XCTAssertFalse(ProbeSharedStorage.migrate(from: legacy, to: group), "之后启动不再触发刷新")
        XCTAssertEqual(group.data(forKey: "probe.instances.v1"), Data([1]))
    }

    func testDoesNotOverwriteExistingGroupData() {
        let legacy = makeDefaults("legacy"), group = makeDefaults("group")
        legacy.set(Data([1]), forKey: "probe.instances.v1")
        group.set(Data([7]), forKey: "probe.instances.v1")
        ProbeSharedStorage.migrate(from: legacy, to: group)
        XCTAssertEqual(group.data(forKey: "probe.instances.v1"), Data([7]))
    }
}
