# 1.4.1 邮箱绑定崩溃复盘

记录日期为 2026-11-19，文中时间使用 UTC+8。

## 问题与影响

TestFlight 1.4.1（20261118184746）收到一条“邮箱 api 保存崩溃”反馈。事故发生于 11 月 19 日 02:47，设备为 iPhone18,4，系统为 iOS 27.2.1。用户点击“验证并保存”后，程序在验证邮箱列表的网络请求阶段终止。钥匙串保存和响应解析均位于该调用之后。

本次查询返回的 5 条历史崩溃反馈中，只有这一条属于 1.4.1。反馈条数无法用于计算整体崩溃率，也无法确定所有设备的触发概率。

## 日志证据与定位

异常为 `EXC_BAD_ACCESS (SIGSEGV)`，访问地址为 `0x10`，触发线程为线程 2。符号化堆栈包含以下路径。

```text
SeekMailBindViewController.saveTapped()
  → verify(key)
  → SeekMailProvider.mailboxes()
  → request(_:)
  → perform(_:)
  → transport(request)
  → async thunk (Builtin.ImplicitActor, URLRequest)
  → URLSession.data(for:delegate:)
  → URLRequest._bridgeToObjectiveC()
  → _MutableHandle._copiedReference()
  → objc_msgSend
```

业务入口定位到 `SeekMailBindViewController.swift` 的保存任务，传输调用定位到 `SeekMailProvider.swift`。系统框架顶部的崩溃只表明读取请求对象时访问了无效内存，单靠它还不能确定对象损坏的来源。

首先核对请求创建、鉴权头设置、插件处理和闭包调用。请求是方法内的局部值，代码中没有直接操作其底层指针。随后将调查重点转向闭包隔离转换和构建条件，避免仅凭系统框架栈顶就归因于网络、API Key 或系统故障。

## 工具链差异与根因方向

| 条件 | 本地 | 发布 CI |
| --- | --- | --- |
| Xcode | 27.2（27B52） | 26.3（17C529） |
| Swift | 6.4.2 | 6.2.4 |
| 主机架构 | arm64 | x86_64 |
| 选择方式 | 本机选中的 Xcode | macos-15-intel 上的 latest-stable |

项目同时启用了 Swift 5 语言模式、默认 MainActor 隔离和 Approachable Concurrency。原传输类型为以下声明。

```swift
typealias Transport = (URLRequest) async throws -> (Data, URLResponse)
```

在上述配置下，未显式声明隔离的 async 函数类型可能采用继承调用方隔离的语义。默认闭包与存储的函数类型之间需要编译器生成转换函数。Swift #91611 报告了这类转换传错结构体参数的缺陷，现象与本次 `Builtin.ImplicitActor` 转换栈和请求对象读取异常高度吻合。隐含 Actor 参数造成参数位置错误属于该报告提出的机制解释，本次实验没有进行寄存器级验证。[Swift #91611](https://github.com/swiftlang/swift/issues/91611)

旧代码已有 `@_optimize(none) deinit {}` 条件绕过，针对的是旧编译器泛型析构相关的编译阶段崩溃。此次仍在运行时闭包调用中发生异常，需要单独处理。项目注释引用的 #88173 讨论的是优化器编译崩溃，不能作为本次运行时根因的直接证明。[Swift #88173](https://github.com/swiftlang/swift/issues/88173)

## 复现实验

在独立分支 `diagnose/mail-141-repro` 提取泛型 Provider、默认 URLSession 传输闭包和 URLRequest 参数传递。使用虚拟 Key 请求 `127.0.0.1:1`，捕获正常网络错误，循环执行 100 次，避免依赖真实邮箱账号或服务。实验验证能否正常经过请求传输路径，未验证服务器成功响应。

CI 固定 Xcode 26.3，分别比较原始类型和显式 `@MainActor` 类型。

| 环境与模式 | 原始类型 | 显式 @MainActor |
| --- | --- | --- |
| 本地 Swift 6.4.2，Release | 100 次调用完成 | 未在该实验单独运行 |
| CI Swift 6.2.4，Debug | SIGSEGV，退出码 139 | 100 次调用完成 |
| CI Swift 6.2.4，Release | 编译器自身 signal 11 | 100 次调用完成 |

CI 的 Debug 堆栈显示 `URLSession.data(for:) → objc_msgSend`，访问地址为 `0x18`，与手机日志的调用链高度相似。实验在 macOS x86_64 上运行，未完整复现 iPhone arm64 上的 1.4.1 Release 二进制。Release 最小程序的编译崩溃限制了该项运行时对照，因此不能声称完整 App 的所有场景已得到同环境验证。Debug 也能触发，说明排查不能只盯 Release 优化。[最终实验与完整堆栈](https://github.com/tyrad/nodeseek/actions/runs/44412931182)

证据支持旧工具链的异步闭包隔离转换缺陷为本次事故的主要根因方向。新工具链最小程序运行成功只说明该实验未触发，不能据此宣称整个缺陷已在该版本全面修复。

## 修复与验证

在传输函数类型上显式声明 MainActor，使调用双方的隔离约定一致。

```swift
// 显式隔离避免旧版 Swift 转换异步闭包时破坏 URLRequest 参数。
typealias Transport = @MainActor (URLRequest) async throws -> (Data, URLResponse)
```

URLSession 的异步等待会挂起任务，该声明用于明确闭包隔离约定。修改复用了现有 Provider 和注入接口，仅调整函数类型与必要注释。

通过项目 make 入口运行 `SeekMailAPITests`、`SeekMailBindTests` 和 `SeekMailInboxModelTests`。本地 iOS 27.2 模拟器测试结果为 46 项测试、含参数化用例共 51 次执行，0 失败。旧工具链最小实验的修正版本也在 Debug、Release 下各完成 100 次调用。

修复提交为 `0b516f0`，随 1.4.2（20261119064405）发布。该版本仍由 Xcode 26.3 构建，归档与上传成功，Apple 处理状态为 VALID，Crashlytics 主程序与 Widget 符号均上传成功。同一个上传构建用于 TestFlight 和 App Store，App Store 加急申请已获 Apple 确认。记录时尚无修复版本的真机复测结论或线上崩溃率观察结果。[1.4.2 发布记录](https://github.com/tyrad/nodeseek/actions/runs/44414243739)

## 排查方法与后续改进

1. 先核对版本、构建号、设备和符号化堆栈，将反馈操作对应到真实调用链。
2. 本地无法复现时，比较发布构建的提交、Xcode build、Swift、SDK、编译模式和主机架构。
3. 在结构体参数经过 async thunk 后出现内存访问异常时，检查 Actor 隔离转换，并查找配置与签名相符的编译器问题。
4. 通过最小程序和单变量对照验证假设，分别记录编译失败、运行崩溃和正常网络错误。
5. 修复后同时覆盖旧工具链复现、本地业务测试和实际 TestFlight 构建，保留每一项的验证边界。

本轮将发布工作流改为 `xcode-27` arm64 runner，固定 Xcode 27.2，并在构建前检查 Xcode build `27B52`、Swift 编译器标识和 arm64 架构，同时输出 iOS SDK 版本。GitHub 镜像清单列出了对应 Xcode build。版本不匹配时流程提前失败，避免静默使用不同工具链。[GitHub runner 镜像清单](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)

以后升级本机 Xcode 时，应同步更新工作流固定版本和校验值，并验证 Release 构建。复现发布问题时优先切回发布使用的工具链，同步核对依赖锁定文件和构建参数。工具链一致能缩小差异范围，设备系统、数据、网络和运行状态仍需独立覆盖。最终发布验证应安装待发布的 TestFlight 构建，通过后在商店复用同一个构建。

工作流变更的远端首次执行仍待验证，本轮文档及配置修改不代表已用新工具链重新发布 1.4.2。
