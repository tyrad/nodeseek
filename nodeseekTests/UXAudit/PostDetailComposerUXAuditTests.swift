import XCTest
@testable import nodeseek

/// UX 审计（详情页回复编辑器 + 引用内容构建）的 RED 测试：当前实现下应当失败。
@MainActor
final class PostDetailComposerUXAuditTests: XCTestCase {
    // MARK: - U21

    // 期望：引用多行评论时保留换行，每行都是独立的 "> " 引用行。
    func test_U21_quotePreservesLineBreaks() {
        let comment = makeComment(id: "1", floor: 3, html: "<p>line 1<br>line 2<br>line 3</p>", markdown: "line 1\nline 2\nline 3")

        let content = CommentComposerContentBuilder.content(
            text: "",
            mode: .quote([comment]),
            postURL: URL(string: "https://www.nodeseek.com/post-1-1")!
        )

        let lines = content.components(separatedBy: "\n")
        let line1 = lines.firstIndex { $0.contains("line 1") }
        let line2 = lines.firstIndex { $0.contains("line 2") }
        let line2IsQuoted = line2.map { lines[$0].hasPrefix(">") } ?? false
        XCTAssertTrue(
            line1 != nil && line2 != nil && line1 != line2 && line2IsQuoted,
            "U21: 多行评论被压成一行引用：\(content.debugDescription)"
        )
    }

    // MARK: - U22

    // 期望：引用只有图片/表情的评论时，引用块里带上原文（图片 Markdown、表情代码），和网页一致，而不是只有标题行。
    func test_U22_quoteOfImageOnlyCommentCarriesSourceMarkdown() {
        let imageMarkdown = "![image](https://cdn.nodeimage.com/i/FBICDKhbCSRbkZ5Kx5qyiyit927K3vCg.webp)"
        let imageComment = makeComment(
            id: "1",
            floor: 1,
            html: #"<p><img src="https://cdn.nodeimage.com/i/FBICDKhbCSRbkZ5Kx5qyiyit927K3vCg.webp" alt="image"></p>"#,
            markdown: imageMarkdown
        )
        let stickerComment = makeComment(
            id: "2",
            floor: 2,
            html: #"<p><img class="sticker" src="/static/image/sticker/xhj/001.png" loading="lazy" alt="xhj001"></p>"#,
            markdown: ":xhj001:"
        )
        let postURL = URL(string: "https://www.nodeseek.com/post-1-1")!

        let imageQuote = CommentComposerContentBuilder.content(text: "", mode: .quote([imageComment]), postURL: postURL)
        let stickerQuote = CommentComposerContentBuilder.content(text: "", mode: .quote([stickerComment]), postURL: postURL)

        XCTAssertEqual(imageQuote.components(separatedBy: "\n").last, "> \(imageMarkdown)", "U22: 图片评论的引用块没有带上原文：\(imageQuote.debugDescription)")
        XCTAssertEqual(stickerQuote.components(separatedBy: "\n").last, "> :xhj001:", "U22: 表情评论的引用块没有带上原文：\(stickerQuote.debugDescription)")
    }

    // MARK: - Helpers

    private func makeComment(id: String, floor: Int, html: String, markdown: String? = nil, isOwnComment: Bool = false) -> Comment {
        Comment(
            id: id,
            anchorID: "\(floor)",
            authorName: "user\(floor)",
            avatarURL: nil,
            floorText: "#\(floor)",
            createdAtText: "1min ago",
            createdAtTitleText: "2026-11-18 10:00:00",
            contentHTML: html,
            isOwnComment: isOwnComment,
            markdown: markdown
        )
    }
}
