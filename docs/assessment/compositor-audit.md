# Compositor 源码复用审计

审计日期：2026-11-05。来源：相邻仓库 `../../../Compositor`，提交 `f6cd2f05525e7ca61d680cd221a690b796ef21d2`，分支 `feat/module-manager`；审查开始时工作树干净。

## 关键调用链

### 形状

`EditorSession.finishShape()` → `shapeImage()` → 位图 `CGContext` → `makeImage()` → `addPixelLayer()` → `ImageLayer.asset`。

[ShapeTool.swift](../../../Compositor/Compositor/Editor/Tools/ShapeTool.swift)：L301 创建形状；L393 生成位图；L182 的 `LayerShape` 同时持有 style 与 `CGImage`；L195 的 `liveShape` 通过图像对象身份判断形状元数据是否仍有效。L354 的 `redrawShape` 在尺寸改变时重新生成像素，线条缩放还会移除 shape 元数据。

结论：有参数化形状和路径生成能力，但最终持久化/显示仍围绕像素图层。其圆角路径数学可借鉴，不能把当前 Shape 工具视为通用节点编辑器。

### 文字

`applyText()` → `textImage()` → `NSTextStorage` / `NSLayoutManager` → 位图上下文绘制 glyph → `CGImage` → 更新图层 asset，并附加 `LayerText`。

[TypeTool.swift](../../../Compositor/Compositor/Editor/Tools/TypeTool.swift)：L271 应用文字；L206 的 `LayerText` 保存图像引用；L449 文本栅格化；[InlineTextEditor.swift](../../../Compositor/Compositor/Rendering/InlineTextEditor.swift) 负责原生文字编辑的交互桥接。

结论：NSTextView、输入法和编辑事务经验可借鉴；矢量文字的统一测量、排版、样式与导出需要重新设计。

### 渲染与导出

[GPUCanvas.swift](../../../Compositor/Compositor/Rendering/GPUCanvas.swift) L108 把 `CGImage` 转为缓存纹理；[LayerRenderer.swift](../../../Compositor/Compositor/Rendering/LayerRenderer.swift) L5 接收 `CGImage`；[ImageExporter.swift](../../../Compositor/Compositor/IO/ImageExporter.swift) L25 从像素快照合成 `ExportRaster`，L269 的 PDF 导出先调用 `render()`。

结论：GPU 和多图层并不等于矢量场景图。当前 PDF 输出也不能直接承担 openSketch 的矢量 PDF 导出。

### SVG、PDF 与画板导入

[ImageImporter.swift](../../../Compositor/Compositor/IO/ImageImporter.swift) L91 `decodeSVG` 通过 `NSImage` 绘入像素；L116 `decodePDF` 把每页画入位图。SVG/PDF 的路径及文字结构不会因此成为可编辑对象。

[PSDTypes.swift](../../../Compositor/Compositor/IO/PSD/PSDTypes.swift) L73 `artboards()` 将 Photoshop 画板拆为多份文档；[EditorSession.swift](../../../Compositor/Compositor/Editor/Session/EditorSession.swift) L1157 起说明每个画板在工作区作为独立文档标签打开。这与一个页面内多画框/嵌套 Frame 的模型不同。

### 保存与历史

[CanvasDocument.swift](../../../Compositor/Compositor/Editor/Model/CanvasDocument.swift) L4 保存固定像素宽高和 `[ImageLayer]`；[ImageLayer.swift](../../../Compositor/Compositor/Editor/Model/ImageLayer.swift) L4 包含 asset、transform、parentID，以及可选 shape/text。

[ProjectStore.swift](../../../Compositor/Compositor/IO/ProjectStore.swift) L18 定义 manifest，当前版本 21；L163 起写资源，L207 起编码 JSON，L225 起协调原子替换文件包。

[DocumentHistory.swift](../../../Compositor/Compositor/Editor/Session/DocumentHistory.swift) L5 起使用值快照共享不可变图像，记录 before/after 和保存修订；其像素内存核算与文档类型绑定。

结论：复用事务、脏状态、快照保存与安全替换的设计；为新模型重写持久化 schema 和历史数据结构。

## 复用决策表

| 能力 | 已检查入口 | 建议处理 |
|---|---|---|
| 快捷键、命令搜索 | `UI/Commands/ShortcutChord.swift`、`ShortcutSettings.swift`、`CommandPalette.swift` | 选择性移植，替换命令集，保留稳定命令 ID 的思路 |
| 数值拖动、提示、面板 | `UI/Shared/NumericScrub.swift`、`ToolTip.swift`、`FloatingPanel.swift` | 较小单元先做依赖与 macOS 15 API 审计 |
| 缩放和平移 | `Rendering/CanvasViewport.swift` L5 | 复用锚点缩放与 Retina 处理思想；改为页面工作区与设计单位 |
| 对齐、参考线、吸附 | `Editor/Canvas/Guides.swift` L247、`Editor/Layers/LayerAlign.swift` L124 | 几何部分候选；改接节点、旋转边界和父子坐标 |
| 多文档与文件生命周期 | `Editor/Workspace/ProjectWorkspace.swift`、`IO/ProjectController.swift` | 参考其保存修订、关闭协调；不连同 EditorSession 整体搬运 |
| 本地化 | `Localization/LanguageSettings.swift`、`NativeMenuLocalization.swift` | 复用显式语言查找的思路；重建产品词表并检查动态/AppKit 路径 |
| 简单形状路径 | `Editor/Tools/ShapeTool.swift` | 数学与样式部分可抽取，去除 CGImage 身份依赖 |
| 路径布尔算法调用 | `Editor/Selection/Selection.swift` L407 | 已使用 CGPath 并/交/差，但作用于选区；可作为几何实验参考 |
| 图层树与属性面板 | `UI/Layers/NativeLayerList.swift` 等 | 借鉴交互，重接语义模型；节点种类和属性差异较大 |
| 像素合成与照片功能 | `Rendering/GPUCanvas.swift`、Adjustments、Filters、Brush | 首版主线不移植 |
| 文档、组件、布局和矢量导出 | 当前文档与导出路径 | 建立新核心；本次未找到完整组件/Stack/可编辑 Bézier 对象系统 |

“未找到”基于 Model、Editor、Rendering、IO 目录和功能入口的本次审查，不是对整个仓库每行代码的形式化证明。

## 工程规模与边界

- `git ls-files '*.swift' '*.c' '*.h'` 统计：应用源文件 239 个、52,612 行；单元测试 120 个、22,484 行；UI 测试 1 个、102 行。行数包含注释和空行，仅用于判断现有工程规模。
- `EditorCanvas.swift` 3,500 行；`EditorSession.swift` 1,279 行；两者不宜作为通用库整体复制。
- [source-structure.md](../../../Compositor/docs/source-structure.md) 明确说明目录分组不是独立 Swift 模块。
- [project.pbxproj](../../../Compositor/Compositor.xcodeproj/project.pbxproj) 中部署目标 26.0、Swift 5.0，依赖 Sparkle。新项目需要自己的最低版本与发布配置。
- [LICENSE](../../../Compositor/LICENSE) 为 MIT，署名 Wonder Assembly LLC。复制代码时保留原许可。

本次没有重新执行 Compositor 的构建、单元测试、GUI 回归或性能测试，不能把历史测试结果作为这次复用后的验证结果。
