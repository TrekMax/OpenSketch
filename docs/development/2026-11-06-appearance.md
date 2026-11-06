# 外观与原生标题栏更新

基于 `2bd5b93`，完成用户新增的亮色 / 暗色 / 跟随系统，以及参照 Compositor 调整暗色配色、标题栏布局的要求。

## 实现

- `AppAppearance` 使用 `UserDefaults` 的 `appearanceMode` 保存 `system/light/dark`；缺失或未知值回退跟随系统。通过 `NSApplication.appearance` 统一窗口、SwiftUI 面板和原生弹窗；跟随系统清除应用外观覆盖，不改系统设置。
- 状态栏 Picker 与“视图 → 外观”共用状态。切换外观不更换文档或写入文档历史。AppKit 画布在有效外观变化时重绘。
- `EditorPalette` 的暗色面板 RGB 为 0.14，画布背景为 0.105；浅色保留系统背景，工具及图层选中态使用中性灰。仅影响编辑器表面，不改变作品填充或导出颜色。
- 标题栏改用 AppKit `NSToolbar` + `unifiedCompact`：保留系统窗口按钮、拖动与缩放机制，左侧新建和文档名胶囊，右侧适合 / 100% / 放大 / 缩小；下方 42 pt 工具行。隐藏独立标题文字及原生顶部分隔线。文档名胶囊显示未保存标记；已有控件的 AX ID 保留。
- 缩放按钮复用画布缩放逻辑，以可见画布中心为锚点，保留 5%–800% 范围。

参考为只读检查的 Compositor `f6cd2f0` 与 `/Applications/Compositor.app` 实际窗口：`ContentView.swift` 的 0.14 背景、`Rendering/EditorCanvas.swift` 的 0.105 surround、`CompositorApp.swift` 的紧凑原生工具栏。仅参考布局及颜色数值，没有复制第三方实现。

## 验收中发现的文件面板问题

旧 `UTType(filenameExtension: "opensketch")` 默认要求符合 `.data`，而文件格式声明为 `.package`；在本机解析成 `dyn.ah62d4rv4ge8086dfr33003pyqrya`，导致已保存文档在打开面板灰显。打开与保存现在共用显式 `conformingTo: .package` 的类型。回归测试先失败，再修复通过。

此前原型记录中的保存/重开是当时观察；本次在已有类型注册的环境明确重现灰显，因此不能据此前结果断言过滤始终正确。该修复不改变文档格式或现有文件。

## 验证证据

| 项目 | 结果 |
| --- | --- |
| 完整 `swift test` | UI 26 项 + 核心 24 项通过，无编译 warning/error；`/tmp/opensketch-appearance-final-tests.log` |
| 偏好行为 | 默认/未知值回退、暗色保存并重建设置对象恢复、切换亮色、跟随系统清除覆盖通过；先记录真实失败的日志为 `/tmp/opensketch-appearance-red.log` |
| 包类型过滤回归 | 修复前不符合 `.package` 的断言失败；`/tmp/opensketch-package-filter-red.log`，最终完整测试通过 |
| Release | `scripts/build.sh release` 成功，5.25 秒；`/tmp/opensketch-appearance-final-release.log` |
| plist / 签名 / diff | `plutil -lint`、`codesign --verify --deep --strict`、`git diff --check` 通过 |
| 真实 GUI 外观 | 初始系统模式显示亮色；Picker 切暗色、菜单切亮色立即更新画布及面板；退出重启仍为暗色。绘制矩形后切换外观，Command-Z 直接撤销矩形，证明未插入外观历史 |
| Compositor 配色与标题栏 | 后续 Release 实际截图和 AX 确认中性深灰面板、更深画布、原生紧凑标题工具栏、新建/文档名/缩放控件及稳定 ID；未再出现独立标题文字行 |
| 文件面板 | 修复前实际截图确认 `.opensketch` 灰显，修复后 AX 确认打开面板允许选择目录包；最终点击打开前 Mac 锁屏，因此完整打开步骤未复测 |

尚未验证最终原生工具栏版本的全屏进出、小窗口边界、每个缩放按钮点击及新暗色配色切回亮色后的完整截图。此前临时布局的全屏进入观察不作为最终版本通过证据。没有切换 macOS 全局外观进行实时跟随系统验收；跟随系统由原生外观继承实现并有清除覆盖的自动化断言。macOS 15 实机仍未验证。

本次只操作独立验收文档；启动前保存了此前验收文档的现有状态。`research/local/preserved-session-20261106.opensketch` 用户原始设计保留副本未改动。Compositor 参考仓库仍为 `f6cd2f0` 且干净。仅更新仓库内 `build/openSketch.app`，未安装到 `/Applications`，未推送。
