---
name: nodeseek-crashlytics
description: 排查 NodeSeek 的 Firebase Crashlytics 崩溃、使用 MCP 查询报告、检查 GitHub Actions 符号上传并补传匹配的 dSYM。
---

# NodeSeek Crashlytics

从仓库根目录执行以下命令。当前 Firebase 项目为 `nodeseek-887f4`，主 App 为 `com.mistj.nodeseek`；以 `nodeseek/Resources/GoogleService-Info.plist` 为配置依据。初始化、收集行为与验证记录见 `docs/crash-reporting.md`。

## 查询与分析

先发现当前可用的 Firebase MCP 工具，不假设已安装或已登录。没有工具时说明限制；需要配置时参考 [Firebase MCP](https://firebase.google.com/docs/crashlytics/ai-assistance-mcp)。安装配置不等于已经通过身份验证或有项目访问权限。

按用户指定的版本、时间范围或 issue 查询，使用 `crashlytics_get_report` 找到影响较大的问题，再用 `crashlytics_get_issue`、`crashlytics_list_events` 或 `crashlytics_batch_get_events` 获取具体堆栈。工具名称与参数以当前工具列表为准。

结合事件对应的构建版本、Git SHA 和源码分析，不把当前源码行号直接套到旧版本。区分实际堆栈证据与推测。添加备注或关闭 issue 仅在任务授权范围内执行。

## GitHub Actions 自动上传

`.github/workflows/testflight.yml` 通过 Fastlane 生成 `build/*.dSYM.zip`，随后执行 **Upload symbols to Firebase Crashlytics**。Fastlane 把 SPM checkout 固定在 `.build/SourcePackages`。独立步骤同步调用官方 `upload-symbols`，上传失败使工作流失败；TestFlight 已经上传成功的包不会因此撤回。

Xcode 归档还有 `scripts/upload-crashlytics-symbols.sh` 调用官方 `run`，其实际上传在后台执行，不能仅凭归档成功认定上传成功。Actions 的独立步骤用于检查同步上传结果。

Actions 构建步骤设置 `CRASHLYTICS_SKIP_BUILD_PHASE_UPLOAD=1`，跳过归档内的后台上传，避免 Xcode 沙盒阻止读取仓库内的 SDK 工具；符号统一在归档完成后的独立步骤上传。本地归档不设置该变量。

上传使用仓库中的 GoogleService 配置，无需额外 Firebase CLI 登录 token。不要把服务账号私钥写进 skill 或仓库。既有 Actions `dSYM` artifact 和成功发布的 Release 附件保留符号；下载时确认对应 run、版本和构建号。artifact 有保留期限。

### 核验与排错

- 用 `gh run view RUN_ID --json status,conclusion,jobs` 分别检查 TestFlight、Firebase 符号上传及产物保存步骤。任务完成后用 `gh run view RUN_ID --log` 核对版本、构建号、符号 UUID 与上传成功信息。构建步骤合并了编译、上传和部分 Apple 处理等待，仅凭步骤运行中无法判断当前阶段。
- TestFlight 上传成功后，再检查 App Store Connect 中对应构建的处理状态；`VALID` 表示构建处理成功，不等于已经分发给外部测试者或通过 Beta App Review。项目默认保留手动外部提测流程。
- 若出现 `Sandbox ... deny ... firebase-ios-sdk/Crashlytics/run`，检查 CI 的跳过变量是否传入构建步骤，以及后续同步上传步骤是否保留。不能仅跳过全部符号上传后就认定修复完成。本地归档若遇到同类错误，需要另查脚本输入路径；CI 跳过方案不证明本地归档已验证。
- `latest-stable` 选择的是当前 runner 镜像可用的 Xcode，不保证是 Apple 最新版本。收到 SDK 版本警告时，核对实际 `xcodebuild -version`、邮件中的 SDK 与生效日期，再决定升级 runner 和 Xcode；打包 SDK 与 App 最低系统版本是不同设置。

已完成的 CI 实测和构建标识维护在 `docs/crash-reporting.md`，不要把历史成功记录当成新一次构建的结果。

## 自动崩溃上报验证

符号上传成功不代表运行时崩溃上报已验证。主 App 自动收集，崩溃报告通常在下次启动时发送；日志页没有手动上传按钮。单测宿主不初始化 Firebase。

需要端到端验证时，按 `docs/crash-reporting.md` 的步骤在脱离调试器的测试构建中触发崩溃并重启，核对后台对应版本的事件及可读堆栈。临时触发代码不得进入正式发布包；无法观察后台结果时明确报告未验证。

## 补传缺失符号

官方 MCP 当前没有直接上传 dSYM 的工具，使用 SDK 自带的命令。优先取原始 Actions 产物或原始 `.xcarchive/dSYMs`；不要用重新编译的新包代替旧包符号。

解压 dSYM 压缩包后核对 Firebase 所缺 UUID：

```sh
xcrun dwarfdump --uuid /path/to/nodeseek.app.dSYM
```

UUID 必须对应；仅版本号相同不够。Debug 构建可能还有 `.debug.dylib` 的 UUID。上传可直接接受 dSYM、包含 dSYM 的目录或 zip：

```sh
.build/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols \
  -gsp nodeseek/Resources/GoogleService-Info.plist \
  -p ios /path/to/nodeseek.app.dSYM.zip
```

自定义依赖目录时使用该次构建实际 checkout 内的工具。缺失工具先解析项目锁定的依赖，不另下载未知版本的上传程序。上传失败保留错误和产物，修正原因后重试，避免无限重试或为补传而触发整个发版流程。

分别报告：命令上传成功、后台缺符号状态消失、报告出现可读函数及源码行。这三项不等价；没有后台证据时不能声称符号化完成。

官方参考：[Apple 平台 dSYM 上传](https://firebase.google.com/docs/crashlytics/ios/get-deobfuscated-reports)。
