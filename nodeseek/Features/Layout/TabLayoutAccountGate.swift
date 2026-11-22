//
//  TabLayoutAccountGate.swift
//  nodeseek
//

import Foundation

/// 多 Tab 模式下需要登录的入口（发帖、签到等）点击前的登录判断。
enum TabLayoutAccountGate {
    /// 直接使用已登录账号，游客状态超过一分钟再重新确认。
    static func isLoggedIn(refresher: (any CurrentAccountRefreshing)? = nil) async -> Bool {
        let refresher = refresher ?? CurrentAccountRefresher.shared
        if await refresher.cachedAccount()?.isLoggedIn == true {
            return true
        }
        return await refresher.refreshIfNeeded(force: false, maxAge: 60)?.isLoggedIn == true
    }
}
