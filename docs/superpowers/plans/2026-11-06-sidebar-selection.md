# 侧栏整行选择 Implementation Plan

> 使用 executing-plans 在当前会话实施；基线 `283c82d`。

**Goal:** 页面、图层和编组整行可选且整行高亮，Shift 点击追加/取消选择。

**Architecture:** 保留现有 SwiftUI 行与独立功能按钮，补齐背景命中；页面增加会话内的选择集合，活动页面仍唯一。图层复用现有 Shift 切换成员语义。

**Tech Stack:** macOS 15+、Swift 6、SwiftUI/AppKit；不修改文档格式。

页面多选按用户请求默认包含；Shift 再点已选页取消该页，但至少保留一个。新增选择的页面成为活动画布；取消活动页时使用剩余页面。普通点击只选当前行；普通点击活动页保留该页已有图层选择。选择变化不产生 dirty 或历史，新增页面、undo/reconcile、替换文档维持活动页面属于选集。锁定/显示/展开按钮和原位名称编辑保持独立。

- [x] 在 `SidebarSelectionTests.swift` 先覆盖页面多选、活动页回退、普通点击、历史/替换协调和重命名提交；先运行 `swift test --filter SidebarSelectionTests` 确认缺少新 API。
- [x] 修改 `EditorSession.swift`，新增 `selectedPageIDs` 及 `selectPage(_:extending:)`。修改 `LayersSidebar.swift`，页面按钮标签包含全行 padding/frame/contentShape；图层在整行背景增加选择按钮，名称和功能按钮保留各自操作；页面/图层选中态暴露给 AX。
- [x] 定向测试、完整 `swift test`、Release 编译、diff check；聚焦审查目标选择、功能按钮事件和重命名交接。
- [ ] 保存必要用户文档后退出再打包，验证 plist/签名；实窗点击文字外空白、缩进、图标并 Shift 多选，检查整行高亮与子按钮、原位命名。更新验收记录及 README，中文 Signed-off-by 本地提交，不推送。

实施结果：57 项相关测试、298 项全量测试和 Release/签名通过，审查无遗留。运行包已从暂存目录替换且保留旧包；当前窗口返回 cgWindowNotFound，未强退进程，新包待重启，实窗命中检查仍待完成，详见 `docs/development/2026-11-06-sidebar-selection.md`。
