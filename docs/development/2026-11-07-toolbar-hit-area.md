# 顶部工具按钮点击区域

基线 `d83b0d5`。用户确认上一轮图层列表调整测试通过，并反馈顶部工具按钮只能点击图标或文字。

实窗复现：点击“画板”左侧留白无响应，点击文字后正常切换。`DocumentEditorView` 的工具按钮使用 `.plain` 样式，Label 设置了内边距与高亮背景，但没有定义覆盖留白的点击区域。

在 Button 的标签内部、padding 之后添加 `.contentShape(Rectangle())`，统一覆盖选择、画板、矩形、椭圆、文字五个工具。同步提供选中状态的辅助功能标记；沿用现有切换动作及高亮样式。

验证结果：

- 修正版 Release 已重新启动；实窗点击五个按钮左侧留白均切换到对应工具。
- 额外点击矩形顶部留白、画板底部留白、选择工具的图文间隙均成功；选中高亮与辅助功能 selected 状态一致。
- 点击画板与矩形之间的按钮外间隔不切换；最后恢复选择工具，文档没有未保存更改，外观保持“跟随系统”。
- `swift test --filter SingleCreationTests`：8 项测试通过；Release 构建通过（10.92 秒），无编译警告。
- `git diff --check`、`plutil -lint`、`codesign --verify --deep --strict` 通过。

日志：`/tmp/opensketch-toolbar-hit-{tests,release}.log`。先正常退出应用，再备份并构建 `build/openSketch.app`；备份为 `build/backups/openSketch-before-toolbar-hit-20261107-085416.app`。最终可执行文件 SHA-256：`1596702a5bf62d13009b7c2e0c9a19837b27baa398d2b10b2a0c80d4c0f11460`。
