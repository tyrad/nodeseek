//
//  AppUXAuditTests.swift
//  nodeseekTests
//
//  2026-11-18 体验测试问题（首页列表、搜索、我的、设置、通知、网页）的红灯测试。
//  每个测试对应 docs/plans/2026-11-18-ux-audit-tdd.md 里的一个编号，修复后应变绿，不改期望。
//

import XCTest
import UIKit
import WebKit
import AsyncDisplayKit
@testable import nodeseek

@MainActor
final class AppUXAuditTests: XCTestCase {

    // MARK: - U02 NodeImage 授权页反复点「API」按钮

    /// 期望：一次提取 API Key 最多点一次 #apiBtn；轮询只读取输入框，不在定时器里反复点按钮（每次点击失败都会弹红色提示）。
    func test_U02_nodeImageExtractionDoesNotClickAPIButtonInsidePollingTimer() async throws {
        let viewController = NodeImageAuthViewController(onAPIKey: { _ in })
        viewController.loadViewIfNeeded()
        let webView = try XCTUnwrap(uxChild(of: viewController, named: "webView") as WKWebView?)

        // 给定时器回调打标记，统计在定时器里发生的 API 按钮点击
        let html = """
        <html><head><script>
        window.__timerDepth = 0;
        window.__apiClicks = 0;
        window.__timerApiClicks = 0;
        const wrap = (original) => function(fn, ms) {
          return original.call(window, function() {
            window.__timerDepth += 1;
            try { fn(); } finally { window.__timerDepth -= 1; }
          }, ms);
        };
        window.setInterval = wrap(window.setInterval);
        window.setTimeout = wrap(window.setTimeout);
        </script></head><body>
        <button id="startAuthBtn" onclick="return false;">start</button>
        <button id="apiBtn" onclick="window.__apiClicks += 1; if (window.__timerDepth > 0) window.__timerApiClicks += 1;">api</button>
        <input id="apiKeyInput" value="">
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.nodeimage.com/")!)

        let clicked = await uxWaitUntil(timeout: 8) {
            ((try? await webView.evaluateJavaScript("window.__apiClicks || 0")) as? Int ?? 0) > 0
        }
        XCTAssertTrue(clicked, "前置条件：页面加载完成后应至少提取一次 API Key")
        try await Task.sleep(nanoseconds: 1_200_000_000)

        let totalClicks = (try? await webView.evaluateJavaScript("window.__apiClicks")) as? Int ?? -1
        let timerClicks = (try? await webView.evaluateJavaScript("window.__timerApiClicks")) as? Int ?? -1
        XCTAssertEqual(
            timerClicks, 0,
            "U02: 提取 API Key 的轮询定时器里点了 \(timerClicks) 次 #apiBtn（1.2 秒内共 \(totalClicks) 次），每次失败都会弹「加载API密钥失败」"
        )
    }

    /// 期望：未登录 NodeImage 时不点「API」；页面稍后变为已登录，只点一次「API」并拿到 API Key。
    func test_U02_nodeImageClicksAPIButtonOnceAfterSignInAndReturnsKey() async throws {
        var receivedKeys: [String] = []
        let viewController = NodeImageAuthViewController(onAPIKey: { receivedKeys.append($0) })
        viewController.loadViewIfNeeded()
        let webView = try XCTUnwrap(uxChild(of: viewController, named: "webView") as WKWebView?)

        // 模拟 NodeImage：未登录时用户区隐藏，点「API」失败；1.5 秒后完成登录。
        let html = """
        <html><body>
        <button id="startAuthBtn" onclick="return false;">start</button>
        <div id="userControls" style="display: none;">user</div>
        <button id="apiBtn" onclick="
          const signedIn = document.getElementById('userControls').style.display !== 'none';
          if (signedIn) { window.__signedInClicks = (window.__signedInClicks || 0) + 1; document.getElementById('apiKeyInput').value = 'ux-audit-api-key'; }
          else { window.__signedOutClicks = (window.__signedOutClicks || 0) + 1; }
        ">api</button>
        <input id="apiKeyInput" value="">
        <script>setTimeout(() => { document.getElementById('userControls').style.display = 'flex'; }, 1500);</script>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.nodeimage.com/")!)

        let received = await uxWaitUntil(timeout: 10) { receivedKeys.isEmpty == false }
        XCTAssertTrue(received, "U02: 登录后没有拿到 API Key")
        XCTAssertEqual(receivedKeys, ["ux-audit-api-key"])

        let signedOutClicks = (try? await webView.evaluateJavaScript("window.__signedOutClicks || 0")) as? Int ?? -1
        let signedInClicks = (try? await webView.evaluateJavaScript("window.__signedInClicks || 0")) as? Int ?? -1
        XCTAssertEqual(signedOutClicks, 0, "U02: 未登录时点了「API」，会弹「加载API密钥失败」")
        XCTAssertEqual(signedInClicks, 1, "U02: 登录后应只点一次「API」")
    }

    // MARK: - U03 每日签到网页一直转圈

    /// 期望：主框架内容已提交（didCommit）后停止转圈，不等所有子资源 didFinish。
    func test_U03_webPageStopsSpinnerOnceNavigationCommits() throws {
        let viewController = UXAuditWebViewController()
        viewController.loadViewIfNeeded()
        viewController.loadingIndicator.startAnimating()

        (viewController as WKNavigationDelegate).webView?(viewController.webView, didCommit: nil)

        XCTAssertFalse(
            viewController.loadingIndicator.isAnimating,
            "U03: 网页主框架已提交内容后转圈仍在继续，只有 didFinish 才停止，慢资源会让签到页一直白屏转圈"
        )
    }

    // MARK: - U07 首页相对时间不刷新

    /// 期望：列表模型保存最后活动的绝对时间（来自 <time datetime>），界面才能随时间重新计算相对时间。
    func test_U07_postSummaryKeepsAbsoluteLastActivityDate() throws {
        let posts = try KannaNodeSeekParser(baseURL: NodeSeekSite.baseURL).parsePostList(html: Self.postListHTML)
        let post = try XCTUnwrap(posts.first)
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-04-27T05:46:32Z"))

        let dates = Mirror(reflecting: post).children.compactMap { $0.value as? Date }
        XCTAssertTrue(
            dates.contains(expected),
            "U07: PostSummary 只有 lastActivityText=\(post.lastActivityText ?? "nil")，没有解析 <time datetime> 的绝对时间，相对时间无法刷新"
        )
    }

    // MARK: - U11 切换分类后发帖按钮仍隐藏

    /// 期望：滚动收起发帖按钮后切换分类，按钮重新出现。
    func test_U11_composeButtonReappearsAfterSwitchingCategory() throws {
        let viewController = PostListViewController(
            presenter: UXAuditPostListPresenter(),
            layout: .tabs,
            floatingPositionStore: UXAuditFloatingPositionStore(),
            searchEntrySettings: PostListSearchEntrySettings(
                userDefaults: UserDefaults(suiteName: "ux-audit-search-entry-\(UUID().uuidString)")!,
                storageKey: "shows-top-search-entry"
            ),
            autoCheckInRunner: { _, _ in }
        )
        let window = uxMakeWindow(root: viewController)
        defer { window.isHidden = true }
        viewController.renderCategories([.all, .daily, .tech], selected: .all)
        viewController.view.layoutIfNeeded()

        let composeButton = try XCTUnwrap(
            uxDescendants(of: viewController.view).compactMap { $0 as? UIButton }
                .first { $0.accessibilityIdentifier == "post-list-compose-button" }
        )
        let onListScroll = try XCTUnwrap(viewController.pageContainerViewController.onListScroll)

        // 模拟手指上推：第一次记录锚点，第二次位移超过阈值后收起
        let scrollView = UXAuditTrackingScrollView(frame: CGRect(x: 0, y: 0, width: 402, height: 700))
        scrollView.contentSize = CGSize(width: 402, height: 5000)
        scrollView.contentOffset = CGPoint(x: 0, y: 600)
        scrollView.fakePan.fakeTranslation = CGPoint(x: 0, y: 0)
        onListScroll(scrollView)
        scrollView.fakePan.fakeTranslation = CGPoint(x: 0, y: -80)
        onListScroll(scrollView)
        XCTAssertEqual(composeButton.alpha, 0, accuracy: 0.01, "前置条件：上推后发帖按钮应已收起")

        let other = try XCTUnwrap(
            uxDescendants(of: viewController.view).compactMap { $0 as? CategoryTabButton }.first { $0.category == .daily }
        )
        other.sendActions(for: .touchUpInside)

        XCTAssertEqual(
            composeButton.alpha, 1, accuracy: 0.01,
            "U11: 切换分类后发帖按钮仍保持隐藏（alpha=\(composeButton.alpha)），要在新分类里上滑才出现"
        )
        XCTAssertTrue(composeButton.isUserInteractionEnabled, "U11: 切换分类后发帖按钮仍不可点")
    }

    // MARK: - U12 「我的」发帖上限与个人主页不一致

    /// 期望：「我的」页与个人主页「今日进度」对同一指标（发帖）显示相同的 当前/上限。
    func test_U12_mePageAndProfileShowSamePostLimit() async throws {
        let context = try await makeLoggedInMePage()
        defer { context.window.isHidden = true }

        let todayText = try XCTUnwrap(context.todayLabelText, "前置条件：我的页应显示今日进度")
        let meFraction = try XCTUnwrap(Self.fraction(after: "发帖", in: todayText), "我的页文案：\(todayText)")

        let client = context.client
        let profile = try await client.loadProfile(uid: 31037)
        let progress = try await client.loadTodayProgress(uid: 31037)
        let card = UserProfileProgressCardView()
        card.configure(level: profile.levelProgress, today: progress)
        let postRow = try XCTUnwrap(
            uxDescendants(of: card).compactMap { $0 as? UIStackView }
                .first { ($0.arrangedSubviews.first as? UILabel)?.text == "发帖" }
        )
        let profileValue = try XCTUnwrap((postRow.arrangedSubviews.last as? UILabel)?.text)
        let profileFraction = profileValue.replacingOccurrences(of: " ", with: "")

        XCTAssertEqual(
            meFraction, profileFraction,
            "U12: 「我的」显示「\(todayText)」，个人主页今日进度显示 发帖 \(profileValue)，同一指标两个上限"
        )
    }

    // MARK: - U13 特别关注删除方向文案写反

    /// 期望：说明文字写「滑动删除」，不写具体方向，避免与手指方向理解冲突。
    func test_U13_specialFollowFooterSaysSwipeToDelete() {
        let defaults = UserDefaults(suiteName: "ux-audit-special-follow-\(UUID().uuidString)")!
        let viewController = SpecialFollowKeywordsViewController(store: SpecialFollowKeywordStore(userDefaults: defaults))
        viewController.loadViewIfNeeded()

        let footer = viewController.tableView(viewController.tableView, titleForFooterInSection: 0) ?? ""

        XCTAssertTrue(
            footer.contains("滑动删除") && !footer.contains("左滑") && !footer.contains("右滑"),
            "U13: 特别关注说明写的是「\(footer)」，应写「滑动删除」"
        )
    }

    // MARK: - U14 字号 +8 时首页元信息行被截断

    /// 期望：App 字号 +8 时，首页元信息行（作者 · 浏览 · 回复 · 时间）要么一行放得下，要么允许换行且行高够用，不截断时间。
    func test_U14_listMetadataNotTruncatedAtLargestAppTextSize() throws {
        let previousOffset = AppTextSizeSettings.shared.pointOffset
        AppTextSizeSettings.shared.setPointOffset(AppTextSizeSettings.maximumPointOffset)
        defer { AppTextSizeSettings.shared.setPointOffset(previousOffset) }

        let post = PostSummary(
            id: "703692",
            title: "【问】115非VIP账号海外上传速度如何",
            url: URL(string: "https://www.nodeseek.com/post-703692-1")!,
            authorName: "harunoyuki",
            nodeName: "日常",
            replyCount: 961,
            viewCount: 47545,
            lastActivityText: "1h 58min ago"
        )
        let item = PostListItem(post: post, isVisited: false)
        let context = PostSummaryLayout.Context(
            width: 402,
            pointOffset: AppTextSizeSettings.maximumPointOffset,
            userInterfaceStyle: .light,
            displayScale: 3,
            specialFollowRules: []
        )
        let layout = PostSummaryLayout.make(item: item, context: context)

        let singleLineWidth = layout.metadata.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).width
        let wrappedHeight = layout.metadata.boundingRect(
            with: CGSize(width: layout.metadataFrame.width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height
        let fitsOneLine = singleLineWidth <= layout.metadataFrame.width
        let wrapsWithoutClipping = PostListCellStyle.Typography.metadataMaximumNumberOfLines != 1
            && layout.metadataFrame.height + 0.5 >= wrappedHeight

        XCTAssertTrue(
            fitsOneLine || wrapsWithoutClipping,
            "U14: 字号 +8 时元信息需要 \(Int(singleLineWidth))pt，只给了 \(Int(layout.metadataFrame.width))pt 且限制 \(PostListCellStyle.Typography.metadataMaximumNumberOfLines) 行，时间会被截断"
        )
    }

    // MARK: - U23 「我的评论」点行只打开帖子顶部

    /// 期望：点评论行打开该评论所在页并定位到对应楼层。
    func test_U23_userCommentRowTapOpensCommentFloor() async throws {
        UXAuditMockURLProtocol.responsesByPath = [
            "/api/content/list-comments": #"{"success":true,"comments":[{"post_id":1047296,"title":"测试帖","rank":0,"floor_id":15,"text":"我的回复"}]}"#
        ]
        let controller = UserCommentsViewController(uid: 31037, client: NodeSeekUserContentClient(session: uxMockSession()))
        var opened: [(page: Int, anchor: String?)] = []
        controller.onSelectPost = { _, page, anchor in opened.append((page, anchor)) }
        controller.loadViewIfNeeded()

        let probeTable = ASTableNode()
        let loaded = await uxWaitUntil(timeout: 3) {
            controller.tableNode(probeTable, numberOfRowsInSection: 0) == 1
                && (uxChild(of: controller, named: "groups") as [UserCommentGroup]?)?.count == 1
        }
        XCTAssertTrue(loaded, "前置条件：评论列表应加载出 1 组")

        controller.tableNode(probeTable, didSelectRowAt: IndexPath(row: 0, section: 0))

        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(opened.first?.page, 2, "U23: 点评论行打开的是第 \(opened.first?.page ?? 0) 页，不是 #15 所在的第 2 页")
        XCTAssertEqual(opened.first?.anchor, "15", "U23: 点评论行没有带楼层锚点（anchor=\(opened.first?.anchor ?? "nil")），只打开帖子顶部")
    }

    // MARK: - U27 系统 Dynamic Type 不影响首页/详情字号

    /// 期望：系统字号调到辅助功能特大时，首页标题和详情正文字号随之变大。
    func test_U27_typographyScalesWithSystemDynamicType() {
        func pointSizes(for category: UIContentSizeCategory) -> (list: CGFloat, body: CGFloat) {
            var result: (CGFloat, CGFloat) = (0, 0)
            UITraitCollection(preferredContentSizeCategory: category).performAsCurrent {
                result = (
                    AppTypography.listTitleFont(pointOffset: 0).pointSize,
                    AppTypography.commentBodyFont(pointOffset: 0).pointSize
                )
            }
            return result
        }

        let standard = pointSizes(for: .large)
        let accessibility = pointSizes(for: .accessibilityExtraLarge)

        XCTAssertGreaterThan(
            accessibility.list, standard.list,
            "U27: 系统字号 .large 与 .accessibilityExtraLarge 下首页标题都是 \(standard.list)pt，没有跟随 Dynamic Type"
        )
        XCTAssertGreaterThan(
            accessibility.body, standard.body,
            "U27: 系统字号 .large 与 .accessibilityExtraLarge 下详情正文都是 \(standard.body)pt，没有跟随 Dynamic Type"
        )
    }

    // MARK: - U33 「我的」页点「粉丝」进入个人主页

    /// 期望：点资料卡里的「粉丝」进入粉丝列表，而不是个人主页。
    func test_U33_meFansStatOpensFollowersList() async throws {
        let context = try await makeLoggedInMePage()
        defer { context.window.isHidden = true }
        let me = context.viewController
        let card = try XCTUnwrap(uxDescendants(of: me.view).first { $0.accessibilityIdentifier == "me-profile-card" })
        let fansStat = try XCTUnwrap(
            uxDescendants(of: card).first { $0.accessibilityLabel?.hasPrefix("粉丝") == true && $0 !== card }
        )
        let point = fansStat.convert(CGPoint(x: fansStat.bounds.midX, y: fansStat.bounds.midY), to: card)
        let hitView = try XCTUnwrap(card.hitTest(point, with: nil))
        var control: UIView? = hitView
        while let candidate = control, !(candidate is UIControl) { control = candidate.superview }
        (control as? UIControl)?.sendActions(for: .touchUpInside)
        _ = await uxWaitUntil(timeout: 1) { context.navigationController.viewControllers.count > 1 }

        let list = try XCTUnwrap(context.navigationController.topViewController as? UserConnectionsViewController)
        let tabs = try XCTUnwrap(uxDescendants(of: list.view).first {
            $0.accessibilityIdentifier == "connections-tabs"
        } as? UISegmentedControl)
        XCTAssertEqual(UserConnectionKind.allCases.firstIndex(of: .followers), tabs.selectedSegmentIndex)
        XCTAssertEqual(context.navigationController.viewControllers.count, 2)
    }

    func testMeLevelProgressRowPresentsTodayProgressCard() async throws {
        let context = try await makeLoggedInMePage()
        defer { context.window.isHidden = true }
        let me = context.viewController
        let views = uxDescendants(of: me.view)
        let row = try XCTUnwrap(views.first { $0.accessibilityIdentifier == "me-today-progress" } as? UIControl)
        let card = try XCTUnwrap(views.first { $0.accessibilityIdentifier == "me-profile-card" })
        let point = row.convert(CGPoint(x: row.bounds.midX, y: row.bounds.maxY - 3), to: card)
        XCTAssertTrue(card.hitTest(point, with: nil) === row)
        row.sendActions(for: .touchUpInside)

        let sheet = try XCTUnwrap(me.presentedViewController as? UINavigationController)
        let detail = try XCTUnwrap(sheet.topViewController as? MeTodayProgressViewController)
        let progress = try XCTUnwrap(uxDescendants(of: detail.view).compactMap { $0 as? UserProfileProgressCardView }.first)
        XCTAssertFalse(progress.isHidden)
        XCTAssertTrue(uxDescendants(of: progress).contains { ($0 as? UILabel)?.text == "7 / 20" })
        XCTAssertTrue(context.navigationController.topViewController === me)
    }

    // MARK: - U34 「添加探针」填写后关闭不确认

    /// 期望：添加探针已填写内容时点取消，先弹放弃确认，不直接关闭。
    func test_U34_probeEditorAsksBeforeDiscardingTypedAddress() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ux-audit-probe-\(UUID().uuidString)"))
        let editor = ProbeInstanceEditorViewController(
            instance: nil,
            store: ProbeInstanceStore(defaults: defaults),
            service: UXAuditProbeService()
        )
        let host = UIViewController()
        let window = uxMakeWindow(root: host)
        defer { window.isHidden = true }
        let navigation = UINavigationController(rootViewController: editor)
        host.present(navigation, animated: false)
        editor.view.layoutIfNeeded()

        let urlCell = try XCTUnwrap(
            editor.tableView(editor.tableView, cellForRowAt: IndexPath(row: 1, section: 0)) as? ProbeTextFieldCell
        )
        urlCell.textField.text = "probe.example.com"
        urlCell.textField.sendActions(for: .editingChanged)

        guard #available(iOS 16.0, *) else { throw XCTSkip("需要 iOS 16 触发 UIAction") }
        editor.navigationItem.leftBarButtonItem?.primaryAction?.performWithSender(nil, target: nil)
        try await Task.sleep(nanoseconds: 300_000_000)

        let alert = (editor.presentedViewController ?? navigation.presentedViewController) as? UIAlertController
        XCTAssertNotNil(
            alert,
            "U34: 已填写探针地址后点取消直接关闭（presented=\(host.presentedViewController.map { String(describing: type(of: $0)) } ?? "nil")），没有放弃确认"
        )
    }

    // MARK: - U35 侧边栏菜单文字左边缘不齐

    /// 期望：侧边栏各菜单行的文字左边缘对齐（不受图标宽度影响）。
    func test_U35_sideMenuRowTitlesShareLeadingEdge() throws {
        let suite = "ux-audit-side-menu-\(UUID().uuidString)"
        let menu = PostListSideMenuViewController(
            currentAccountStore: CurrentAccountStore(userDefaults: UserDefaults(suiteName: suite)!, storageKey: "account"),
            accountRefresher: UXAuditAccountRefresher(),
            notificationClient: UXAuditNotificationClient()
        )
        let window = uxMakeWindow(root: menu)
        defer { window.isHidden = true }
        menu.show(animated: false)
        window.layoutIfNeeded()

        let identifiers = [
            "post-list-side-menu-new-discussion-button",
            "post-list-side-menu-check-in-button",
            "post-list-side-menu-notification-button",
            "post-list-side-menu-recent-visited-button",
            "post-list-side-menu-search-button",
            "post-list-side-menu-probe-button",
            "post-list-side-menu-mail-button"
        ]
        let buttons = uxDescendants(of: menu.view).compactMap { $0 as? UIButton }
        var leadings: [String: CGFloat] = [:]
        for identifier in identifiers {
            guard let button = buttons.first(where: { $0.accessibilityIdentifier == identifier }),
                  button.window != nil, !button.isHidden else { continue }
            button.layoutIfNeeded()
            guard let titleLabel = button.titleLabel, titleLabel.bounds.width > 0 else { continue }
            leadings[identifier] = titleLabel.convert(titleLabel.bounds, to: nil).minX
        }
        XCTAssertGreaterThanOrEqual(leadings.count, 3, "前置条件：至少应找到 3 个可见菜单行")

        let values = leadings.values
        let spread = (values.max() ?? 0) - (values.min() ?? 0)
        let detail = leadings.sorted { $0.key < $1.key }
            .map { "\($0.key.replacingOccurrences(of: "post-list-side-menu-", with: "")):\(String(format: "%.1f", $0.value))" }
            .joined(separator: ", ")
        XCTAssertLessThan(spread, 0.5, "U35: 侧边栏菜单文字左边缘相差 \(String(format: "%.1f", spread))pt（\(detail)）")
    }

    // MARK: - U36 搜索结果不高亮关键词

    /// 期望：帖子搜索结果标题里的关键词有区别于其他文字的样式。
    func test_U36_searchResultTitleHighlightsKeyword() async throws {
        let post = PostSummary(
            id: "1047296",
            title: "出一台美西 VPS，年付 10 刀",
            url: URL(string: "https://www.nodeseek.com/post-1047296-1")!,
            authorName: "mist",
            nodeName: "交易",
            replyCount: 3,
            viewCount: 40,
            lastActivityText: "1min ago"
        )
        let service = NodeSeekService(
            htmlClient: UXAuditStaticHTMLClient(html: "<html><body></body></html>"),
            parser: UXAuditPostListParser(posts: [post])
        )
        let viewController = SearchViewController(
            service: service,
            visitedStore: EmptyVisitedPostStore(),
            searchHistoryStore: uxSearchHistoryStore(),
            searchPreferenceStore: uxSearchPreferenceStore()
        )
        let window = uxMakeWindow(root: viewController)
        defer { window.isHidden = true }
        viewController.view.layoutIfNeeded()

        let keywordField = try XCTUnwrap(uxDescendants(of: viewController.view).compactMap { $0 as? UITextField }
            .first { $0.accessibilityIdentifier == "search-keyword-text-field" })
        keywordField.text = "美西"
        _ = viewController.textFieldShouldReturn(keywordField)

        var titleText: NSAttributedString?
        _ = await uxWaitUntil(timeout: 3) {
            window.layoutIfNeeded()
            let cell = uxDescendants(of: viewController.view).compactMap { $0 as? PostSummaryCell }.first
            titleText = cell.flatMap { uxChild(of: $0, named: "titleLabel") as UILabel? }?.attributedText
            return titleText?.string.contains("美西") == true
        }
        let title = try XCTUnwrap(titleText, "前置条件：搜索结果应显示 1 条帖子")
        let keywordLocation = (title.string as NSString).range(of: "美西").location
        let plainLocation = (title.string as NSString).range(of: "出").location
        let keywordAttributes = title.attributes(at: keywordLocation, effectiveRange: nil) as NSDictionary
        let plainAttributes = title.attributes(at: plainLocation, effectiveRange: nil) as NSDictionary

        XCTAssertFalse(
            keywordAttributes.isEqual(plainAttributes),
            "U36: 搜索结果标题里关键词「美西」与其他文字样式完全相同，没有高亮"
        )
    }

    // MARK: - U37 切到「用户」Tab 不自动搜索

    /// 期望：输入框已有关键词时从「帖子」切到「用户」，自动用该关键词搜索用户。
    func test_U37_switchingToUserScopeSearchesExistingKeyword() async throws {
        let searcher = UXAuditUserSearcher()
        let service = NodeSeekService(
            htmlClient: UXAuditStaticHTMLClient(html: "<html><body></body></html>"),
            parser: UXAuditPostListParser(posts: [])
        )
        let viewController = SearchViewController(
            service: service,
            visitedStore: EmptyVisitedPostStore(),
            searchHistoryStore: uxSearchHistoryStore(),
            searchPreferenceStore: uxSearchPreferenceStore(),
            userSearcher: searcher,
            isLoggedIn: { true }
        )
        viewController.loadViewIfNeeded()
        let keywordField = try XCTUnwrap(uxDescendants(of: viewController.view).compactMap { $0 as? UITextField }
            .first { $0.accessibilityIdentifier == "search-keyword-text-field" })
        let scopeControl = try XCTUnwrap(uxDescendants(of: viewController.view)
            .first { $0.accessibilityIdentifier == "search-scope-control" } as? SearchScopeTabsView)

        keywordField.text = "酒神"
        _ = viewController.textFieldShouldReturn(keywordField)
        scopeControl.selectedSegmentIndex = 1
        scopeControl.sendActions(for: .valueChanged)
        _ = await uxWaitUntil(timeout: 1) { !searcher.keywords.isEmpty }

        XCTAssertEqual(
            searcher.keywords, ["酒神"],
            "U37: 切到「用户」Tab 后关键词「酒神」仍在输入框，但没有自动搜索用户"
        )
    }

    // MARK: - U40 字号滑块使用系统蓝

    /// 期望：字号滑块的已选轨道颜色跟随黑白主题（.label），不用系统蓝。
    func test_U40_textSizeSliderUsesMonochromeTint() {
        let cell = SettingsTextSizeAdjustmentCell(style: .default, reuseIdentifier: nil)
        let slider = cell.slider
        let light = UITraitCollection(userInterfaceStyle: .light)
        let effective = (slider.minimumTrackTintColor ?? slider.tintColor ?? .systemBlue).resolvedColor(with: light)

        XCTAssertTrue(
            effective.uxIsClose(to: UIColor.label.resolvedColor(with: light)),
            "U40: 字号滑块已选轨道颜色为 \(effective)（minimumTrackTintColor=\(String(describing: slider.minimumTrackTintColor))），不是黑白主题的 .label"
        )
    }

    // MARK: - U42 时间格式不统一

    /// 期望：首页列表时间与「最近浏览」一样按中文相对时间显示（如「7个月前」），而不是站点英文原文「24s ago」。
    func test_U42_listTimeUsesLocalizedRelativeFormat() throws {
        let posts = try KannaNodeSeekParser(baseURL: NodeSeekSite.baseURL).parsePostList(html: Self.postListHTML)
        let post = try XCTUnwrap(posts.first)
        let metadata = PostSummaryText.metadataAttributedText(for: post).string

        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-04-27T05:46:32Z"))
        let expected = formatter.localizedString(for: date, relativeTo: Date())

        XCTAssertTrue(
            metadata.contains(expected) && !metadata.contains("ago"),
            "U42: 首页元信息时间为「\(metadata)」，与最近浏览的中文相对时间格式（应为「\(expected)」）不一致"
        )
    }

    // MARK: - Fixtures

    /// 取自 page-1.html 的一条真实列表项。
    private static let postListHTML = """
    <html><body><ul class="post-list"><li class="post-list-item"><a href="/space/17843"><img src="/avatar/17843.png" alt="橘子海" class="avatar-normal"></a>
    <div class="post-list-content"><div role="heading" aria-level="3" class="post-title"><a href="/post-703692-1">115非VIP账号海外上传速度如何</a></div>
    <div class="post-info"><span class="info-item info-author"><a href="/space/17843">橘子海</a></span>
    <span class="info-item info-views"><span title="39 views">39</span></span>
    <span title="4 comments" class="info-item info-comments-count"><span title="5 comments">4</span></span>
    <span class="info-item info-last-commenter"><a href="/space/5714">harunoyuki</a></span>
    <a href="/post-703692-1#4" class="info-item info-last-comment-time"><time title="2026-04-27 13:46:32" datetime="2026-04-27T05:46:32.000Z">24s ago</time></a>
    <a href="/categories/daily" class="info-item post-category">日常</a></div></div></li></ul></body></html>
    """

    private static func fraction(after keyword: String, in text: String) -> String? {
        guard let range = text.range(of: "\(keyword)\\s*(\\d+)\\s*/\\s*(\\d+)", options: .regularExpression) else { return nil }
        return String(text[range]).replacingOccurrences(of: keyword, with: "").replacingOccurrences(of: " ", with: "")
    }

    private struct MePageContext {
        let viewController: MeViewController
        let navigationController: UINavigationController
        let window: UIWindow
        let client: NodeSeekUserContentClient
        let todayLabelText: String?
    }

    /// 用独立账号存储和模拟接口搭一个已登录、资料与今日进度都已加载的「我的」页。
    private func makeLoggedInMePage() async throws -> MePageContext {
        UXAuditMockURLProtocol.responsesByPath = [
            "/api/account/getInfo/31037": #"{"success":true,"detail":{"member_id":31037,"member_name":"缭雾","rank":4,"coin":2000,"stardust":21,"bio":"","created_at":"2024-11-23T17:11:12.000Z","nPost":26,"nComment":607,"follows":3,"fans":5,"readme":"","followed":false}}"#,
            "/api/progress/today": #"{"success":true,"postBonusCount":0,"maxPostBonusCount":4,"commentBonusCount":7,"maxCommentBonusCount":20,"maxFreeLike":3,"freeLikeUsed":0}"#,
            "/api/attendance/board": #"{"list":[],"record":null}"#
        ]
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ux-audit-me-\(UUID().uuidString)"))
        let store = CurrentAccountStore(userDefaults: defaults, storageKey: "account")
        await store.save(AccountResponse(
            displayName: "缭雾",
            isLoggedIn: true,
            profileURL: URL(string: "https://www.nodeseek.com/space/31037")
        ))
        let client = NodeSeekUserContentClient(session: uxMockSession())
        let me = MeViewController(
            accountController: PostListSideMenuAccountController(
                currentAccountStore: store,
                accountRefresher: UXAuditAccountRefresher()
            ),
            client: client,
            notificationClient: UXAuditNotificationClient(),
            visitedStore: EmptyVisitedPostStore()
        )
        let navigation = UINavigationController(rootViewController: me)
        let window = uxMakeWindow(root: navigation)

        var todayText: String?
        _ = await uxWaitUntil(timeout: 3) {
            window.layoutIfNeeded()
            todayText = uxDescendants(of: me.view).compactMap { ($0 as? UILabel)?.text }
                .first { $0.hasPrefix("今日") && $0.contains("发帖") }
            let fansLoaded = uxDescendants(of: me.view).contains { $0.accessibilityLabel == "粉丝 5" }
            return todayText != nil && fansLoaded
        }
        window.layoutIfNeeded()
        return MePageContext(
            viewController: me,
            navigationController: navigation,
            window: window,
            client: client,
            todayLabelText: todayText
        )
    }
}

// MARK: - Helpers

@MainActor
private func uxDescendants(of view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap { uxDescendants(of: $0) }
}

/// 按属性名读私有存储属性，沿父类向上找。
private func uxChild<T>(of object: Any, named name: String) -> T? {
    var mirror: Mirror? = Mirror(reflecting: object)
    while let current = mirror {
        if let value = current.children.first(where: { $0.label == name })?.value as? T {
            return value
        }
        mirror = current.superclassMirror
    }
    return nil
}

@MainActor
private func uxWaitUntil(timeout: TimeInterval, _ condition: () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return await condition()
}

@MainActor
private func uxMakeWindow(root: UIViewController) -> UIWindow {
    let window: UIWindow
    if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
        window = UIWindow(windowScene: scene)
    } else {
        window = UIWindow()
    }
    window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
    window.windowLevel = .alert + 1
    window.rootViewController = root
    window.makeKeyAndVisible()
    window.layoutIfNeeded()
    return window
}

private func uxMockSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UXAuditMockURLProtocol.self]
    return URLSession(configuration: configuration)
}

@MainActor
private func uxSearchHistoryStore() -> SearchHistoryStore {
    SearchHistoryStore(userDefaults: UserDefaults(suiteName: "ux-audit-search-history-\(UUID().uuidString)")!, storageKey: "history")
}

@MainActor
private func uxSearchPreferenceStore() -> SearchPreferenceStore {
    SearchPreferenceStore(userDefaults: UserDefaults(suiteName: "ux-audit-search-pref-\(UUID().uuidString)")!, categoryStorageKey: "category")
}

private extension UIColor {
    func uxIsClose(to other: UIColor) -> Bool {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return abs(r1 - r2) < 0.02 && abs(g1 - g2) < 0.02 && abs(b1 - b2) < 0.02 && abs(a1 - a2) < 0.02
    }
}

// MARK: - Test doubles

private final class UXAuditWebViewController: BaseWebViewController {
    init() {
        super.init(initialURL: NodeSeekSite.baseURL, pageTitle: "每日签到", automaticallyLoadsPage: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadInitialPage() {}
}

private final class UXAuditFakePan: UIPanGestureRecognizer {
    var fakeTranslation: CGPoint = .zero

    override func translation(in view: UIView?) -> CGPoint {
        fakeTranslation
    }
}

/// 模拟手指正在拖动的列表。
private final class UXAuditTrackingScrollView: UIScrollView {
    let fakePan = UXAuditFakePan()

    override var isTracking: Bool { true }
    override var panGestureRecognizer: UIPanGestureRecognizer { fakePan }
}

private final class UXAuditFloatingPositionStore: FloatingControlPositionStoring {
    private var positions: [String: FloatingControlPosition] = [:]

    func position(forKey key: String) -> FloatingControlPosition? {
        positions[key]
    }

    func save(_ position: FloatingControlPosition, forKey key: String) {
        positions[key] = position
    }
}

private final class UXAuditPostListPresenter: PostListPresenterProtocol {
    func viewDidLoad() {}
    func viewWillAppear() {}
    func didEnterForeground() {}
    func didReceiveNotificationReadStateChange() {}
    func didReceiveNotificationUnreadCountUpdate(_ unreadCount: NodeSeekNotificationUnreadCount) {}
    func didSelectCategory(_ category: PostListCategoryItem) {}
    func didReselectCategory(_ category: PostListCategoryItem) {}
    func didTapLogin() {}
    func didTapAccountProfile(profileURL: URL) {}
    func didTapNewDiscussion() {}
    func didTapCheckIn() {}
    func didTapNotification(url: URL) {}
    func didTapRecentVisited() {}
    func didTapUserDiscussions() {}
    func didTapUserComments() {}
    func didTapUserCollections() {}
    func didTapSearch() {}
    func didTapProbe() {}
    func didTapMail() {}
    func didTapSettings() {}
    func didTapCategoryPreferences() {}
    func didTapLogFile() {}
    #if DEBUG
    func didTapDetailTest() {}
    func didSubmitDetailTestURL(_ rawURL: String) {}
    #endif
    func didSelectPost(_ post: PostSummary) {}
}

private final class UXAuditAccountRefresher: CurrentAccountRefreshing, @unchecked Sendable {
    func cachedAccount() async -> AccountResponse? { nil }
    func refreshIfNeeded(force: Bool, maxAge: TimeInterval) async -> AccountResponse? { nil }
}

private actor UXAuditNotificationClient: NodeSeekNotificationClientProtocol {
    func loadUnreadCount() async throws -> NodeSeekNotificationUnreadCount { .zero }
    func loadAtMe() async throws -> [NodeSeekNotificationRecord] { [] }
    func loadReplies() async throws -> [NodeSeekNotificationRecord] { [] }
    func loadMessageConversations() async throws -> [NodeSeekMessageConversationRecord] { [] }
    func markViewed(ids: [Int], tab: NodeSeekNotificationTab) async throws {}
    func markAllViewed(tab: NodeSeekNotificationTab) async throws {}
}

private final class UXAuditProbeService: ProbeFetching, @unchecked Sendable {
    func testConnection(baseURL: URL, adapterID: String) async throws -> ProbeConnectionInfo {
        ProbeConnectionInfo(version: "1.6.1", nodes: [])
    }
    func snapshot(for instance: ProbeInstance, reloadNodes: Bool) async throws -> ProbeSnapshot {
        ProbeSnapshot(nodes: [], statuses: [:], fetchedAt: Date())
    }
    func history(for instance: ProbeInstance, nodeID: String, hours: Int) async throws -> [ProbeHistoryPoint] { [] }
    func forget(instanceID: UUID) async {}
}

private struct UXAuditStaticHTMLClient: HTMLClient {
    let html: String

    func get(_ url: URL) async throws -> HTMLResponse {
        HTMLResponse(statusCode: 200, headers: [:], finalURL: url, html: html)
    }

    func post(_ url: URL, formFields: [String: String]) async throws -> HTMLResponse {
        try await get(url)
    }
}

private struct UXAuditPostListParser: NodeSeekParser {
    let posts: [PostSummary]

    func parsePostList(html: String) throws -> [PostSummary] { posts }
    func parsePostDetail(html: String, url: URL) throws -> PostDetail {
        throw NSError(domain: "UXAuditPostListParser", code: 1)
    }
    func parseCheckInState(html: String, pageURL: URL) throws -> CheckInState {
        CheckInState(isCheckedIn: false, message: "", actionURL: nil, hiddenFields: [:])
    }
    func parseAccount(html: String) throws -> AccountResponse {
        AccountResponse(displayName: "未登录", isLoggedIn: false)
    }
}

private final class UXAuditUserSearcher: UserSearchLoading, @unchecked Sendable {
    private(set) var keywords: [String] = []

    func findMembers(keyword: String) async throws -> [UserConnectionRecord] {
        keywords.append(keyword)
        return []
    }
}

private final class UXAuditMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responsesByPath: [String: String] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((Self.responsesByPath[url.path] ?? "{}").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
