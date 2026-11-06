# 侧栏整行选择与 Shift 多选

基线 `283c82d`。原页面按钮的 padding/高度位于按钮外，普通图层仅名称按钮处理选择；图层图标、缩进、行边缘空白无法选中。Shift 图层成员切换已存在，但入口同样限于名称。

## 修改

- 页面按钮的标签包含整行 frame、padding 和矩形命中区域。
- 图层保留名称按钮，在整行背景增加透明选择按钮；图标透传命中到背景，缩进及边缘空白均参与选择。展开/隐藏/锁定按钮及原生名称输入框位于前景，独立处理操作。
- 选择仍由 EditorSession 负责，亮暗模式沿用页面/图层选中色，并向辅助功能暴露选中状态。Shift 使用当前鼠标事件的修饰键，保留既有追加/取消成员语义。
- 页面新增会话内 `selectedPageIDs`，至少保留一页；新增选择的页面成为当前画布，取消活动页时回到其他已选页。普通点击同一活动页会清除其他页面高亮，保留该页图层选择；跨页清空图层选择。
- 页面选择不修改文档或历史。新增页、替换文档、undo/reconcile 维护活动页属于选集；撤销移除活动页时保留其他有效的已选页面。页面多选不隐含跨页批量编辑或批量导出。

## 验证

2026-11-06，当前 macOS 主机：

| 检查 | 结果 |
| --- | --- |
| 四组相关测试 | 57 项通过 |
| 完整 `swift test` | UI 219 + Core 79 = 298 项通过 |
| `swift build -c release` | 通过，10.46 秒 |
| Info.plist / deep strict ad-hoc 签名 | 通过 |
| `git diff --check` | 通过 |
| 独立只读源码审查 | 无 Critical / Important / Minor 遗留 |

新增六项测试覆盖页面选择、活动页回退、普通点击、undo/替换协调、原位改名提交与撤销后保留其他页面选集。首次测试确认缺少新选择 API；活动页移除测试先复现选集丢失再修复。日志为本机 `/tmp/opensketch-sidebar-selection-{red,green,full,release,reconcile-red}.log`。

```sh
swift test --filter 'SidebarSelectionTests|SidebarRenameTests|LayerCommandTests|OrganizationControlsTests'
swift test
swift build -c release
plutil -lint build/openSketch.app/Contents/Info.plist
codesign --verify --deep --strict build/openSketch.app
```

## 运行包及实窗边界

进入任务时实窗为亮色的“未命名 3”，空白且没有未保存标记。随后多次 CUA 读取/重新绑定均返回 `cgWindowNotFound`，未强制退出用户进程或修改用户设计。因此尚未完成新版本实窗点击验证，也没有重启加载新包。

最终 Release 在独立暂存目录组包并验证签名，再替换 `build/openSketch.app`，避免覆盖正在运行的可执行文件 inode。旧包保留在 `build/backups/openSketch-before-sidebar-selection-20261106-231159.app`。新可执行文件 SHA-256：`548e162c867c55f11c66ffb9ed26f6acdbf3c9ffd39dd3d3ea090939062a6051`。未安装到 `/Applications`，未推送。

待窗口可访问后，用独立样例检查：名称外空白/图标/缩进点击、Shift 多选只切换一次及整行高亮；展开/锁定/显示不改变选择；点击原位名称编辑框可移动光标而不触发背景选择；切页保留正确的页面选集。自动化测试与源码审查不替代这些实窗命中检查。
