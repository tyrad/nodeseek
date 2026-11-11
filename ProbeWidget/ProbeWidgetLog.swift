import OSLog

/// 小组件里的精简日志：共享的探针代码会调用 AppLog，但 App 的日志实现依赖调试配置，不带进扩展。
enum AppLogType: String {
    case service = "Service"
}

enum AppLog {
    nonisolated private static let logger = Logger(subsystem: "com.nodeseek.app.widget", category: "Probe")

    nonisolated static func info(_ type: AppLogType, _ message: @autoclosure () -> String) {
        let text = message()
        logger.info("[\(type.rawValue, privacy: .public)] \(text, privacy: .public)")
    }

    nonisolated static func error(_ type: AppLogType, _ message: @autoclosure () -> String) {
        let text = message()
        logger.error("[\(type.rawValue, privacy: .public)] \(text, privacy: .public)")
    }
}
