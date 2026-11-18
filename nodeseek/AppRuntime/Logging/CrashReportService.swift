import Foundation
import FirebaseCore
import FirebaseCrashlytics

/// SDK 自动保存崩溃并在后续启动时上传，不转发普通文件日志。
@MainActor
enum CrashReportService {
    static func configure() {
        // 单测宿主不启动采集，避免把测试故障混入正式报告。
        guard NSClassFromString("XCTestCase") == nil else { return }
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        _ = Crashlytics.crashlytics()
    }
}
