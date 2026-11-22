---
name: nodeseek-ipa-beta
description: 在 NodeSeek 项目中响应 adhoc 口令，打包当前工作区、发布到 iOS Shelf 并返回安装链接。也支持上传已有 IPA 和查询历史构建。
---

# NodeSeek IPA 内测

## 从当前工作区打包并发布

用户单独发送 `adhoc` 即授权本次发布。直接在当前工作区根目录运行下面的脚本，等待上传校验成功后，只回复结果中 `install_page` 的可点击链接。发布失败时说明阻塞原因。

```sh
.agents/skills/nodeseek-ipa-beta/scripts/release.sh
```

脚本先验证 Shelf 授权，再归档 Release，使用本机 Apple Distribution 证书和已安装的 Ad Hoc 描述文件导出 IPA，最后上传并回查。自动签名覆盖仅作用于本次归档；导出时使用项目团队 Z9K94479DQ 的两个描述文件，名称分别为 `Shelf Ad Hoc com.mistj.nodeseek` 和 `Shelf Ad Hoc com.mistj.nodeseek.ProbeWidget`。日志、归档和 IPA 均位于命令打印的 `.build/shelf-release.*` 目录。Shelf 归档跳过 Crashlytics 后台上传，dSYM 保存在归档中。上传阶段中断时，复用该目录中的 IPA 和原构建来源重试。

密钥来自环境变量 `IOS_SHELF_API_KEY`，本机脚本也支持从 `~/.config/ios-shelf/nodeseek.env` 加载，CI 可注入同名 secret。避免在日志和命令参数中记录密钥。

## 发布已有 IPA

直接使用 Python 客户端前，若 shell 尚未注入密钥，运行 `. "$HOME/.config/ios-shelf/nodeseek.env"`。使用本次指定的 NodeSeek Ad Hoc IPA。若产物来源不明，先核对主 App 的 Info.plist、内嵌描述文件和版本。缺少签名材料时报告具体缺项。

```sh
python3 .agents/skills/nodeseek-ipa-beta/scripts/publish.py upload "/path/to/nodeseek.ipa"
```

上传会记录当前 worktree 目录名、分支、提交。发布其他工作区的既有产物时，传入产物实际的 `--worktree`、`--branch` 和 `--commit`；未知的分支或提交传空字符串。发生网络中断时用相同文件和来源信息重试，服务会复用已有记录。

客户端校验 SHA-256，并在该 worktree 的构建列表中回查 ID。上传结果包含版本、构建号、worktree 和 `install_page`。该地址是可收藏的工作区安装页，早期构建位于历史版本中。设备安装结果需在已登记的 iPhone 上验证。

## 查询

```sh
python3 .agents/skills/nodeseek-ipa-beta/scripts/publish.py list
python3 .agents/skills/nodeseek-ipa-beta/scripts/publish.py list --worktree nodeseek
```

HTTP 401 表示服务未接受当前 Key；检查注入的密钥是否有效。API Key 用于上传及查询，测试者通过网页访问密码登录安装页。
