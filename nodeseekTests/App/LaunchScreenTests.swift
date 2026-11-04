//
//  LaunchScreenTests.swift
//  nodeseekTests
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct LaunchScreenTests {
    /// 启动屏只靠 Info.plist 引用资源，资源改名或丢失时系统会静默显示空白屏。
    @Test func launchScreenAssetsExistForBothAppearances() throws {
        let launchScreen = try #require(Bundle.main.object(forInfoDictionaryKey: "UILaunchScreen") as? [String: Any])
        let imageName = try #require(launchScreen["UIImageName"] as? String)
        let colorName = try #require(launchScreen["UIColorName"] as? String)
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            #expect(UIImage(named: imageName, in: .main, compatibleWith: traits) != nil)
            #expect(UIColor(named: colorName, in: .main, compatibleWith: traits) != nil)
        }
    }
}
