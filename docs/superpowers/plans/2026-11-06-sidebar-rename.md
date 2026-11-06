# 左侧重命名 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 页面和图层树对象通过右键可靠重命名，支持取消、单步撤销和持久化。

**Architecture:** EditorSession 扩展负责捕获/校验目标与事务；独立 sheet 持有草稿；LayersSidebar 接页面和图层右键入口，复用现有图层命令菜单。无 Core/格式变化。

**Tech Stack:** macOS 15+、Swift 6、SwiftUI/AppKit、Swift Testing。

### Task 1: 完成重命名交互与回归

**Files:** 新增 `EditorSession+Rename.swift`、`SidebarRenameSheet.swift`、`SidebarRenameTests.swift`；修改 `LayersSidebar.swift`、`LayerActionsView.swift`，更新 README/验收记录。

- [ ] 先写行为测试并确认缺少 API 的 RED：单个右键目标、全部节点类型、后台页面不切换、锁定/隐藏、取消/同名/redo、非法和过期请求、原生输入独立事务与保存重开。
- [ ] 实现 request/name 校验及候选文档验证后的单步历史；sheet 输入和确认/取消，页面/图层菜单接线，AX 为 page.rename / layer.rename / rename.name / rename.confirm / rename.cancel / rename.error。
- [ ] 定向测试后完整 suite 一次、Release、diff check，聚焦源码审查并处理发现；仅范围明确的中文 signed commit。
- [ ] 保存用户最新设计，打包验证 plist/签名，在独立样例验收页面、普通图层及编组重命名、取消、撤销和保存重开；恢复用户当前设计，记录自动化/实窗验证边界。
