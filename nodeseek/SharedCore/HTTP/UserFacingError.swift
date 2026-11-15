import Foundation

nonisolated enum UserFacingError {
    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    /// 写操作收到非 2xx 时的提示。401/403/429 是明确失败；5xx 时服务器可能已执行，按结果未确认处理。
    static func submissionHTTPStatusMessage(_ statusCode: Int) -> String? {
        switch statusCode {
        case 401:
            return "登录状态已失效，请重新登录。"
        case 403:
            return "访问被拒绝，请在网页中确认登录或验证状态。"
        case 429:
            return "操作过于频繁，请稍后再试。"
        case 500..<600:
            return "操作结果未确认，请刷新查看。"
        default:
            return nil
        }
    }

    static func message(for error: Error, fallback: String) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet:
                return "网络未连接，请检查网络后重试。"
            case .timedOut:
                return "加载超时，请重试。"
            default:
                return fallback
            }
        }
        if let description = (error as? LocalizedError)?.errorDescription,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return description
        }
        return fallback
    }
}
