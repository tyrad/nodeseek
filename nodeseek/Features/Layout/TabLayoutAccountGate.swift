//
//  TabLayoutAccountGate.swift
//  nodeseek
//

import Foundation

/// 多 Tab 模式下需要登录的入口（发帖、签到等）点击前的登录判断。
enum TabLayoutAccountGate {
    /// 缓存显示已登录就直接放行；否则强制刷新一次，避免刚登录完缓存还是游客。
    static func isLoggedIn(refresher: (any CurrentAccountRefreshing)? = nil) async -> Bool {
        let refresher = refresher ?? CurrentAccountRefresher.shared
        if await refresher.cachedAccount()?.isLoggedIn == true {
            return true
        }
        return await refresher.refreshIfNeeded(force: true, maxAge: 0)?.isLoggedIn == true
    }
}
