"""独立执行生产 Swift 错误映射，不启动 App、WebView 或 URLSession。"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / "nodeseek/AppRuntime/Web/NodeSeekDiscussionSubmitter.swift").read_text()
error_type = source[source.index("enum NodeSeekDiscussionSubmitError"):source.index("\nprotocol NodeSeekDiscussionSubmitting")]
start = source.index("    private static func throwIfFailed")
end = source.index("\n    }", start) + len("\n    }")
mapping = source[start:end].replace("private static", "static")
html_source = (root / "nodeseek/AppRuntime/Web/HTMLClient/HiddenWebViewHTMLClient.swift").read_text()
loading_error = html_source[html_source.index("enum HiddenWebViewHTMLClientError"):html_source.index("\nprivate enum WebViewCachePolicy")]
checks = """
for reason in ["submit_timeout", "network_error", "response_unreadable"] {
    do {
        try Mapping.throwIfFailed(["ok": false, "reason": reason])
        fatalError("应返回错误")
    } catch let error as NodeSeekDiscussionSubmitError {
        let expected = reason == "submit_timeout" ? "提交超时，请刷新确认是否成功。" : "操作结果未确认，请刷新查看。"
        precondition(error.localizedDescription == expected)
        precondition(error.isResultUnknown)
    }
}
try Mapping.throwIfFailed(["ok": true])
precondition(!NodeSeekDiscussionSubmitError.notLoggedIn.isResultUnknown)
precondition(HiddenWebViewHTMLClientError.timeout.localizedDescription == "加载超时，请重试。")
print("Swift 提交超时、结果未知、成功及加载超时映射通过")
"""
reaction_source = (root / "nodeseek/AppRuntime/Web/NodeSeekCommentSubmitter.swift").read_text()
facing_source = (root / "nodeseek/SharedCore/HTTP/UserFacingError.swift").read_text()

def block(text, marker, terminator="\n}\n"):
    start = text.index(marker)
    return text[start:text.index(terminator, start) + len(terminator)]

reaction_types = "\n".join([
    block(facing_source, "nonisolated enum UserFacingError"),
    block(reaction_source, "struct CommentUpvoteResponse"),
    block(reaction_source, "struct CommentUpvoteAutomationResponse"),
    block(reaction_source, "private struct ReactionSubmitterErrors").replace("private ", ""),
    block(reaction_source, "@MainActor\nprivate func submitReaction").replace("private func", "func"),
])
reaction_checks = """
struct Failure: Error { let message: String }
let errors = ReactionSubmitterErrors(
    invalidID: Failure(message: "invalid"),
    serverMessage: { Failure(message: $0) },
    httpStatus: { Failure(message: "status \\($0)") },
    fallbackMessage: "fallback"
)
func outcome(_ status: Int?, _ success: Bool?, _ message: String?, _ reason: String) async -> String {
    do {
        _ = try await submitReaction(targetID: "1", action: "add", referer: URL(string: "https://example.invalid")!, errors: errors) { _, _, _ in
            CommentUpvoteAutomationResponse(ok: false, statusCode: status, response: CommentUpvoteResponse(success: success, message: message), reason: reason)
        }
        return "success"
    } catch let error as Failure {
        return error.message
    } catch {
        return "unexpected"
    }
}
let cases: [(Int?, Bool?, String?, String, String)] = [
    (401, nil, nil, "server_error", "登录状态已失效，请重新登录。"),
    (403, nil, nil, "server_error", "访问被拒绝，请在网页中确认登录或验证状态。"),
    (429, nil, nil, "server_error", "操作过于频繁，请稍后再试。"),
    (502, nil, nil, "server_error", "操作结果未确认，请刷新查看。"),
    (404, nil, nil, "server_error", "status 404"),
    (403, false, "该评论创建于7天前", "server_error", "该评论创建于7天前"),
    (200, nil, nil, "invalid_response", "操作结果未确认，请刷新查看。"),
    (200, false, "已点过", "server_error", "已点过"),
    (nil, nil, nil, "submit_timeout", "提交超时，请刷新确认是否成功。"),
]
for (status, success, message, reason, expected) in cases {
    let actual = await outcome(status, success, message, reason)
    precondition(actual == expected, "status=\\(String(describing: status)) reason=\\(reason): \\(actual)")
}
print("Swift 互动状态码映射 \\(cases.count) 项通过")
"""

with tempfile.TemporaryDirectory() as directory:
    reaction_script = Path(directory) / "reaction.swift"
    reaction_script.write_text("import Foundation\n" + reaction_types + "\n" + reaction_checks)
    subprocess.run(["swift", str(reaction_script)], check=True)

with tempfile.TemporaryDirectory() as directory:
    script = Path(directory) / "checks.swift"
    script.write_text("import Foundation\n" + error_type + "\n" + loading_error + "\nenum Mapping {\n" + mapping + "\n}\n" + checks)
    subprocess.run(["swift", str(script)], check=True)
