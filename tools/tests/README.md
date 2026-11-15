# 提交脚本离线验证

在仓库根目录运行：

```sh
node tools/tests/action-response-scripts.cjs
node tools/tests/comment-submission-script.cjs
python3 tools/tests/submission-errors.py
```

JS 测试直接读取生产 Swift 文件中的脚本，在独立的 Node VM 中执行。
VM 只注入模拟的 fetch、DOM 和编辑器，不提供真实网络客户端或 require。
不会访问 NodeSeek，也不会发送评论、点赞或收藏请求。

覆盖成功、业务失败、异常 JSON、缺失成功标志、请求超时、网络异常、
迟到响应不覆盖超时结果、不自动重试、发帖正文读取超时及异常投票数据。
评论测试还覆盖编辑器 API 填入验证和提交次数。

Swift 独立验证提取生产错误类型及发帖结果映射，不启动 App。
App-hosted 回归用例另保存在 NodeSeekCommentSubmitterTests 和
NewDiscussionPresenterTests，覆盖提示映射、保留草稿及禁止直接重试。
本轮只用 make xcode-build-tests 编译这些用例：
启动测试宿主会触发 App 联网预热，不符合本轮完全离线执行的约束。
