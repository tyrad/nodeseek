//
//  XPathRules.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

enum XPathRules {
    static let accountUserCard = "//*[@id='nsk-right-panel-container']//*[contains(concat(' ', normalize-space(@class), ' '), ' user-card ')][1]"
    static let accountUsername = ".//a[contains(concat(' ', normalize-space(@class), ' '), ' Username ')]"
    static let accountProfileLink = ".//a[contains(@href, '/space/')][1]"
    static let accountAvatar = ".//img[contains(@class, 'avatar') or contains(@src, '/avatar/')]"
    static let accountStatLinks = ".//*[contains(concat(' ', normalize-space(@class), ' '), ' user-stat ')]//a[normalize-space()]"
    static let accountStatSpans = ".//*[contains(concat(' ', normalize-space(@class), ' '), ' user-stat ')]//span[normalize-space()]"

    static let postListItems = "//article[contains(@class, 'post-item')] | //li[contains(@class, 'post-list-item')]"
    static let postTitle = ".//*[contains(@class, 'post-title') and self::a] | .//*[contains(@class, 'post-title')]//a[contains(@href, '/post-') or contains(@href, '/post/')]"
    static let postPinned = ".//*[contains(@class, 'post-title')]//*[@title='置顶' or contains(concat(' ', normalize-space(@class), ' '), ' pined ') or (local-name()='use' and @*[local-name()='href' and .='#pin'])]"
    static let postLocked = ".//*[contains(@class, 'post-title')]//*[local-name()='use' and @*[local-name()='href' and .='#lock']]"
    static let postAvatar = ".//img[contains(@class, 'avatar') or contains(@src, '/avatar/')]"
    static let postAuthor = ".//*[contains(@class, 'post-author')] | .//*[contains(@class, 'info-author')]//a"
    static let postNode = ".//*[contains(@class, 'post-node')] | .//*[contains(@class, 'post-category')]"
    static let viewCount = ".//*[contains(@class, 'info-views')]//span"
    static let replyCount = ".//*[contains(@class, 'reply-count')] | .//*[contains(@class, 'info-comments-count')]//span[last()]"
    static let lastActive = ".//*[contains(@class, 'last-active')] | .//*[contains(@class, 'info-last-comment-time')]//time"
    static let fallbackPostLinks = "//a[contains(@href, '/post-') or contains(@href, '/post/')]"
    static let fallbackPostContainer = "./ancestor::*[self::article or self::li or self::tr or self::div][1]"
    static let fallbackAvatar = ".//img[contains(@src, '/avatar/')]"
    static let fallbackAuthor = ".//a[contains(@href, '/space/') or contains(@href, '/user/')]"
    static let fallbackNode = ".//a[contains(@href, '/go/') or contains(@href, '/categories/')]"
    static let fallbackLastActive = ".//time"

    static let postDetailTitle = "//*[contains(@class, 'post-title')]//a[contains(@class, 'post-title-link')] | //*[contains(@class, 'post-title')]//h1"
    static let postDetailBodyItem = "//*[contains(@class, 'nsk-post')]//*[contains(@class, 'content-item')][1]"
    static let postDetailComments = "//ul[contains(@class, 'comments')]/li[contains(@class, 'content-item')]"
    static let contentAuthor = ".//*[contains(@class, 'author-name')]"
    static let contentCreatedAt = ".//*[contains(@class, 'date-created')]//time"
    static let contentCategory = ".//*[contains(@class, 'content-category')]//a"
    static let contentFloor = ".//*[contains(@class, 'floor-link')]"
    static let contentArticle = ".//article[contains(@class, 'post-content')]"
}
