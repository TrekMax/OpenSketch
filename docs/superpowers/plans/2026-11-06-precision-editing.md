# 精准编辑实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 为原生画布加入拖框多选、方向键微调和移动吸附参考线。

**Architecture:** Core 的 CanvasEditing 计算纯值选择、平移和吸附；CanvasView 路由原生输入，扩展文件管理临时状态；EditorSession 复用文档历史并保存每文档的吸附开关。

**Tech Stack:** Swift 6、AppKit、SwiftUI、CoreGraphics、Swift Testing。

## Global Constraints

- macOS 15+、Swift 6、无第三方依赖；保持 v1 文档格式、原节点 UUID、现有亮暗主题、原生标题栏和编辑区裁剪。
- 在现有 `feat/native-prototype` 工作区继续，不安装到 `/Applications`、不推送；中文 `git commit -s`，只提交任务所有文件。保持当前用户文档安全，代理不操作真实 GUI。
- 框选及参考线是临时状态，不使文档变脏；框选要求完全包含可见 frame 几何的页面轴向包围盒，不含描边和实际 path 轮廓。
- group 作为整体且不进入孩子；frame 被完整框住时选容器，否则进入孩子。隐藏/锁定祖先阻止框选；祖先 frame 裁剪用旋转后的凸四边形求交，完全裁掉的节点忽略。
- 选中父子只移动最外层根；任一有效根或其祖先隐藏/锁定时整次平移拒绝，不能静默处理其余子集。位移按页面坐标，逆父变换转为局部；结果坐标 ±1e9，有限数，无效平移原子失败。
- 鼠标移动吸附阈值 6/zoom 页面点，按整组完整世界 frame 包围盒的三轴锚点比较其他可见节点；参考节点使用裁剪后的 frame 包围盒，排除所选子树及全部祖先，锁定可见节点可作参考。
- 每轴最小绝对修正优先，等距按场景绘制顺序再参考/移动锚点顺序稳定决胜。至多两条参考线，以手势起始快照和原始位移计算，不累积。
- 方向键 1 点、Shift 10 点，同段按住/重复在最后方向键 keyUp 提交一次历史；Escape 取消。鼠标开始、其他命令、焦点丢失、工具/文档/视口变化提交；无变化不产生历史。
- 底部新增默认开启、每文档独立“吸附”开关，AX `view.snapping`，不持久化进文档；Control 拖动绕过；开关变化先结束手势。手势结束/取消清除参考线和框选。
- 不实现尺寸/创建/网格吸附、手动参考线、测距、编组整体缩放、自动布局或文件导入。文字与既有单次绘制行为不能回归。

## Task 1: Core 框选、平移和吸附几何

**Files:** Create `Sources/OpenSketchCore/CanvasEditing.swift`, `Tests/OpenSketchCoreTests/CanvasEditingTests.swift`。

**Interfaces:** 以下公共 API 是 Task 2 的固定依赖，类型均 Equatable、Sendable：

```swift
public struct SnapGuide: Equatable, Sendable {
    public var start: CGPoint
    public var end: CGPoint
    public init(start: CGPoint, end: CGPoint)
}
public struct MovementSnap: Equatable, Sendable {
    public var translation: CGSize
    public var guides: [SnapGuide]
    public init(translation: CGSize, guides: [SnapGuide])
}
public enum CanvasEditing {
    public static func marqueeSelection(in page: DesignPage, rect: CGRect) -> Set<UUID>
    public static func snapMovement(in page: DesignPage, selection: Set<UUID>,
                                    translation: CGSize, tolerance: CGFloat) -> MovementSnap
    public static func translating(_ document: DesignDocument, pageID: UUID,
                                   selection: Set<UUID>, by delta: CGSize) throws -> DesignDocument
}
```

错误复用 `LayerEditError`。框选无效矩形返回空；吸附无效参数/选择返回原 translation 和空 guides；平移空选择返回相同文档，其他无效选择抛错。无需全文件编码。

- [x] 先写失败测试并实际运行。基本几何例：A=(0,0,20,20)、B=(100,80,40,40)，框=(−1,−1,22,22) 仅选 A；只相交不选；group 的孩子不能被单独框选；frame 未全包时允许选其孩子。旋转裁剪用实际裁剪后的凸多边形包围盒验证，不能仅用祖先 AABB 冒充裁剪。

```swift
@Test func translationUsesPageAxesAndPreservesIdentity() throws {
    let node = DesignNode(kind: .rectangle, frame: CGRect(x: 10, y: 20, width: 30, height: 40))
    let page = DesignPage(nodes: [node])
    let doc = DesignDocument(pages: [page])
    let moved = try CanvasEditing.translating(doc, pageID: page.id, selection: [node.id], by: CGSize(width: 1, height: -10))
    #expect(moved.node(id: node.id)?.frame.origin == CGPoint(x: 11, y: 10))
    #expect(doc.node(id: node.id)?.frame.origin == CGPoint(x: 10, y: 20))
}
```

- [x] 实现内部一次遍历的场景 entry（节点、祖先、world、可编辑/可见、完整 frame bounds、裁剪后的 bounds）。frame 四角变换后，用 Sutherland–Hodgman 凸多边形裁剪依次作用于祖先 clipping frame；group 的 clipsContent 不生效。zero-area/非有限可见几何不参与框选/参考。
- [x] 实现框选递归：先检查可编辑及可见几何；contained 选当前并停止后代；group 未 contained 不深入；frame 未 contained 才深入。叶节点 contained 选中。标准化倒向拖动矩形，完全包含可见 bounds。
- [x] 平移验证同页所有选择，去除选中祖先覆盖的子项；先计算每根新 frame.origin，再批量应用；旋转父的逆变换仅作用于向量。覆盖父子不会双移、跨父旋转世界位移一致、整次拒绝锁定/隐藏、非有限与边界溢出原子失败、零位移和空选择无变化。
- [x] 吸附对有效根完整 bounds 求并集并加原始 translation；其他可见条目排除有效根/后代/祖先后提供 min/mid/max。每轴扫描三对三组合，abs(correction)≤tolerance 选择稳定最小值；结果 translation 加修正。guide 是对应坐标的线段，其另一轴范围跨过修正后移动 bounds 和参考 bounds。无匹配没有 guide，不产生 UUID 或修改页面。
- [x] 数值验证：移动 A=(0,0,20,20) 朝参考 B=(100,80,40,40)，raw=(78,58)、tolerance=3，最近边分别对齐 x=100/y=80，结果=(80,60)、2 guides；raw=(76,56) 超阈值保持原值。覆盖中心、同距稳定、隐藏/锁定参考、所选后代排除、旋转裁剪、0.5/2 倍 zoom 对应 tolerance12/3 的屏幕阈值。
- [x] 定向 `swift test --filter CanvasEditingTests` 及完整 `swift test`，记录真实 RED/GREEN 和失败原因；审查没有每帧编码或文档变异；只提交 Core 文件。

## Task 2: 原生框选、键盘事务与吸附覆盖层

**Files:** Create `Sources/OpenSketchUI/CanvasView+Precision.swift`, `Tests/OpenSketchUITests/PrecisionEditingTests.swift`; modify `CanvasView.swift`, `EditorSession.swift`, `EditorRootView.swift`, `AppController.swift`（为全选命令补齐 finishInput，并让原生 Undo 预检与工具栏共享待提交微调能力）。若需要额外明确会话扩展，创建 `EditorSession+Precision.swift`，不做无关重构。

**Interfaces:** 消费 Task 1 API。Session 新增 `var snapping = true`；`moveSelection(by:)` 调用 `CanvasEditing.translating`，以 `gestureStart` 为起点，错误只报告中文状态。Canvas 新增存储状态供扩展使用：框选起点/当前 rect/初始 selection、按键集合与累计位移、当前 guides；可采用小 struct 表达互斥活动类型，避免同时存在鼠标和键盘事务。

- [x] 先写失败的原生 NSEvent 用例：空白 mouseDown+mouseDragged 框住 A/B 后选两项；Shift 追加、Escape 恢复；键盘 repeated right 三次在一个 keyUp 后 x+3，一次 undo 恢复，redo 重做；ShiftDown y+10；旋转父子世界位移正确。按键 code left123/right124/down125/up126；Escape53。事件构造遵循现有 LayerCommandTests 的 Canvas 宿主。
- [x] 将框选帮助/覆盖层绘制放扩展文件。在空白按下保存原 selection，普通即时清空、Shift 保留；拖动达到3屏幕点后调用 Core 更新selection；Shift用初始selection union结果再去除被选中祖先覆盖的后代，避免父子重复选。鼠标结束不提交文档历史。Escape恢复初始selection。
- [x] 已命中图层的拖动保留原选择/Option直选/Shift切换。仅普通移动分支计算吸附：

```swift
let raw = CGSize(width: point.x - origin.x, height: point.y - origin.y)
let result = session.snapping && !event.modifierFlags.contains(.control)
    ? CanvasEditing.snapMovement(in: baselinePage, selection: session.selection,
                                 translation: raw, tolerance: 6 / session.zoom)
    : MovementSnap(translation: raw, guides: [])
session.moveSelection(by: result.translation)
```

creation/resizing 不吸附。guides 在画布 world context 中绘制，使用既有主题 accent、1/zoom 线宽和按zoom换算的虚线；框选半透明填充+边框；保留 clipsToBounds，不渲染到导出。
- [x] 在 Canvas.keyDown 只接管没有 Command/Option/Control 的方向键。第一次开始文档事务，累计本段页面delta，调用同一moveSelection；记录按下的方向键集合，keyUp移除、集合空时提交；Escape还原。原生文本编辑器保持firstResponder，不添加全局事件监视器。按住键期间选择/工具/文档/其他命令通过finishInput提交。
- [x] 完整收尾：新mouseDown、finishInput、resignFirstResponder、scrollWheel/magnify/fit/zoom均先结束精准编辑状态；避免finishText与resignFirstResponder递归，不能提前提交行内文字自己的历史。鼠标finishGesture只提交实际文档手势，框选不调用beginGesture。Escape一次清理所有临时状态并恢复应该恢复的selection/document。
- [x] 底栏“吸附”Toggle使用显式Binding，setter先finishInput再赋值；AX `view.snapping`；每文档独立，CanvasHost订阅该值触发绘制。保留网格、亮暗色、标题栏与单次绘制语义。
- [x] 追加原生回归：Control拖动保留raw且guide清空、释放/取消清空覆盖层、阈值随zoom、同段repeat只一次历史、键盘焦点/切换文档提交且不污染另一文档、文字/数字字段方向键不移动图层、越界错误无部分移动、普通点击无脏状态。运行定向及全量测试和真实 Release compile（只编译不打包），只提交任务文件。

## Task 3: 发布与真实验收

**Files:** Update README.md, docs/development/core-api.md, this plan; create docs/development/2026-11-06-precision-editing.md。

- [x] 源码范围审查、全量测试、`scripts/build.sh release`、严格签名与 plist、`git diff --check`。先通过原生保存保留用户当前文档再正常退出更新应用，禁止丢弃用户未保存内容。
- [x] 独立GUI样例验证框选、方向键1/10、一次撤销重做、吸附开关与最终坐标、保存重开和切换文档无临时覆盖层。Shift追加、Control绕过、持键中取消/撤销及guide像素由原生事件/bitmap测试覆盖（CUA不能可靠拆分持键阶段）；实际边界写入验收记录。
- [x] 恢复用户原活动文档/页面/主题；更新功能、快捷键、API和实际验收记录，区分自动化/GUI与未验证边界；审查后中文签署本地提交。

完成于源码 `8836d10`：171 项测试、Release/签名/plist通过，真实工作流与用户文档恢复见 [精准编辑验收](../../development/2026-11-06-precision-editing.md)。
