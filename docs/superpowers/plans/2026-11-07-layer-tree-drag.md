# 图层树拖拽 Implementation Plan

> 在当前会话使用 executing-plans 实施，基线 `02cb652`。

**Goal:** 左侧图层拖动调整同级顺序或画板/编组归属，位置不跳变，支持多选及一次撤销。

**Architecture:** 新增 Core 值编辑器 `LayerTreeEditing`，提供 above/below/inside/pageEnd 四种落点；UI 会话保存带 UUID 的单次拖动请求，原生 item provider 仅在本进程流转；SwiftUI 行与根层级落点显示反馈并处理 drop。保留现有 Canvas 容器拖动规则，不改文件格式。

**Tech Stack:** Swift 6、macOS 15+、SwiftUI DropDelegate/AppKit NSItemProvider、Swift Testing。

## 约定

- 列表自上而下对应绘制顺序自前而后；行上/下边缘插入同级，画板/编组中间区域放入容器最前方。普通节点上下半行分别表示上/下。
- 拖动已选对象保留多选，拖未选对象只移动该对象；父子同时选中仅搬运最高祖先，保留子树和原相对绘制顺序。
- 转换父坐标系保持世界几何、UUID、尺寸、子树；同父仅重排，不重新计算几何。画板也可重排或嵌套，结果仍需通过现有文档校验。
- 拒绝自包含/循环、跨页面或跨文档拖放、源/目的父容器锁定或隐藏、超深/无效文档。拖动期间页面或文档发生变化时拒绝过期请求。
- 悬停不修改文档/历史；落下后一次提交，失败、取消和无变化不污染历史。根层级落点可将内容移出容器，放入容器后展开目标。
- 保留整行选择、Shift 多选、右键和原位重命名。重命名时不发起图层拖动。

## 实施

- [x] Core 测试先 RED：上下插入的反向索引、多选顺序、旋转父容器/子树保持、同父 no-op、移出根层级、非法循环/锁定/跨页/超深/无效几何原子拒绝。实现 `Sources/OpenSketchCore/LayerTreeEditing.swift`。
- [x] UI 会话测试先 RED：拖动未选/多选、单步 undo/redo、请求隔离与文档变化拒绝、provider token 校验、取消/无变化。实现 `EditorSession+LayerDrag.swift`，补充会话状态。
- [x] 在 `LayersSidebar.swift` 接入拖动及反馈，新增 `LayerTreeDropDelegate.swift`。上下边缘各占 25%，容器中间 50% 放入；普通节点分为上下半行；底部根层级落点始终可达。
- [ ] 相关测试、全量测试、Release/diff/signature；独立只读审查。实窗可用时用独立样例检验真实拖放、行间/容器反馈、多选/撤销与保存重开；保留用户文档。更新 README 与验收记录并本地 Signed-off-by 提交，不推送或安装系统目录。

结果：41 项相关测试、318 项全量测试和 Release/签名检查通过，独立源码审查的问题均已修复。新包及旧包备份已生成；窗口与访达均返回 cgWindowNotFound，实窗部分保留待验收，见 `docs/development/2026-11-07-layer-tree-drag.md`。
