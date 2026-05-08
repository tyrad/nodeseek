---
name: ios-device-install
description: Use when the user asks to install the iOS app onto a real iPhone (e.g. "打包安装到手机", "装到真机", "安装到 iPhone"), and needs either direct device install or an OTA link via Tailscale.
---

# iOS Device Install (Real Device)

这个 skill 用于“把当前项目安装到真机 iPhone”，并且在两种路径之间做选择：

1. **直接安装（推荐，前提是 Mac 能识别真机）**：用项目脚本 `./run-local-device-fast.sh`（build + install + launch）。
2. **链接手动安装（OTA，适用于只想安装、或真机无法被 Xcode 识别）**：导出 `.ipa`，通过 Tailscale HTTPS 给 iPhone 一个 Safari 安装链接。

## 必须先问的一句话

当用户只说“打包安装到手机/真机安装”但没说方式时，必须先问：

“你想用哪种方式安装：`直接安装` 还是 `链接手动安装（Tailscale OTA）`？”

不要擅自选择。

## 选择规则

- 用户提到“用 Tail/Tailscale/链接/手动安装”：走 **链接手动安装（OTA）**。
- 用户说“直接装/直接安装/装到手机并启动”：优先尝试 **直接安装**。
- 如果用户选择直接安装，但 `xcodebuild -showdestinations` 里没有具体真机 UDID（只有 `Any iOS Device`），说明真机链路没通：
  - 解释原因（信任/Developer Mode/USB 配对/同网段 Wi‑Fi 无线调试等）。
  - 建议改用 **链接手动安装（OTA）**。

## 直接安装（真机已可用）

优先使用仓库已有脚本（它处理了 destination/安装/启动）：

```bash
./run-local-device-fast.sh
```

可选：如果需要看启动日志：

```bash
CONSOLE=1 ./run-local-device-fast.sh
```

## 链接手动安装（Tailscale OTA）

运行脚本：

```bash
bash skills/ios-device-install/scripts/prepare-ota-install.sh
```

脚本会：

1. `xcodebuild archive` 生成 `.xcarchive`
2. `xcodebuild -exportArchive` 导出 `.ipa`
3. 生成 `manifest.xml` 和 `index.html`（点击即可安装）
4. 在本机起一个 `http.server`（仅绑定 127.0.0.1）
5. 用 `tailscale serve` 把 HTTPS 暴露给 tailnet
6. 打印最终安装链接（在 iPhone Safari 打开）

### 常见失败与处理

- iPhone 提示“无法安装/无法验证”：
  - 通常是 provisioning profile 没包含该 iPhone 的 UDID（development/调试包要求设备已注册）。
  - 需要把设备加到 Apple Developer / 重新签名再导出。
- 链接能打开但下载失败：
  - 检查 iPhone 是否已连接 Tailscale
  - 检查 `tailscale serve status`
