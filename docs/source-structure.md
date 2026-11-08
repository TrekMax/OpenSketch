# 源码结构

源码按职责参考 Compositor 的 `Editor`、`UI`、`Rendering`、`IO` 分组，保留现有 Swift Package target：

```text
OpenSketchApp → OpenSketchUI → OpenSketchCore
```

目录是源码分组，不是独立 Swift 模块。`Package.swift` 自动发现 target 目录下的 Swift 文件；移动文件时保留所属 target、类型名、访问级别和行为。

## OpenSketchCore

核心仅依赖 Foundation 和 CoreGraphics，包含可序列化文档、几何与编辑算法、历史和文件格式。

| 目录 | 文件 | 职责 |
| --- | --- | --- |
| `Editor/Model` | `DocumentModel.swift`、`DocumentOperations.swift` | 文档值、树查询与基础增删改 |
| `Editor/Session` | `DocumentHistory.swift` | 编辑事务、撤销重做与保存快照 |
| `Editor/Canvas` | `CanvasEditing.swift`、`SceneGeometry.swift` | 框选、位移、吸附、变换、命中和路径几何 |
| `Editor/Layers` | `LayerEditing.swift`、`LayerTreeEditing.swift`、`ContainerEditing.swift` | 编组、排序、对齐分布和容器归属 |
| `IO` | `DocumentCodec.swift`、`SketchMetadata.swift` | 原生文档编码、校验和包读写；Sketch 元数据解码 |

## OpenSketchUI

这个 target 同时承担编辑会话、原生应用集成、界面和渲染，因此内部继续按职责分组。

| 目录 | 文件 | 职责 |
| --- | --- | --- |
| `Editor/Session` | `EditorSession.swift`、`EditorSession+Rename.swift`、`EditorError.swift` | 会话状态、跨页面与图层的重命名事务、共享编辑错误 |
| `Editor/Workspace` | `DocumentWorkspace.swift` | 多文档集合、切换和关闭协调 |
| `Editor/Layers` | `EditorSession+Layers.swift`、`EditorSession+LayerDrag.swift`、`EditorSession+Containers.swift`、`EditorSession+Inspector.swift` | 图层命令、拖放、归属和属性编辑事务 |
| `Editor/Tools` | `EditorTool.swift` | 工具标识及现有工具展示信息 |
| `UI/Workspace` | `EditorRootView.swift`、`DocumentTabsView.swift` | 编辑窗口布局和文档标签 |
| `UI/Canvas` | `ZoomControlView.swift` | 缩放控件 |
| `UI/Layers` | `LayersSidebar.swift`、`NativeLayerTree.swift`、`NativeLayerTree+Coordinator.swift`、`LayerTreeItem.swift`、`NativeLayerOutline.swift`、`LayerTreeCell.swift`、`SidebarRenameField.swift`、`InspectorView.swift`、`InspectorNumberField.swift`、`LayerActionsView.swift`、`AppController+Layers.swift` | 页面与图层侧栏、原生树、检查器和图层菜单 |
| `UI/ImportExport` | `InspectorExportView.swift` | 导出选项和尺寸预览 |
| `UI/Settings` | `AppAppearance.swift`、`ApplicationSettingsView.swift`、`SettingsWindowController.swift`、`AppController+Settings.swift` | 外观偏好、通用设置窗口、设置菜单与原生语言刷新 |
| `UI/Shared` | `EditorPalette.swift`、`EditorFieldStyle.swift` | 共享界面颜色和输入框样式 |
| `Rendering` | `CanvasView.swift`、`CanvasView+Precision.swift`、`CanvasView+Containers.swift`、`CanvasRenderer.swift`、`TextLayout.swift` | 画布输入与绘制、临时反馈、文字布局；绘制规则供导出复用 |
| `IO` | `AppController.swift`、`AppController+Documents.swift`、`SketchFileInspector.swift` | 应用和窗口生命周期、文档面板及文件操作、Sketch ZIP 元数据读取 |
| `IO/Export` | `Exporter.swift`、`ExportSnapshot.swift`、`EditorSession+Export.swift`、`AppController+Export.swift` | 导出快照、准备、编码和目标文件写入 |
| `Localization` | `LanguageSettings.swift`、`L10n.swift`、`LocalizedMessage.swift`、`Resources/{en,zh-Hans}.lproj` | 语言偏好、显式翻译查找、保留参数的状态提示和双语词条 |

### 原生图层树的边界

- `NativeLayerTree` 只负责 SwiftUI/AppKit 桥接、更新入口和销毁。
- `NativeLayerTree+Coordinator` 在 `extension NativeLayerTree` 中定义原有嵌套 `Coordinator`，负责数据源、选择同步、展开状态、拖放和菜单；保留 `NativeLayerTree.Coordinator` 的类型名。菜单项和选中行绘制辅助类仍为本文件私有。
- `LayerTreeItem` 表示用于 NSOutlineView 的稳定节点对象和页尾占位节点。
- `NativeLayerOutline` 处理层级竖线、原生键盘输入和右键事件。
- `LayerTreeCell` 负责图标、名称、显示/锁定按钮和行内重命名宿主；非编辑名称控件仍为本文件私有。

SwiftUI 与 AppKit 的同一功能放在一起。功能扩展放在其职责目录，只有共享会话状态放在 `Editor/Session`。检查器数值控件依赖检查器属性与会话，属于 `UI/Layers`，不作为通用控件放入 `UI/Shared`。

## App 入口、测试与脚本

`Sources/OpenSketchApp/main.swift` 负责创建 `NSApplication` 和 `AppController`。应用资源仍由 `scripts/build.sh` 从仓库 `Resources` 复制到包内。

本地化词条由 SwiftPM 生成 `OpenSketch_OpenSketchUI.bundle`，打包脚本复制到应用的 `Contents/Resources`；`L10n` 优先使用应用内资源，测试和命令行运行使用 `Bundle.module`。状态提示保存键、参数或错误，展示时才按当前语言解析；文档中的用户名称和文字不作为翻译键。新增界面文案时同时更新两种语言及动态占位符检查。

测试保留 `Tests/OpenSketchCoreTests` 和 `Tests/OpenSketchUITests` 两个 target，按 Swift 模块导入，不依赖源文件目录。

`scripts/benchmark.sh` 使用 Bash 数组和 NUL 分隔路径递归收集 `Sources/OpenSketchCore` 内的 Swift 文件，与 `scripts/GeometryBenchmark.swift` 一起编译；路径含空格时仍作为独立编译参数。不要恢复为只匹配根目录的 `*.swift`。

## 添加或移动文件

1. 先确定所属 target，再按职责选择目录。Core 不依赖 OpenSketchUI、AppKit 或 SwiftUI。
2. 渲染实现放 `Rendering`，文件格式与读写放 `IO`，界面放 `UI`，编辑状态与事务放 `Editor`。
3. 拆分文件时保留私有辅助类型与调用方的文件边界；不要为目录调整扩大访问权限。
4. 更新本页和仍用于当前操作的路径说明。历史实施计划中的路径保留为当时记录。
5. 验证 `swift test`、`scripts/build.sh release`、`scripts/benchmark.sh`、包签名及 `git diff --check`。目录调整不改变 `.opensketch` 格式、偏好键、剪贴板类型或辅助功能标识。

本次整理的具体检查结果见 [2026-11-08 验证记录](development/2026-11-08-source-structure.md)。
