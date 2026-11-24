# AGENTS.md

## 0. 项目介绍
- 项目背景、目录边界、验证命令和开发约定详见 `docs/project-overview.md`。
- 遇到目录边界、验证命令或项目结构不明确时，按需阅读该文件的相关章节。

## 1. 交流与文档规则
- 交流优先使用中文。
- 代码、标识符、提交信息、技术文档可按场景使用英文。
- 注释偏向中文，并强调减少中英混杂。

## 2. 工作方式
- 用户单独发送 `adhoc` 时，直接按 [NodeSeek IPA 内测技能](.agents/skills/nodeseek-ipa-beta/SKILL.md) 打包并上传当前工作区，成功后只回复安装链接。
- 面对复杂任务，先理解、分解、规划，再动手。
- 不要未经准备就大范围同时改动多个模块。
- 强调 "Slow as Fast" 的做事方式。

## 3. 核心原则
- 证据优先：先看日志、复现步骤和上下文，不凭猜测改代码。
- 一次只处理一个主要问题，避免同时引入过多变量。
- 最小修改优先：能局部修，就不要扩大成重构。
- 高风险操作前要先同步影响，再执行。

## 4. UI 开发
- UI 开发必须考虑暗黑模式。
- 优先使用 UIKit/SwiftUI 的系统动态颜色，例如 `.systemBackground`、`.secondarySystemBackground`、`.label`、`.secondaryLabel`、`.separator`。
- 避免在界面代码里直接写固定的黑白色或硬编码 RGB 颜色，除非确实是品牌色、状态色或业务语义色。
- 如果系统颜色无法满足设计需要，应优先在 Assets 中定义支持 Light/Dark variants 的自定义颜色，再在代码中引用。
- 新版本功能介绍页的内容与样式约束见 `docs/project-overview.md` 的「8. 新功能介绍页」。

### 键盘与输入
- 新增或修改输入页面时，明确键盘出现后的可见区域、输入框切换、提交与收起方式；必要时使用 keyboardLayoutGuide，避免键盘遮挡当前输入和主要操作。
- 点击空白收起键盘应由页面主动接入 KeyboardDismissCoordinator，显式指定背景白名单；仅背景本身响应，不自动包含子视图。禁止向 Window 全局安装收起手势。
- 输入框、正文编辑区域（包括内部空白）、可选文本、链接、按钮、列表项和 WebView 不应被空白手势拦截。保留页面已有编辑与滚动行为，尊重结束编辑校验，不用强制结束编辑掩盖冲突。
- 系统输入弹窗及网页输入保留各自行为。验证输入框切换、中文输入法组合文字、选字、按钮单次点击、滚动和键盘遮挡。

- 状态视图、空态视图（如 tableView.backgroundView）需单独登记背景，替换时移除旧登记；验证无结果和出错状态下空白可收起，重试按钮正常。不遍历 WebView 内部输入控件。

### 动态字号
- 文本优先复用 AppTypography 和项目字号设置；系统 Dynamic Type 使用语义字体或 UIFontMetrics，并按控件需要启用 adjustsFontForContentSizeCategory。避免重复缩放。
- 字号变化后同步刷新字体和布局，避免固定高度导致大字号截断、重叠或按钮不可点；必要时允许换行和滚动。
- 新增或修改文本布局时，验证默认字号、大字号及系统辅助功能字号，兼顾应用内字号设置；图标与点击区域不得随文字缩小到不可用。

### 多语言
- 新增用户可见文案必须使用项目既有本地化资源与模块约定，补齐项目支持的语言；包含占位符、错误提示、菜单和无障碍标签。
- 避免拼接完整句子；变量使用本地化格式占位符，复数使用相应本地化规则，日期和数字使用区域格式化。
- 布局不依赖中文长度，优先使用 leading/trailing 与自然文本对齐；验证较长译文、换行及适用的从右到左布局，技术地址等内容按语义保留方向。

## 5. 复杂任务处理
- 简单改动可直接做。
- 中等或复杂任务应先进入计划模式，明确目标、约束、方案、风险、影响范围与验证方式。
- 需求不清时先提问，不要硬猜。

## 6. 输出与编码风格
- 输出应直接、清晰、可执行。
- 编码风格尽量贴近现有项目，不为“好看”而无谓改写。
- 注释只写必要信息，重点解释为什么。
- 未完成就明确说明未完成，不伪装成已完成。

## 7. Git 与提交规范
- 谨慎使用 `git rm`、`git rebase`、`git reset --hard`、`git push --force` 等高风险命令。
- 除非用户明确要求，否则不主动进行此类操作。
- Git 提交信息使用中文，要求清晰、简短、可读，方便 GitHub Release 自动生成升级内容。
- 推荐格式：`type(scope): 中文摘要`，例如 `fix(detail): 降低详情页回帖按钮视觉权重`。
- 常用 `type`：`feat`、`fix`、`ui`、`test`、`build`、`ci`、`docs`、`refactor`、`chore`。
- 中文摘要写具体行为或结果，避免 `更新`、`修复问题`、`杂项改动` 这类模糊描述。
- 一次提交只表达一个主要改动；跨 UI、发布流程、测试的无关改动不要混在同一条 commit 里。
- `main` 分支按「完整功能 / 独立修复」沉淀提交：特性分支开发期可小步提交，合入 `main` 时优先用 `squash merge` 压成 1 条（或按大阶段 2～3 条）完整提交，避免把未上线功能的开发期修补与反复微调带入主线。
- 同一功能或修复配套的单测与文档随代码一起提交，不必强行拆成多条 commit；未推送前的反复试错与已撤回尝试在定稿后合并，只保留最终生效的结果。
- 彼此无关的线上 bugfix，以及纯重构与行为改动仍保持独立提交，便于单独回退与排查回归。

## 8. 自检要求
- 完成前自查语法、依赖、导入、低级错误。
- 涉及编译、测试、类型检查或接口变更时，应尽量做验证并汇报结果。
- 发布前 E2E 用 `make e2e-list` 按功能查编号，再用 `make e2e-case CASE=<编号>` 单跑。账号条件和验收方式见 [NodeSeek E2E 技能](.agents/skills/nodeseek-e2e/SKILL.md)。
- 模拟器测试用 `make xcode-test-class TEST="类名 ..."` 等 make 目标，不要手写 `xcodebuild test`/`test-without-building`，原因见 `docs/project-overview.md`「常用验证命令」。

### 模拟器操作经验
- `make xcode-test-class` 默认用 iPhone 16 / iOS 18.0，本机没有时传 `SIMULATOR_ID=<UDID>`（用 `xcrun simctl list devices available` 查）。
- `TEST` 只接受类名（Makefile 会拒绝 `类名/方法名`），需要看单个方法时按类名跑，再从 `.build/XcodeDerivedData/Logs/Test/` 最新的 `.xcresult` 用 `xcrun xcresulttool get test-results tests --path <路径>` 读失败信息。
- 构建会自动改动 `Package.resolved`（删掉部分 Google 依赖条目），与本次改动无关时还原，不要提交。
- 本机 Xcode 27.2 用 Device Hub 查看模拟器。运行 `open -a /Applications/Xcode.app/Contents/Applications/DeviceHub.app`，在侧栏选中测试使用的设备即可实时观看。用 `axe` 点击时加 `--tap-style physical`，滑动用 `axe swipe`。
- `axe describe-ui` 读不到帖子和评论正文（富文本），只能拿到按钮、楼层号等；点正文需截图（`xcrun simctl io <UDID> screenshot`）后按坐标点，屏幕点数 = 截图像素 ÷ 3。
- 安装最新构建：`make xcode-build-tests` 后 `xcrun simctl install <UDID> .build/XcodeDerivedData/Build/Products/Debug-iphonesimulator/nodeseek.app`。
- make 构建带 `CODE_SIGNING_ALLOWED=NO`，App 没有 Keychain 权限，写入返回 -34018，Key 存不进去。要验证依赖 Keychain 的流程（如保存 NodeImage Key），改用 `xcodebuild build`（不带该参数，另设 `-derivedDataPath .build/SignedSimDerivedData`）让 Xcode 自动签名后安装；用 `codesign` 手动重签的包模拟器会拒绝启动。
- 看 App 日志：`xcrun simctl spawn <UDID> log stream --style compact --predicate 'eventMessage CONTAINS "关键字"'`，可配合临时 `NSLog` 观察网页消息和调用顺序，提交前删除。
