import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

struct UserFacingErrorTests {
    @Test func distinguishesNetworkErrorsAndCancellation() {
        #expect(UserFacingError.message(for: URLError(.notConnectedToInternet), fallback: "失败") == "网络未连接，请检查网络后重试。")
        #expect(UserFacingError.message(for: URLError(.timedOut), fallback: "失败") == "加载超时，请重试。")
        #expect(UserFacingError.isCancellation(URLError(.cancelled)))
        #expect(UserFacingError.isCancellation(CancellationError()))
        #expect(!UserFacingError.isCancellation(URLError(.timedOut)))
    }

    @Test func hidesUnknownInternalErrors() {
        let error = NSError(domain: "InternalImplementation", code: 7)
        #expect(UserFacingError.message(for: error, fallback: "通知加载失败") == "通知加载失败")
        #expect(UserFacingError.message(for: NodeSeekParserError.postDetailNotFound, fallback: "失败") == "无法读取帖子内容，请刷新后重试。")
    }
}
