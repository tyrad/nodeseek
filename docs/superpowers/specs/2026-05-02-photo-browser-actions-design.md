# 图片浏览器非循环与原图操作设计

## 目标

详情页图片浏览器需要调整两点：

- 左右滑动不再无限循环，滑到首图或末图后停止。
- 当前图片支持分享图片本身和保存到系统相册，并尽量保留原始图片格式。

本次只改图片浏览器行为和操作入口，不调整详情页富文本渲染、图片列表解析、缩略图缓存策略或第三方库源码。

## 当前上下文

详情页通过 `PostDetailViewController.presentPhotoBrowser(imageURLs:initialIndex:)` 创建 `DetailPhotoBrowserPresenter`，再由 presenter 创建 `JXPhotoBrowserViewController`。

当前 presenter 已做的事：

- 设置初始图片索引。
- 使用 fade 转场。
- 添加 `JXPageIndicatorOverlay` 页码。
- 使用 `DetailImageLoader.loadImageForPreview` 加载预览图片。

`JXPhotoBrowserViewController` 已暴露 `isLoopingEnabled`，默认值是 `true`。它也支持 `addOverlay(_:)`，业务可以添加自定义浮层控件。

`DetailImageLoader` 内部已有原始图片数据获取和磁盘缓存能力，但目前公开给图片浏览器的接口只返回解码后的 `UIImage?`，不适合满足“原始格式”分享/保存。

## 方案

推荐采用一个右下角“更多”浮层按钮，点击后弹出系统 action sheet：

- 分享图片
- 保存到相册
- 取消

浏览器仍保留底部页码，不新增两个常驻操作按钮。这样能降低遮挡图片的概率，也符合 iOS 对次级操作的常见呈现方式。

### 非循环滑动

在 `DetailPhotoBrowserPresenter.present(from:initialIndex:)` 创建浏览器后设置：

```swift
browser.isLoopingEnabled = false
```

这利用 JXPhotoBrowser 现有能力，不需要改第三方库。

### 原图数据接口

给 `DetailImageLoader` 增加一个公开接口，用于返回原始图片数据：

```swift
struct DetailOriginalImagePayload {
    let data: Data
    let mimeType: String?
    let suggestedFileExtension: String
}
```

接口内部复用现有 `fetchOriginalData(for:)`，保持当前请求头、Cookie、缓存、HTML 内容校验和兜底逻辑一致。

扩展名推断优先级：

1. URL path extension。
2. MIME type，例如 `image/jpeg`、`image/png`、`image/gif`、`image/webp`。
3. 默认 `jpg`。

如果拿到的是兜底图，不应当当作原图分享或保存，应返回失败结果给 UI 提示。

### 分享图片本身

分享动作流程：

1. 从 `browser.pageIndex` 读取当前图片 URL。
2. 通过 `DetailImageLoader` 加载原始图片数据。
3. 将数据写入 app temporary directory 下的临时文件，例如 `nodeseek-image-<index>.<ext>`。
4. 用 `UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)` 分享文件。
5. iPad 场景将 popover source 指向右下角“更多”按钮，避免崩溃。

临时文件只作为系统分享面板输入，不进入图片缓存目录。

### 保存到相册

保存动作流程：

1. 加载当前图片原始数据。
2. 使用 PhotoKit `PHPhotoLibrary.performChanges` 创建 asset。
3. 通过 `PHAssetCreationRequest.addResource(with:data:options:)` 写入原始数据。
4. 成功后 toast “已保存到相册”，失败则 toast “保存失败”。

需要新增 `NSPhotoLibraryAddUsageDescription`：

```text
保存图片到系统相册
```

保存动作只请求添加权限，不需要读取用户相册。

### 浮层 UI

新增一个遵循 `JXPhotoBrowserOverlay` 的视图，例如 `DetailPhotoActionOverlay`：

- 右下角固定在 safe area 内。
- 单个圆形按钮，图标使用 `ellipsis.circle` 或 `square.and.arrow.up` 风格的系统符号。
- 点击按钮将事件回调给 `DetailPhotoBrowserPresenter`。
- overlay 只负责 UI 和当前 browser 引用，不直接处理图片下载和相册写入。

Presenter 负责操作编排，避免把业务逻辑放入 view。

## 错误处理

- 图片 URL 越界：不展示操作或直接提示“当前图片无效”。
- 原图加载失败：提示“图片加载失败，暂时无法操作”。
- 临时文件写入失败：提示“分享失败”。
- 用户拒绝相册权限或系统保存失败：提示“保存失败”。
- 操作进行中可以禁用菜单项或显示轻量加载状态，避免重复点击触发多次下载。

## 测试与验证

代码层验证：

- Xcode 构建通过。
- 如新增可测试的扩展名推断逻辑，应补窄范围单测。

手动验证：

- 打开包含多张图片的详情页。
- 点击第一张图片进入浏览器，左滑到末图后不能继续循环到首图。
- 从末图右滑可以回到上一张，首图不能循环到末图。
- 页码仍显示正确。
- 右下角“更多”按钮可以弹出操作菜单。
- 分享当前图片时，分享面板拿到的是当前页图片文件而不是帖子链接。
- 保存图片时触发系统相册添加权限；允许后图片出现在相册中。
- WebP/GIF 等格式尽量以原始文件数据分享和保存，不退化为预览静态图。

## 风险

- 部分系统版本或相册实现对 WebP/GIF 原始数据写入支持可能不一致，需要以真机手测结果为准。
- 原图文件较大时，首次点击分享或保存会等待下载；需要避免 UI 看起来无响应。
- 右下角按钮可能遮挡极少数图片内容，但单按钮方案遮挡范围可控。
