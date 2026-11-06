# 资源导出面板 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在检查器提供有范围、格式、倍率和尺寸预览的 PNG/PDF 导出，保持画布渲染语义与文档安全。

**Architecture:** 导出规划创建不可变的 `ExportSnapshot`（page/bounds/name），过滤选择但保留必要祖先变换/裁剪/透明度；统一 Exporter 校验并输出。会话保存临时导出选项，SwiftUI 面板通过 AppController 的共享导出动作打开原生 SavePanel。

**Tech Stack:** Swift 6、AppKit/SwiftUI、Swift Testing；macOS 15+。

## Global Constraints

- macOS 15+，Swift 6，无新增依赖，不改变 `.opensketch` v1。
- 使用当前 feat/native-prototype checkout；仅范围明确的中文 `git commit -s`；不推送、不安装系统目录、不触碰用户文档。
- 亮色参考 Sketch、暗色保持 Compositor 中性灰；保留现有 AX 标识和右侧 260 pt 宽度。
- 测试使用离屏原生窗口，不启动/激活用户应用或注入 GUI 输入；实际 GUI 由 controller 执行。
- 有意义地验证输出行为与像素，不为纯布局写镜像实现测试；同一代码的已通过测试不无故重复。

### Task 1: 导出快照、选择语义与 PNG 倍率

**Files:** 新增 `Sources/OpenSketchUI/ExportSnapshot.swift`；修改 `Sources/OpenSketchUI/Exporter.swift`；新增 `Tests/OpenSketchUITests/ExportTests.swift`。如职责需要可将选项定义单独置于 `ExportOptions.swift`。

**Interfaces:** 新增 `enum ExportFormat: String, CaseIterable { case png, pdf }`、`enum ExportScope: String, CaseIterable { case selection, page }`、`struct ExportOptions: Equatable`（format 默认 png、scope 默认 selection、scale 默认1，PNG UI 倍率仅1/2/3）。提供 `ExportSnapshot.make(page: DesignPage, selection: Set<UUID>, scope: ExportScope) throws -> ExportSnapshot`，snapshot 持有渲染 page、bounds、name；空 selection 在 options 消费层解析为 .page，不在显式 .selection 的 make 中静默回退。提供 `Exporter.png(page:bounds:scale:)`，scale 默认1以兼容现有调用；预览与输出共享像素尺寸验证。为 Task2 提供单文件安全命名 API，行为见下。

- [x] 先写失败测试，覆盖实际 PNG 解码像素/尺寸和 PDF mediaBox：2× 的有色 20×10 矩形应得40×20；非零坐标、小数尺寸和三个倍率保持内容方向与边缘；不将“能输出数据”作为唯一断言。
  ```swift
  let data = try Exporter.png(page: page, bounds: CGRect(x: 10, y: 20, width: 20, height: 10), scale: 2)
  let image = try #require(NSBitmapImageRep(data: data))
  #expect(image.pixelsWide == 40 && image.pixelsHigh == 20)
  ```
- [x] 实现选中单画板独立导出：原点归零、旋转归零、clipsContent=true、精确自身 bounds，保留整个子树，拒绝隐藏祖先下的画板。普通选择构建裁剪后的渲染树：选中子树原样保留；必要祖先保留变换/clip/opacity但移除自身fill/stroke；排除兄弟；bounds 仅累计选中子树几何并应用祖先裁剪。父子同选去重，锁定仍可导出。页面范围使用现有可见内容 bounds/空页尺寸。无效或完全不可见的显式选择抛出易读错误。
- [x] 通过独立像素点和 bounds 验证嵌套旋转/父透明度/裁剪、未选兄弟和祖先背景排除、组尺寸、单画板规范化、选择多层合并与去重、锁定/隐藏/跨页未知ID/完全裁剪；确保输入模型值未改。
- [x] PNG 把倍率应用到 CGContext 与实际 bitmap 像素尺寸，ceil 后检查16,384边长及64,000,000像素，在 Int 转换/分配前拒绝NaN/Inf、负或零尺寸/倍率与越界origin。PDF继续1×矢量及原尺寸上限。共享尺寸预览 API 不分配图像。测试小倍率边界及超限，不为边界测试分配巨大bitmap。
- [x] 默认文件名：单层名称、页面名称或“选中图层”，替换 /、\\、: 与控制字符，去掉首尾空白，空值用“设计”，basename UTF-8不超过200字节，PNG非1×加@2x/@3x后缀、PDF无倍率后缀。测试分隔符、空名、Unicode和长名称。
- [x] 运行 `swift test --filter 'ExportTests|IntegrationTests'` 及 `git diff --check`，中文 signed commit；报告可供Task2调用的实际 API 名称/签名及结果。完整suite/Release留给Task2集成完成后。

### Task 2: 右侧导出分区与共享原生导出动作

**Files:** 新增 `Sources/OpenSketchUI/InspectorExportView.swift`；修改 `InspectorView.swift`, `EditorRootView.swift`, `EditorSession.swift`, `AppController.swift`, `AppController+Documents.swift`（导出可拆到 `AppController+Export.swift`）；新增 `Tests/OpenSketchUITests/ExportIntegrationTests.swift`，按需更新工作区测试。

**Interfaces:** 消费Task1的 ExportOptions/ExportSnapshot/Exporter 尺寸与输出 API；EditorSession 增加独立会话导出设置，UI默认scope selection，但无选择时有效scope page；格式默认PNG、倍率1。root通过明确回调把面板动作路由到当前 AppController；不能覆盖 Canvas/Inspector finishInput 协调器。

- [x] 先写行为测试：两个文档设置隔离、无选择解析page、显式page不因选中对象改回selection、锁定可导出但hidden无效、PNG倍率/PDF固定1×、不增加dirty/undo。
  ```swift
  // Change first session's export options; switch workspace and assert defaults.
  // Export after native inspector/Canvas pending input; inspect file geometry.
  // chooseDestination switches document and mutates selection: output stays original snapshot.
  // Cancel returns nil: no file, no URL/history change except finishing prior input.
  ```
- [x] 在现有检查器末尾增加“导出”分区，范围picker“当前选择/当前页面”、格式picker“PNG/PDF”、PNG倍率picker“1×/2×/3×”、尺寸文本与“导出…”按钮；PDF隐藏或禁用倍率并明确显示1×点尺寸。无选择时selection选项不可用、显示page；有错误时显示短原因并禁用按钮。AX IDs使用 export.scope / export.format / export.scale / export.dimensions / export.action / export.error。锁定图层导出分区必须在编辑属性 disabled 边界之外。尺寸预览不渲染位图。
- [x] 统一 AppController 导出动作：捕获发起文档，完成原生/Canvas/Inspector输入，创建不可变 snapshot 和已校验输出选项，再打开 NSSavePanel；默认文件名与允许格式正确；SavePanel取消不写文件，错误通过既有alert；原子写入，成功session.message包含实际文件名。文件菜单PNG/PDF复用动作，强制格式但保留当前文档的scope/PNG倍率。
- [x] 验证选择层/页面切换预览、窗口/文档切换时路由、面板期间修改内容后快照不变、实际文件PNG像素与PDF页框，旧文件菜单测试继续通过；通过native离屏编辑器测试导出前提交数值和Canvas文字。
- [x] 运行新集成及受影响测试，最终一次 `swift test`、`swift build -c release`、`git diff --check`；中文 signed commit，报告准确计数/日志/GUI入口。

### Task 3: 原生导出验收与文档（controller）

- [x] 保存用户最新设计，构建签名app并正常重启；使用独立样例从检查器分别导出2×PNG和PDF，用解码器核对像素、页框与文件内容，检查当前选择/页面切换与取消。
- [x] 核对亮/暗导出区布局及不被锁定属性禁用，重开/保留用户最新文件。完成源码审查与 scoped fix复核，更新README、验收记录和历史能力矩阵状态说明；记录真实GUI与原生测试的边界。
- [x] 范围明确的本地signed提交，工作树干净，清理本计划scratch，保留其他计划和用户数据。
