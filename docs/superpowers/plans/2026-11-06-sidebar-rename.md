# 左侧重命名 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 页面和图层树对象通过右键可靠重命名，支持取消、单步撤销和持久化。

**Architecture:** EditorSession 扩展负责目标、草稿及事务；原生行内 NSTextField 处理焦点、确认、取消；LayersSidebar 在对应原行切换标签/输入框，复用现有图层命令菜单。无 Core/格式变化，不弹出重命名窗口。

**Tech Stack:** macOS 15+、Swift 6、SwiftUI/AppKit、Swift Testing。

### Task 1: 完成重命名交互与回归

**Files:** 新增 `EditorSession+Rename.swift`、`SidebarRenameField.swift`、`SidebarRenameTests.swift`；修改 `EditorSession.swift`、`LayersSidebar.swift`、`LayerActionsView.swift`，更新 README/验收记录。

- [x] 先写行为测试并确认缺少 API 的 RED：单个右键目标、全部节点类型、后台页面不切换、锁定/隐藏、取消/同名/redo、非法和过期请求、原生输入独立事务与保存重开。
- [x] 实现 request/name 校验及候选文档验证后的单步历史；行内输入 Enter/失焦确认及 Escape 取消，页面/图层菜单接线，AX 为 page.rename / layer.rename / rename.name；无效输入使用底部消息。
- [x] 定向测试后完整 suite 一次、Release、diff check，聚焦源码审查并处理发现；仅范围明确的中文 Signed-off-by commit。
- [ ] 保存用户最新设计，打包验证 plist/签名，在独立样例验收页面、普通图层及编组重命名、取消、撤销和保存重开；恢复用户当前设计，记录自动化/实窗验证边界。

实施结果：15 项重命名测试、292 项全量测试及 Release/签名通过。实窗已验证页面 Enter、编组 Escape/失焦/单步撤销；窗口随后不可读取，普通图层及保存重开的额外实窗检查保留为待验收，详见 `docs/development/2026-11-06-sidebar-rename.md`。用户新增文档已另存并保留打开。
