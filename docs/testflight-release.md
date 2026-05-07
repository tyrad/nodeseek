# TestFlight Release

本项目的 TestFlight 包应从公开 GitHub Actions workflow 构建并上传，避免本地私有构建成为唯一来源。

## GitHub Secrets

在仓库或 `app-store` environment 中配置：

- `APP_STORE_CONNECT_TEAM_ID`
- `APPLE_TEAM_ID`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_KEY_CONTENT`
- `APPLE_ID`
- `FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD`
- `MATCH_GIT_URL`
- `MATCH_PASSWORD`
- `MATCH_GIT_PRIVATE_KEY`

上传 TestFlight 推荐使用 App Store Connect API key：`APP_STORE_CONNECT_KEY_ID`、`APP_STORE_CONNECT_ISSUER_ID`、`APP_STORE_CONNECT_KEY_CONTENT`。如果暂时没有 API key，也可以使用 `APPLE_ID` 加 `FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD` 先上传 build；这种模式不会自动等待处理或分发外部测试组。`MATCH_GIT_PRIVATE_KEY` 使用 match 私有仓库的只读 deploy key。

## GitHub Variables

`app-store` environment 可以配置这些 variables：

- `TESTFLIGHT_GROUPS`：外部测试组，默认空。多个组用英文逗号分隔。
- `APP_IDENTIFIER`：Bundle identifier，默认可由 workflow 设置为维护者自己的 bundle id。
- `APP_STORE_CONNECT_APP_ID`：App Store Connect app id。
- `TESTFLIGHT_CHANGELOG`：TestFlight 的 What to Test 文案。
- `TESTFLIGHT_DISTRIBUTE_EXTERNAL`：是否自动分发到外部测试组，默认 `false`。
- `TESTFLIGHT_SUBMIT_BETA_REVIEW`：是否自动提交 Beta App Review，默认 `false`。
- `TESTFLIGHT_NOTIFY_EXTERNAL_TESTERS`：是否通知外部测试者，默认 `false`。
- `TESTFLIGHT_USES_NON_EXEMPT_ENCRYPTION`：出口合规选项，默认 `false`。如果应用使用非豁免加密，需要改成 `true`。
- `TESTFLIGHT_PUBLIC_LINK`：公开 TestFlight 链接，创建后记录在这里，便于 README 或 release note 引用。

默认策略是：workflow 只上传 TestFlight build，不自动分发到外部测试组，也不自动提交 Beta App Review。`Public Beta` 提测最后一步由维护者在 App Store Connect 手动完成。

如果未来确认要全自动外部分发，再同时设置：

- `TESTFLIGHT_GROUPS=Public Beta`
- `TESTFLIGHT_DISTRIBUTE_EXTERNAL=true`
- `TESTFLIGHT_SUBMIT_BETA_REVIEW=true`

## 发布流程

1. 确认证书和 profile 已经通过 `fastlane match appstore` 写入私有 match 仓库。
2. 在 GitHub 创建 `app-store` environment，并开启人工审批。
3. 确认 App Store Connect 中已经创建外部测试组 `Public Beta`，并按需开启 Public Link。
4. 打 tag 触发发布：

```bash
git tag ios/v1.0.0
git push origin ios/v1.0.0
```

5. workflow 会校验 tag 指向 `main` 历史中的 commit，版本号从 tag 解析，build number 使用 GitHub run number。
6. workflow 会构建并上传 TestFlight。Simulator 测试不在发布 workflow 中执行，避免公开发布链路等待过久；需要时可本地或单独 CI 执行 `fastlane tests`。
7. 上传成功后，workflow summary 会生成可复制的 Public Beta 测试信息。
8. 维护者进入 App Store Connect，选择这个 build，确认测试信息并手动提交 Beta App Review。
9. 构建会把 GitHub run 信息写入 `Info.plist`，并上传 `build/build-provenance.json` artifact。

手动触发 `TestFlight` workflow 仍然可用，需要输入 version 和 build number，适合补发或调试。

## Public Beta 前置条件

自动分发到 Public Beta 之前，App Store Connect 里需要先完成一次性配置：

1. 创建 External Testing Group：`Public Beta`。
2. 开启该 group 的 Public Link，并把链接记录到 `TESTFLIGHT_PUBLIC_LINK`。
3. 填写 Beta App Review 信息、反馈邮箱、测试说明和隐私相关信息。
4. 第一次外部测试 build 需要通过 Apple Beta App Review。通过后，后续构建可以自动分发到同一个公开测试组。

推荐测试信息：

**Beta App Description**

```text
NS Connect is an unofficial third-party iOS client for NodeSeek. It helps users browse discussions, view post details, sign in with their own NodeSeek account, and interact with forum content in a native mobile interface.
```

**What to Test**

```text
Please test browsing discussion lists, opening post details, signing in with a NodeSeek account, replying to posts, loading images, viewing user information, and general navigation stability.
```

**Review Notes**

```text
NS Connect is an unofficial third-party client for NodeSeek and is not affiliated with, sponsored by, or endorsed by NodeSeek.

The app accesses publicly available NodeSeek web content and user-authorized account sessions. Users sign in with their own NodeSeek account through the website login flow.
```

## 本地验证

```bash
bundle install
bundle exec fastlane tests
```

本地执行 `fastlane build` 或 `fastlane beta` 需要可用的 Apple 签名配置和 match secrets。
