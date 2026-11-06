# 图层组织与排版实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 使用户能编组、整理叠放顺序，并对多个图层进行对齐和等距排版。

**Architecture:** OpenSketchCore 负责纯值树变换和几何计算；EditorSession 将命令作为一个历史事务应用；SwiftUI 图层树、检查器与 AppKit 菜单共享命令入口。持久化格式保持 v1。

**Tech Stack:** Swift 6、AppKit、SwiftUI、CoreGraphics、Swift Testing。

## Global Constraints

- macOS 15+，无第三方依赖；保持原生优先、现有亮暗主题和画布视口裁剪。
- 在现有 `feat/native-prototype` 工作区继续已获授权的开发；不安装到 `/Applications`，不推送远程。
- 原节点 UUID、子树内容和文档格式保持不变；每个有效命令只产生一次文档撤销，无效或无变化命令不产生脏状态。
- 编组和重排要求同一父容器；对齐/分布允许同页跨父容器，以页面坐标轴下的几何包围盒计算，再反算父局部位移。
- 对选中父子项去重，只处理最外层选中项；任一有效选中根或其祖先锁定/隐藏时整个命令禁用，不能悄悄处理剩余子集。
- 几何包围盒按节点 frame 四角经旋转及祖先变换得到，不含描边外扩；group 使用其容器 frame。本轮不提供编组缩放或子层变化后自动调整编组边界。
- 编组/取消编组必须保留内容的页面坐标和内部顺序；分散选择编组放在原最前选中层的位置（未选中项彼此顺序不变）。
- 取消编组仅作用于选中的 group，保留旋转和子节点 UUID；带填充、描边或非 1 不透明度的 group 禁用取消编组，以免丢失合成外观。
- 分布为相邻几何包围盒之间等间距，保留最前/最后空间端点；允许负间距，排序相同时保持原绘制顺序。
- 不新增自动布局、组件、钢笔、拖拽跨容器重挂接或 Sketch 导入。

## 决策与验收

用户已选择“图层组织与排版”。在实现纯图层命令、先做自动布局、先扩展文件互操作三个方向中采用前者，以补齐 M1 日常编辑工作流。操作入口为“图层”菜单、图层列表右键菜单，以及检查器内的图层操作和对齐/分布按钮。

图层列表按视觉前后顺序呈现父行及可折叠子行，层级深度真实缩进；Shift 点击切换成员。画布普通点击选中命中内容所属的最外层 group，Option 点击允许直接选子层；frame 不自动吞并子层选择。group 禁用现有仅改容器尺寸的缩放手柄/宽高输入，避免误导为整体缩放。

验收须覆盖旋转父容器、选中父子去重、多文档隔离、锁定/隐藏阻止、分布端点、稳定排序、一次撤销/重做、保存重开、菜单路由和实际 GUI 操作。

### Task 1: 纯值图层命令与几何回归

**Files:**
- Create: `Sources/OpenSketchCore/LayerEditing.swift`
- Create: `Tests/OpenSketchCoreTests/LayerEditingTests.swift`

**Interfaces:** 供 Task 2 使用以下公共接口（可添加 private 辅助函数，不修改名称）：

```swift
public enum LayerOrder: String, CaseIterable, Sendable {
    case forward, backward, front, back
}
public enum LayerAlignment: String, CaseIterable, Sendable {
    case left, horizontalCenter, right, top, verticalCenter, bottom
}
public enum LayerAxis: String, CaseIterable, Sendable { case horizontal, vertical }
public enum LayerCommand: Equatable, Sendable {
    case group, ungroup
    case order(LayerOrder)
    case align(LayerAlignment)
    case distribute(LayerAxis)
}
public struct LayerEditResult: Equatable, Sendable {
    public var document: DesignDocument
    public var selection: Set<UUID>
}
public enum LayerEditError: Error, Equatable {
    case invalidSelection, differentParents, lockedOrHidden, styledGroup, invalidGeometry
}
public enum LayerEditing {
    public static func canApply(_ command: LayerCommand, to document: DesignDocument,
                                pageID: UUID, selection: Set<UUID>) -> Bool
    public static func apply(_ command: LayerCommand, to document: DesignDocument,
                             pageID: UUID, selection: Set<UUID>) throws -> LayerEditResult
}
```

- [ ] 写失败测试并运行 `swift test --filter LayerEditingTests`。包括如下明确几何例：矩形 A=(10,20,20,30)、B=(70,80,40,20)，编组容器=(10,20,100,80)，子层本地原点分别=(0,0)、(60,60)，取消编组还原。选择 A 与 B 做左对齐后两者 x=10；水平居中后中心 x=60；底对齐后 maxY=100。
- [ ] 覆盖三个不同宽度节点 x/width=(0,20)、(40,30)、(100,40)，等间距为25，中间 x=45，端点保持不变；加垂直例、重叠负间距、同坐标稳定排序。
- [ ] 实现纯值命令。group ≥2 个同父根；ungroup ≥1 个同父 group；order ≥1 个同父根；align ≥2 个根；distribute ≥3 个根。全部验证后再修改候选文档，返回新 selection。
- [ ] 编组包围盒在父局部坐标中计算，每个孩子只减去新编组原点，rotation 不变。取消编组将孩子中心应用 group 的 localTransform，保留孩子尺寸，rotation 加上 group.rotation；子孙保持局部值。以多个测试点的世界坐标不变验证嵌套旋转。
- [ ] 叠放顺序按 children/nodes 的底到顶数组处理；front/back 稳定分区，forward/backward 每次让每段选中层越过一个相邻未选中层，保持选中项彼此顺序。边缘无变化返回相同文档。
- [ ] 对齐/分布按世界包围盒算位移，再用父 worldTransform 的逆矩阵将向量转回局部坐标。确保有限几何，候选文档通过 `DocumentCodec.encode` 验证；任何错误原文档不变。
- [ ] 运行定向测试和完整 `swift test`，记录红/绿证据、无效选择/锁定/隐藏/跨父编组失败、parent+child 去重及保存重开回归。只提交本任务源码与测试，使用 `git commit -s` 中文说明。

### Task 2: 会话事务、原生菜单和图层树

**Files:**
- Create: `Sources/OpenSketchUI/EditorSession+Layers.swift`
- Create: `Sources/OpenSketchUI/LayerActionsView.swift`
- Create: `Sources/OpenSketchUI/AppController+Layers.swift`
- Modify: `Sources/OpenSketchUI/AppController.swift`
- Modify: `Sources/OpenSketchUI/LayersSidebar.swift`
- Modify: `Sources/OpenSketchUI/InspectorView.swift`
- Modify: `Sources/OpenSketchUI/CanvasView.swift`
- Create: `Tests/OpenSketchUITests/LayerCommandTests.swift`

**Interfaces:** 消费 Task 1 的 `LayerEditing`。会话提供以下入口，UI 和菜单统一调用：

```swift
extension EditorSession {
    func canPerform(_ command: LayerCommand) -> Bool
    func perform(_ command: LayerCommand)
    func canvasSelectionTarget(_ hit: UUID, direct: Bool) -> UUID
}
```

- [ ] 先写会话/菜单测试：编组后 selection 是新组，undo 恢复原节点顺序、redo 恢复编组；每个命令只一条历史；无效命令不变；切换文档后的菜单只修改当前文档；进行中的文字事务先提交，再执行图层命令。
- [ ] `perform` 先 `finishInput?()`，调用纯值命令，文档不同才 `change { $0 = result.document }`，随后更新 selection；错误用状态栏中文消息说明。菜单禁用和检查器禁用来自 `canPerform`。读能力查询不得创建 UUID 或改变文档/历史。
- [ ] 添加独立“图层”菜单：编组 ⌘G、取消编组 ⇧⌘G、上移一层 ⌘]、下移一层 ⌘[、置于顶层 ⇧⌘]、置于底层 ⇧⌘[；“对齐”子菜单六项和“等距分布”子菜单两项。快捷键正在编辑普通文本字段时禁用图层命令，避免吞掉文本快捷键；按钮主动执行可提交行内文字。
- [ ] 检查器顶部展示 `LayerActionsView`：编组/取消编组、层级菜单，以及六个对齐和两个分布按钮，采用现有主题，提供中文帮助及稳定 AX ID：`layer.group`、`layer.ungroup`、`layer.order.<rawValue>`、`layer.align.<rawValue>`、`layer.distribute.<rawValue>`。
- [ ] 图层树按每层 children.reversed() 呈现，父行在子行之前；使用独立 row 数据（id、depth、node）生成展开列表，折叠状态为视图局部状态。容器行显示展开按钮及类型图标；保留现有 `layer.<UUID>`、visibility、lock 标识。Shift 点击采用成员切换语义，右键菜单调用同一套会话命令，不重复实现树修改。
- [ ] Canvas 普通命中提升为最外层 group，Option 命中保留最深层；保持 frame 子项点击行为和文字双击编辑兼容。group 禁用缩放手柄命中与绘制；检查器 group 宽/高只读，并隐藏不适用于普通编组的填充/描边编辑。X/Y、旋转、重命名可用。
- [ ] 覆盖 GUI 宿主测试：树嵌套深度/父子顺序、菜单标题/快捷键/禁用、group 与 Option 直选命中、原生输入不被图层快捷键抢占；运行定向与完整 `swift test`。只提交本任务文件。

### Task 3: 发布包与实际工作流验收

**Files:**
- Modify: `README.md`
- Modify: `docs/development/core-api.md`
- Create: `docs/development/2026-11-06-layer-layout.md`

**Interfaces:** 使用已完成的 Task 1/2 API 和实际菜单/检查器入口，不添加新功能。

- [ ] 检查范围和源码 diff；运行 `swift test`、`scripts/build.sh release`、`codesign --verify --deep --strict build/openSketch.app`、`plutil -lint build/openSketch.app/Contents/Info.plist`、`git diff --check`。
- [ ] 用原生 GUI 保留用户当前文档，重启新版，创建独立验收文档；实际测试多选、编组/展开、移动、取消编组、对齐/分布和叠放顺序，再验证撤销/重做、保存重开。
- [ ] 恢复用户原设计和外观。更新 README 功能/快捷键/限制，记录 API 语义、测试总数、GUI 验证和未验证边界；所有文档内容由实际结果填写。中文签署本地提交，保持工作区干净。
