# 缩放与检查器优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 完成缩放控件反馈优化与 Sketch 风格的可拖动参数检查器。

**Architecture:** 保持 AppKit 画布 / 工具栏和 SwiftUI 侧栏结构。缩放继续从当前 DocumentWorkspace 会话读取；数值控件由原生事件处理驱动会话级事务，直接输入和拖动共享属性定义。

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, macOS 15+。

## Global Constraints

- macOS 15+，Swift 6，不新增外部依赖。
- 当前 feature checkout 工作；保留其他改动与用户文档；仅范围明确的 `git commit -s` 中文本地提交，不推送、不安装 `/Applications`。
- 亮色参考 Sketch，暗色沿用 Compositor 中性配色；画布与两侧栏隔离不变。
- 保留现有 AX 标识和文档格式、撤销语义；禁止 GUI 注入脚本及测试期间抢占用户窗口。测试原生控件使用屏幕外窗口。
- 验证命令与结果写入报告；同一代码已通过的测试不无故重复。

### Task 1: 紧凑缩放菜单与比例反馈

**Files:** `Sources/OpenSketchUI/ZoomControlView.swift`, `Sources/OpenSketchUI/AppController.swift`, `Sources/OpenSketchUI/EditorRootView.swift`（比例取整）, `Tests/OpenSketchUITests/OrganizationControlsTests.swift`, `Tests/OpenSketchUITests/WorkspaceIntegrationTests.swift`。

**Interfaces:** 消费 `workspace.current.session.zoom`, `setZoom(_:)`, `fitCanvas`, `zoomCanvas`；工具栏统一显示当前会话倍率。仅修改缩放相关文件，后续检查器任务不依赖新的缩放 API。

- [x] 为 96 pt 滑条、常显百分比下拉按钮、当前文档菜单路由及外部放大缩小同步增加有意义的测试，先运行观察失败。
  ```swift
  let workspace = DocumentWorkspace()
  // Host the toolbar control offscreen; find the actual NSSlider/menu control.
  // Assert slider.frame.width == 96; apply zoomIn/zoomOut/current-document switch,
  // then inspect native percentage label and invoke menu items' target/action.
  ```
- [x] 将滑条宽度设为 96 pt；增加常显整数百分比与下拉箭头，菜单提供“适合画布”“实际尺寸（100%）”、25/50/100/200/400/800%。原独立适合按钮并入菜单。现有 view.zoomSlider / view.zoomIn / view.zoomOut AX 标识保留，菜单新标识 view.zoomMenu。保留拖动悬浮框，比例按钮本身为点击图标后的即时反馈。
  ```swift
  // Menu commands resolve workspace.current.session at activation time.
  workspace.current.session.fitCanvas?()
  workspace.current.session.setZoom(1)
  ```
- [x] 验证倍率夹紧 0.05...8、中心锚点、即时往返同步、切换文档、无 dirty/undo，并核对最小 980 pt 窗口工具栏预算；更新原工具栏测试。
- [x] 所有比例显示统一四舍五入到整数，修正实窗约 29.8% 时滑条 30%、底栏 29% 的差异。
- [x] 运行 `swift test --filter OrganizationControlsTests` 和 `swift test --filter WorkspaceIntegrationTests`，`git diff --check`；提交并写报告（代码、测试证据、GUI 待验边界）。

### Task 2: 检查器布局与数值拖动事务

**Files:** 重写 `Sources/OpenSketchUI/InspectorView.swift`；新建 `InspectorNumberField.swift`, `EditorSession+Inspector.swift`（可按清晰职责细分）；按需修改 `LayerActionsView.swift`, `EditorPalette.swift`, `EditorSession.swift` 及输入结束调用点；新增 `Tests/OpenSketchUITests/InspectorEditingTests.swift`。

**Interfaces:** 消费 `EditorSession.document`, `history`, `selection`, `pageID`, `editable`, `finishInput` 及现有 Canvas 输入收尾协议；提供字段共享校验与原生数值拖动控件。不得用 Inspector 覆盖 Canvas 的 finishInput 闭包；协调收尾使保存/撤销/切文档均可靠结束数值事务。

- [x] 先写行为测试：X/Y、宽高、旋转、透明度、线宽、圆角、字号的范围/有限数校验；默认、Shift、Option 相对拖动；多次更新一次撤销；重做；Escape；回到起点无历史；锁定/隐藏；选择/页面/文档切换、失焦、保存和撤销中断。
  ```swift
  // For a rectangle at x=20, begin a numeric edit, update translation 10 then 25.
  // Assert live x=45; commit; one undo restores 20; redo restores 45.
  // Begin again and cancel after update; document/history equal the prior state.
  // Switch selection during tracking; subsequent events must not mutate either node.
  ```
- [x] 增加可共享的数值属性定义（读取/范围/写入），不新增模型字段。透明度显示 0...100%，写入 style.opacity 的 0...1。所有可编辑数值直接输入与拖动走同一验证；组宽高继续只读。
- [x] 增加原生数值控件：可选择/编辑文本，标签区域水平拖动，悬停提示和水平调整指针；3 pt 阈值，1/10/0.1 单位每点，对开始值累计，松开提交一次，Escape 取消。提供稳定 AX 字段 ID inspector.x/y/width/height/rotation/opacity/strokeWidth/cornerRadius/fontSize；标签可新增 .scrub ID。
- [x] 接入编辑生命周期：提交画布现有输入后开始参数拖动；保存/撤销/选择/页面/文档变化/窗口失焦/视图脱离时结束且不串文档；保持文本编辑器正常快捷键。不得用 `session.update` 在每个 drag event 创建撤销步骤。
- [x] 重排 260 pt 检查器：名称、精简对齐分布、X/Y 双列、布局宽高双列、旋转、样式透明度/圆角、填充/边框、按需文字；紧凑灰色圆角控件、较清晰分区间距，亮暗系统外观均适配。保留现有编组/层级与裁剪颜色文字编辑；不添加尚不可用的约束/阴影/效果/导出占位控件。
- [x] 运行新增测试与受影响工作区/精确编辑测试，再完整 `swift test`、`swift build -c release` 和 `git diff --check`；完成中文 signed scoped commit。报告完整测试数量、日志与必要 GUI 交互入口。

### Task 3: 集成验收与文档（controller）

- [x] 真实应用保存用户当前文档；打包并验证签名/Info.plist，正常退出并启动新 build/openSketch.app。
- [x] 使用原生 UI 验收缩放菜单、比例反馈、短滑条，以及检查器亮/暗布局、直接输入、拖动、撤销与颜色/文字基本控件；用测试文档保留用户已有内容。
- [x] 更新 README/开发记录与本计划结果，清晰记录自动化及 GUI 已验/未验边界，提交；收尾代码审查并保持工作树干净。
