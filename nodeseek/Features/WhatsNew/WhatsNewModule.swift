//
//  WhatsNewModule.swift
//  nodeseek
//

import SwiftUI
import UIKit
import WhatsNewKit

enum WhatsNewModule {
    /// 各版本的新功能内容，新版本往前插入；为空时不弹出、设置页也不显示入口。
    /// 内容与样式约束见 docs/project-overview.md 的「新功能介绍页」一节。
    ///
    /// 示例：
    /// ```swift
    /// release("1.0.11", features: [
    ///     feature(
    ///         systemName: "person.crop.circle.badge.checkmark",
    ///         tint: .systemBlue,
    ///         title: "只看楼主",
    ///         subtitle: "长按回复，可以只看楼主或某个人的发言。"
    ///     )
    /// ])
    /// ```
    static let catalog: [WhatsNew] = [
        release("1.1.0", features: [
            feature(
                systemName: "person.crop.circle.fill",
                tint: .systemBlue,
                title: "原生个人页",
                subtitle: "资料、今日进度和自述一屏看全"
            ),
            feature(
                systemName: "star.fill",
                tint: .systemOrange,
                title: "星辰与鸡腿",
                subtitle: "余额和每笔变动原生展示"
            ),
            feature(
                systemName: "person.2.fill",
                tint: .systemIndigo,
                title: "关注与粉丝",
                subtitle: "名单原生展示，左右滑动切换"
            ),
            feature(
                systemName: "photo.fill",
                tint: .systemPink,
                title: "看大图",
                subtitle: "从原图位置放大打开、缩回关闭"
            )
        ]),
        release("1.0.11", features: [
            feature(
                systemName: "square.and.pencil",
                tint: .systemBlue,
                title: "原生发帖",
                subtitle: "草稿自动保存，支持格式、插图和预览"
            ),
            feature(
                systemName: "pencil.circle.fill",
                tint: .systemOrange,
                title: "编辑帖子",
                subtitle: "自己的帖子和评论可以直接修改"
            ),
            feature(
                systemName: "person.crop.circle.fill.badge.checkmark",
                tint: .systemIndigo,
                title: "只看楼主",
                subtitle: "长按菜单可只看楼主或某人的回复"
            ),
            feature(
                systemName: "moon.fill",
                tint: .systemPurple,
                title: "图片变暗",
                subtitle: "深色模式下图片可调暗，分三档"
            )
        ])
    ]

    static var hasContent: Bool { !catalog.isEmpty }

    /// 当前版本有内容且未展示过时返回，否则返回 nil。
    static func whatsNewToPresent(
        currentVersion: WhatsNew.Version = .current(),
        versionStore: WhatsNewVersionStore,
        catalog: [WhatsNew] = catalog
    ) -> WhatsNew? {
        guard let whatsNew = catalog.first(where: { $0.version == currentVersion }) else { return nil }
        return versionStore.hasPresented(whatsNew) ? nil : whatsNew
    }

    /// 启动后自动弹出，同一版本只弹一次。
    @MainActor
    static func presentIfNeeded(
        from presenter: UIViewController,
        versionStore: WhatsNewVersionStore = UserDefaultsWhatsNewVersionStore()
    ) {
        // 已有其他弹窗（如自动签到提示）时不叠加
        guard presenter.presentedViewController == nil,
              let whatsNew = whatsNewToPresent(versionStore: versionStore),
              let viewController = WhatsNewViewController(whatsNew: whatsNew, versionStore: versionStore) else { return }
        presenter.present(viewController, animated: true)
    }

    /// 设置页手动查看，不受是否已展示限制。
    @MainActor
    static func makeViewController() -> UIViewController? {
        let current = WhatsNew.Version.current()
        guard let whatsNew = catalog.first(where: { $0.version == current }) ?? catalog.first else { return nil }
        return WhatsNewViewController(whatsNew: whatsNew)
    }

    /// 一个版本的介绍页，标题和按钮固定，内容只需提供功能列表。
    static func release(_ version: WhatsNew.Version, features: [WhatsNew.Feature]) -> WhatsNew {
        WhatsNew(
            version: version,
            title: "NS Connect\n新功能",
            features: features,
            primaryAction: WhatsNew.PrimaryAction(
                title: "继续",
                // 跟随 App 黑白主题，按钮用文字色反色
                backgroundColor: .primary,
                foregroundColor: Color(.systemBackground)
            )
        )
    }

    static func feature(
        systemName: String,
        tint: UIColor,
        title: String,
        subtitle: String
    ) -> WhatsNew.Feature {
        WhatsNew.Feature(
            // 仿系统设置图标：彩色圆角底 + 白色符号，页面其余部分保持黑白主题
            image: .init {
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color(tint))
                    )
            },
            title: WhatsNew.Text(title),
            subtitle: WhatsNew.Text(subtitle)
        )
    }
}
