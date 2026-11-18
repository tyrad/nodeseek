# 崩溃反馈

主 App 使用 FirebaseCrashlytics 13.2.0 起的兼容版本（Swift Package Manager），不接入 Analytics。关闭 Firebase 默认的 Firestore trait，避免下载不使用的数据库组件；该优化需要 Xcode 26.4 或更高版本。配置位于 `nodeseek/Resources/GoogleService-Info.plist`，仅加入主 App。

`FirebaseCrashlyticsCollectionEnabled = true` 启用 SDK 自动收集和上传。崩溃时由 SDK 保存报告，通常在下次启动时自动发送，无需用户操作。日志页不再提供手动发送按钮。网络失败后的排队与重试由 SDK 管理；不保证崩溃当时立即上传，也不保证覆盖所有系统终止。

不转发普通文件日志、论坛账号或邮箱凭据。单测宿主不启动 Firebase；`make xcode-test-class TEST=CrashReportServiceTests` 验证打包后的自动上传开关及配置匹配。

App Store 隐私申报维护在 `fastlane/app-privacy.json`：崩溃数据用于应用功能，其他诊断数据用于应用功能和分析，均不关联用户身份、不用于跟踪。依据当前 SDK 隐私清单及未设置用户 ID/自定义日志的集成方式；更改集成时重新核对。2026-11-18 已通过 `asc web privacy` 更新并核验发布状态。中英文公开政策位于 `docs/privacy.md`。Fastlane 的隐私上传从同一份声明转换，不再读取旧的本地声明文件。

以下历史验证记录来自此前手动发送版本，不能作为当前自动上传链路的端到端验证结果。

## 发布与真机验证

归档最后执行 Crashlytics 官方符号上传脚本，Release 使用 DWARF with dSYM。脚本兼容项目 `.build/SourcePackages` 和 Xcode 默认目录，自定义目录时设置 SOURCE_PACKAGES。普通模拟器构建不上传符号。

GitHub Actions 还会在 Fastlane 步骤之后同步上传 `build/*.dSYM.zip`，避免仅依赖官方 `run` 的后台上传。失败会明确标记工作流失败，既有 dSYM artifact 仍会保存；若 TestFlight 已上传成功，不会撤回该包。Fastlane 固定 SPM 目录为 `.build/SourcePackages`，上传使用现有 GoogleService 配置，无需新增 Firebase 登录 secret。报告查询与补传操作见项目 skill：`.agents/skills/nodeseek-crashlytics/SKILL.md`。

1. 使用开发真机构建，在本地临时加入测试崩溃触发点（不提交、不发布）。
2. 脱离 Xcode 调试器启动 App，触发崩溃，再次启动。
3. 重启后不进行任何发送操作，检查 SDK 上传日志。
4. 确认日志页不再出现发送按钮。
5. 联网等待后，在 Firebase 项目 nodeseek-887f4 的 Crashlytics 中检查报告、版本及符号化堆栈。Debug 真机测试需生成并手动上传对应 dSYM，或使用归档构建。
6. 验证离线启动后恢复网络时 SDK 的重试行为。
7. 删除临时触发点。上线前更新隐私说明与 App Store 数据收集申报，以实际 SDK 收集行为为准。

不承诺覆盖所有系统终止；强制退出、内存终止等不应等同于可获取堆栈的崩溃。真机报告收取与包体/启动性能对比需要单独实测。

## 本次验证

GitHub Actions 构建时设置 `CRASHLYTICS_SKIP_BUILD_PHASE_UPLOAD=1`，跳过归档内的后台上传，由后续独立步骤同步上传。首次 CI 验证发现 Xcode 沙盒拒绝读取仓库内 Firebase `run` 脚本，采用此方式避免符号上传阻断归档。

2026-11-18：Xcode 27.2、iPhone 15 / iOS 17.5 模拟器，使用 `make xcode-test-class TEST=CrashReportServiceTests`（独立构建/依赖目录、arm64、并发 2）完成构建，4 项测试通过。检查构建产物确认主 App 包含 Firebase 配置、Widget 不包含，自动上传开关为 false。

尚未验证真机崩溃上传到 Firebase、归档符号实际送达、界面在不同字号/语言下的视觉表现，以及接入前后的包体和启动耗时差异。

## 模拟器端到端验证（2026-11-18）

在 iPhone 15 / iOS 17.5 模拟器中使用临时启动参数触发 `fatalError("NodeSeek Crashlytics E2E 20261118")`，未附加调试器。通过临时测试驱动调用日志页的 `sendCrashReport` 动作，非人工点击按钮。

- 未签名构建能捕获报告，但 Firebase Installations 出现 `SecItemCopyMatching (-34018)`；改用 `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-` 的模拟器构建后消失。
- 16:45:37：发送前状态 `available`，发送后状态 `requested`。
- 16:45:38：SDK 记录报告 `5654d0c2af9243d58f15d62422a01905` 已提交到传输层。
- 16:45:40：`crashlyticsreports-pa.googleapis.com/v1/firelog/legacy/batchlog` 请求返回 HTTP 200（请求关联 Task 64877EAD-1CC9-472A-81C5-4280A74323BF）。这验证了实际网络上传，不只是调用发送 API。
- 初次测试构建的主程序和 debug.dylib 符号已通过官方 upload-symbols 成功上传。后续签名重测构建的后台符号匹配仍需核验。
- 临时崩溃/自动调用发送动作代码已全部移除，恢复正常构建并重新安装到模拟器。

证据日志位于本机 `/tmp/nodeseek-e2e-signed-upload.log`、`/tmp/nodeseek-symbol-upload.log`。这些临时日志不提交仓库。

浏览器工具持续报告用户正在操作 Chrome，且标签页工具返回 timeoutMs 内部错误，因此尚未直接确认 Firebase 控制台展示及堆栈符号化。尚未验证归档脚本完整执行、真机、不同字号/语言视觉表现或包体/启动耗时。

### 后台核验与补传符号

随后通过 Firebase 控制台确认收到 1 份崩溃，但处于未处理状态，要求 UUID `C43C7C35-675A-3528-A997-4FB6D2094302` 的 dSYM。恢复完全相同的临时测试源码并重新构建后，生成的 debug.dylib dSYM UUID 与该值完全一致；官方 upload-symbols 已返回成功（同时上传主程序 UUID `0E98AB4C-5ECF-37C4-B13A-31C01D8E1341`）。符号保存在 `.build/CrashlyticsEvidence/test-20261118.dSYM`，临时测试源码已再次移除并恢复正常构建。

补传后的控制台刷新仍被浏览器用户操作保护拦截，尚未目视确认符号处理完成及源码行展示。

### 自动上传配置验证

改为自动上传后，主 App 构建及 CrashReportServiceTests 通过（1 项）。测试读取实际 App bundle，确认自动上传开关为 true 且 Firebase Bundle ID 匹配。已移除手动发送状态机、日志页按钮及对应本地化资源。此次未再次执行自动模式的测试崩溃和后台端到端核验。

### dSYM zip 实际上传验证

2026-11-18：将保留的 `test-20261118.dSYM` 压缩为 `.dSYM.zip`，使用 SDK 官方 `upload-symbols -gsp nodeseek/Resources/GoogleService-Info.plist -p ios` 实际上传。工具对上述主程序与 debug.dylib 两个 UUID 均返回 `Successfully submitted symbols`，最终返回 `Successfully uploaded Crashlytics symbols`，退出码为 0。未新增 Firebase 登录 token 或服务账号私钥。该结果验证本机 zip 上传路径；尚未执行 GitHub Actions 真实构建，也未核验后台符号化完成状态。

### GitHub Actions 发布验证

2026-11-18：[工作流 44278543353](https://github.com/tyrad/nodeseek/actions/runs/44278543353) 全部通过，发布版本 `1.4.1`、构建号 `20261118174337`，App Store Connect 返回 `VALID`。独立上传步骤确认主 App dSYM UUID `FF007936-B3B1-3B59-BDC5-935401A2E5E3` 和 Widget UUID `35298189-E31D-3224-AD3D-7FFBD666798D` 上传成功；IPA、dSYM 和构建来源信息已保存至 GitHub Release。该验证不代表新版本已触发真实崩溃或完成报告符号化核验。

该次 Intel runner 选择 Xcode 26.3，Apple 提示包使用 iOS 26.2 SDK（ITMS-90725），此次上传和处理成功；邮件要求从 2027 年 4 月起使用 Xcode 27 / iOS 27 SDK 或更高版本，后续需升级 CI 工具链。
