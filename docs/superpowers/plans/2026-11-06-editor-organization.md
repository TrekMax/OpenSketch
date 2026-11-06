# 编辑器组织交互实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 完成页面列表、画板拖放容器、图层右键复制/删除及实时缩放滑条。

**Architecture:** Core 提供纯值容器目标/归属变换；Canvas 在 mouseUp 合并归属与移动事务；侧栏使用会话命令；原生工具栏宿主可观察 SwiftUI 缩放滑条。

**Tech Stack:** Swift 6、macOS 15+、AppKit、SwiftUI、Swift Testing，无第三方依赖。

## Global Constraints

- 在 `feat/native-prototype` 原工作区继续，基线 `1c845e2`；中文 `git commit -s`，只提交本任务文件，不推送、不安装 /Applications。代理不操作真实 GUI、不打包；root 负责保存用户文档和最终 Release。
- 保持 v1 格式、UUID、主题、标题栏、画布裁剪、多文档、文字输入和单次绘制行为。方向键微调不改变父层级。
- 页面列表只新增垂直选择展示，保留添加，不做删除/改名/排序。复制/删除移动至图层右键菜单，预检纯读，执行基于同一有效选择，全选任一不可编辑即禁用，不能只处理子集。
- 滑条替代标题栏 100% 按钮，保留适合和放大/缩小；5%–800%，log2 值映射；拖动时浮层即时显示整数百分比，松开隐藏。以画布中心缩放，不增历史；所有缩放入口与文档切换同步。
- 画布普通移动超过 3 屏幕点才考虑改归属，仅 mouseUp 应用，移动+归属一次历史；Escape 恢复、其他结束输入提交移动并清理预览，不把中断视为 drop。
- drop 指针位于可编辑 frame 的真实变换后矩形内才是目标，祖先 clipping frame 限制资格；重叠最上层子树、最深 frame 优先。排除选中子树，hidden/locked 祖先阻断；源选择任一无效/锁定/隐藏原子拒绝。
- 按最外层选中根处理；任一根 kind=frame 则整次自动归属为 no-op。每根最近 frame 祖先等于目标时保持原父（含 nil==nil）；不同才插入目标最上方或页面根，按原绘制顺序追加。保留世界几何、旋转、尺寸、UUID、子树，结果须通过 DocumentCodec。
- 目标高亮/移动外框临时且不导出；不做新建自动收纳、自动布局、侧栏拖拽重排、Space 绕过或画板自动嵌套。

## Task 1: Core 画板目标与归属变换

**Files:** Create Sources/OpenSketchCore/ContainerEditing.swift、Tests/OpenSketchCoreTests/ContainerEditingTests.swift。复用 DocumentOperations、SceneGeometry、LayerEditError，不修改已有算法。

**Interfaces:**
```swift
public enum ContainerEditing {
    public static func dropTarget(in page: DesignPage, selection: Set<UUID>, at point: CGPoint) -> UUID?
    public static func reparenting(_ document: DesignDocument, pageID: UUID,
                                  selection: Set<UUID>, to targetID: UUID?) throws -> DesignDocument
}
```
无效 target/循环/缺失选择抛 LayerEditError.invalidSelection，非法几何抛 invalidGeometry，锁定隐藏抛 lockedOrHidden；空选择返回原文档。dropTarget 无效选择/参数返回 nil。reparenting target 必须同页 frame 或 nil；函数应用上述最近画板相等不变、frame 根 no-op 规则。由调用方判断是否发生了实际拖动；函数不处理历史。

- [ ] 写实际失败测试并运行：frame F=(100,100,300,200)，root A=(140,150,20,30)，drop(150,160)得到F；转入后A.local=(40,50)，世界四角不变；转出nil后回到(140,150)，ID/尺寸不变。
```swift
@Test func entersFrameWithoutVisualJump() throws {
    let frame = DesignNode(kind: .frame, frame: CGRect(x: 100, y: 100, width: 300, height: 200))
    let a = DesignNode(kind: .rectangle, frame: CGRect(x: 140, y: 150, width: 20, height: 30))
    let page = DesignPage(nodes: [frame, a]); let doc = DesignDocument(pages: [page])
    let result = try ContainerEditing.reparenting(doc, pageID: page.id, selection: [a.id], to: frame.id)
    #expect(result.parentID(of: a.id) == frame.id)
    #expect(result.node(id: a.id)?.frame.origin == CGPoint(x: 40, y: 50))
    #expect(doc.parentID(of: a.id) == nil)
}
```
- [ ] 实现一次场景索引/遍历收集节点、父亲、祖先、world、绘制序，可编辑资格；drop用局部逆变换矩形contains并追踪祖先裁剪资格，先处理上层子树再深层frame，不能被普通覆盖矩形阻止找到所在frame。选中根及后代不能成为目标，过滤后仍可命中其合法祖先。
- [ ] reparenting先完整验证选择归一化最外根、目标和循环、源目标变换，最近frame相等保持原父；计算变换后只在值副本一次remove/insert，所有成功后编码验证。转换公式：currentWorld.concatenating(targetWorld.inverted())；用局部中心变换得新center，frame.origin=center-size/2，rotation=atan2(b,a)*180/pi。保持子树不重算。
- [ ] 增补独立数值/边界测试：两个旋转父与目标世界多点一致；组内移动不拆组、从组跨frame移动、父子归一化、多选稳定追加、选中frame整体no-op、目标后代循环、missing/crosspage/lockedhidden/祖先locked/非有限与±1e9越界原子拒绝、无变化无新ID；重叠/嵌套/旋转/clipped frame目标筛选；保存重开保留父子关系。
- [ ] `swift test --filter ContainerEditingTests` 和全量 `swift test`，记录RED/GREEN和日志，diffcheck；中文签署提交仅两个新文件。

## Task 2: 页面列表、右键动作与缩放滑条

**Files:** Modify Sources/OpenSketchUI/LayersSidebar.swift、LayerActionsView.swift、EditorSession+Layers.swift、EditorSession.swift、AppController.swift、CanvasView.swift；Create Sources/OpenSketchUI/ZoomControlView.swift、Tests/OpenSketchUITests/OrganizationControlsTests.swift。

**Interfaces:** 新增 `EditorSession.selectPage(_ id: UUID)`、`setZoom(_ value: CGFloat)`、`var setCanvasZoom: ((CGFloat)->Void)?`；Canvas initializer 绑定绝对 zoom 到现有zoom(to:anchor:)中心；保留既有zoomCanvas倍数入口，AppController.actualSize改调用setZoom(1)。右键新增统一的 `canEditContextLayers(for id: UUID)` 与 `duplicateContextLayers(for:)`、`deleteContextLayers(for:)` 会话方法，使用既有contextMenuSelection。ZoomControlView持有workspace，body观察workspace.current.session，避免存旧session。

- [ ] 先写行为失败测试：选择第二页清空selection、切页提交pending输入而自身不脏；无效id不切换；上下文右键未选行操作正确成员，已选行多选、父子不重复、locked/hidden无部分操作，菜单预检不改选择。
- [ ] 侧栏替换Picker为ScrollView+页面行Button。当前页主题选中态、accessibility selected trait及ID `page.row.UUID`，区域ID `page.list`，动态高度一行约28、上限140，页面增加后显示并选中；移除底栏复制/删除HStack。
- [ ] LayerCommandsMenu首部添加复制/删除和分隔线，ID保留 `layer.duplicate`、`layer.delete`；调用统一上下文能力/执行方法，执行先finishInput、再设有效selection后调用duplicate/deleteSelection。原其他命令不变。复制采用现有副本偏移行为，此任务不扩展复制算法。
- [ ] 新建ZoomControlView，log2映射滑条到session.setZoom(exp2(value))，onEditingChanged显示/隐藏非阻挡百分比浮层，实时显示四舍五入整数。AX `view.zoomSlider`，标签“缩放”，可访问值百分比。工具栏用NSHostingView包住该控件，合理固定宽约160，高度32；浮层通过popover或独立原生承载避免标题栏clip，显示时不夺画布焦点、不阻断drag。替换view.actualSize项为view.zoomSlider，保留fit/+/-；按新增控件宽度调整文档tabs的剩余宽度预算。
```swift
func setZoom(_ value: CGFloat) {
    guard value.isFinite else { return }
    finishInput?()
    let value = min(8, max(0.05, value))
    if let setCanvasZoom { setCanvasZoom(value) } else { zoom = value }
}
```
- [ ] 原生测试验证5%/100%/800%、无效缩放忽略、画布中心世界点不变、不脏、多文档路由、滚轮/快捷键后控件源值更新；覆盖宿主slider连续值和editing状态，UI/AX外观留root实窗验证。旧测试引用view.actualSize如确受变更影响按新明确契约更新，不删行为覆盖。
- [ ] 定向/full测试、Release只编译、diffcheck，通过后仅任务文件签署中文commit；不得打包/重启用户app。

## Task 3: 画布拖放画板集成

**Files:** Modify Sources/OpenSketchUI/CanvasView.swift；Create Sources/OpenSketchUI/CanvasView+Containers.swift、EditorSession+Containers.swift、Tests/OpenSketchUITests/ContainerInteractionTests.swift；必要的画布临时绘制接口可小改CanvasRenderer.swift，不改变导出默认行为。

**Interfaces:** 消费Task1 ContainerEditing。session增加 `applyContainerDrop(at point: CGPoint)`，在当前gesture内先计算target再reparenting；不另begin/commit。Canvas新增临时dropTargetID与是否有效移动状态，封装于扩展避免主文件进一步增长。

- [ ] 写失败原生事件测试：从rootA=(20,40,40,30)拖到F=(200,100,300,250)内，释放后A父为F、世界起点=拖前+位移，一次undo同时恢复位置/父，redo恢复；从frame拖出nil，跨frame和90度旋转容器；不以仅API调用冒充实际事件。
- [ ] 普通move分支达到3屏幕点后记录有效移动，依据当前页面/指针更新dropTargetID（frame根则无候选）；目标轮廓用world变换真实矩形绘制accent，线宽屏幕一致，只在编辑区。选中拖动物的未裁剪外框可表示其从旧clipping frame移出的当前位置，避免只剩不可见拖动；只处理普通move，不影响creation/resize/marquee/nudge。
- [ ] mouseUp仅当有效普通move时调用session.applyContainerDrop，然后原finishGesture合并commit；选择ID不变，树自动刷新。drop无变化保留history语义；失败保持已成功的移动数据并中文提示，不产生部分层级修改。
- [ ] finishInput/focus/window/viewport/document change以及Escape均清理目标/移动外框；中断只提交当前位置、不drop。Escape先还原gesture快照。点击、右下缩放、创建、键盘微调均不触发parent改变。
- [ ] 原生回归覆盖低阈值点击、鼠标创建和resize无reparent、frame自身带孩子移动、组内不拆组、跨容器父子去重、锁定拒绝和中文状态、完成/取消/切文档清理、按住状态目标bitmap/完成后消失；图层树层级和真实包保存重开。
- [ ] 定向/full测试和Release只编译、diffcheck，签署中文范围commit；报告真实RED/GREEN及覆盖边界。

## Task 4: 发布与验收记录

**Files:** README.md、docs/development/core-api.md、docs/development/2026-11-06-editor-organization.md、此计划。

- [ ] 最终源码审查；原生保存用户最新文档并正常退出；打包Release、严格签名/plist，复用最终源码已通过的全量测试证据。
- [ ] 真实GUI验证多页面列表切换、图层右键复制删除与undo、滑条值变化及不脏、拖入frame父子层级、移动frame子层跟随、拖出和undo、保存重开；不能可靠保持的drag中间态用宿主事件/bitmap证据并明确边界。
- [ ] 恢复用户原文档/页面/主题，核对文件哈希；记录接口、功能、参考来源和验证，中文签署本地提交，干净工作区，不安装不推送。
