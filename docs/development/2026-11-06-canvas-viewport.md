# 画布视口裁剪修复

日期：2026-11-06。代码基线：`3e80600`。

## 问题与修复

实际窗口复现了平移后画板填充和选择轮廓越过中间编辑区、覆盖左侧图层列表的问题。`EditorRootView` 已为 `CanvasHost` 分配中间区域，但 `CanvasView` 未启用原生视图边界裁剪；`draw(_:)` 将文档按平移/缩放变换绘制，越界内容因此能够覆盖相邻面板。

在 `CanvasView.init(session:)` 设置 `clipsToBounds = true`，使自身绘制和行内 `NSTextView` 子视图统一受画布视口限制。保持文档几何坐标、平移/缩放算法、图层内容裁剪设置和导出行为不变。

[Apple 的 NSView 文档](https://developer.apple.com/documentation/appkit/nsview/clipstobounds)说明该属性同时约束自身和子视图，当前默认值为 false；本机 SDK 头文件也注明 macOS 14 起默认关闭。Compositor 的 `EditorCanvas` 同样显式开启此属性。

## 验证

新增 `CanvasViewportTests.pannedContentStaysInsideViewport`，通过 AppKit 对整个父视图生成位图，避免捕获区域本身掩盖越界绘制。测试包含画板/行内文字、100%/200% 缩放四种组合，以及两种视口尺寸；检查中间内容仍然可见、上下左右外部像素保持背景、文档内容与脏状态不变。

- 原实现：四种组合的外部像素检查共 32 处失败，实际为越界内容的白色。
- 开启裁剪后：上述检查全部通过。
- `swift test`：UI 69、核心 24，共 93 项测试通过，无编译警告或错误。
- `scripts/build.sh release`：构建通过（8.59 秒）。严格签名、Info.plist 和 `git diff --check` 通过。
- 新 Release 实际窗口：原画板放大到 259% 后同时超出四边，黄色填充在中间编辑区边界截断，左右面板、顶部工具区及底部状态栏保持完整；上下滚动后边缘裁剪正常。
- 验收结束恢复页面 2、选中原画板并执行“适合”。本次没有单独验收横向触控板手势；四边绘制边界已由像素测试与放大窗口检查覆盖。

## 设计文档保留

更新应用前发现用户将画板改为黄色且尚未保存，已通过原生“另存为”保留至：

`research/local/preserved-before-viewport-20261106.opensketch`

更新后重新打开该文档并恢复页面 2。其 `document.json` SHA-256 为 `c56bcd89f1a6b3e415b9f49677ecf52829e1b4adec182b1c9ae56958b0418c26`；GUI 验收只改变视口与选择，保存文件校验值保持一致。

本次仅更新仓库内 `build/openSketch.app`，未安装到 `/Applications` 或推送远程。
