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
    static let catalog: [WhatsNew] = []

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
