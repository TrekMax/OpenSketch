# 设置面板与中英文本地化验证

日期：2026-11-08。本文记录原型阶段的设置与语言功能；当时曾参考本机 Compositor 的 `f6cd2f0`。2026-11-09 已完成相关实现的独立重写，当前来源状态见 [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md)。

## 行为与实现

- 应用菜单增加“设置…”/“Settings…”（`⌘,`），打开可复用的独立设置窗口。分类侧栏和分组表单参考 Compositor，当前“通用”包含外观、语言两组。
- 外观与既有底栏、视图菜单共享 `AppAppearance`：跟随系统、亮色、暗色。语言提供跟随系统、English、简体中文；默认跟随系统，不支持的系统语言回退英语。选择立即生效并保存，重启后恢复。
- `LanguageSettings` 管理稳定语言标识和偏好；`L10n` 显式查找 `en` / `zh-Hans` 资源；`LocalizedMessage` 为动态状态保留翻译键、参数和错误，使语言切换后仍可重译已有提示。
- 两份词表各 215 项，覆盖应用菜单、工具、文档标签、页面与图层面板、检查器、导出、缩放、错误与状态提示，以及应用提供的辅助功能标签。原生 AppKit 控件和 SwiftUI 环境均接入刷新。
- 用户文件名、页面名、图层名、正文不作为翻译键。切换语言不重建工作区、不修改文档 JSON、选择和编辑对象；新建内容的默认名称按创建时语言写入。未保存文档的临时标签属于界面文字，可随语言刷新。
- 设置前台时，`⌘W` 只关闭设置；撤销、重做、复制、粘贴、重复、删除、全选和图层命令不操作后台文档。菜单验证和图层快捷键入口共用窗口判断。
- SwiftPM 资源归 `OpenSketchUI`，构建脚本复制完整资源 bundle 和应用 `InfoPlist.strings`。安装包优先使用包内资源，不依赖源码目录。未增加外部包依赖，Core 的 10 个源码文件与本轮开始时逐字节一致。

文件职责见[源码结构](../source-structure.md)，实施步骤见[计划](../superpowers/plans/2026-11-08-settings-localization.md)。

## 自动化与产物验证

环境：Apple silicon、macOS 27.2（26B123）、Apple Swift 6.4；部署目标仍为 macOS 15。

| 检查 | 结果 |
| --- | --- |
| `swift test` | UI 243 + Core 88，共 331 项通过，无编译 warning/error |
| 新增语言/设置测试 | 7 项通过：偏好和回退、显式翻译与动态参数、资源键与占位符、原生刷新与文档数据保持、窗口复用、关闭设置、后台命令隔离 |
| 词表检查 | en/zh-Hans 键和格式参数一致；英语译文无汉字；包内两份词表与源码逐字节一致 |
| `scripts/build.sh release` | 成功，最终生产构建 8.87 秒，无编译 warning/error |
| `plutil -lint` | 应用 Info.plist、两份 InfoPlist.strings、两份 Localizable.strings 通过 |
| `codesign --verify --deep --strict --verbose=2 build/openSketch.app` | 通过 |
| `/bin/bash -n scripts/build.sh`、`/bin/zsh -n scripts/build.sh` | 通过 |
| 完整 diff 空白检查 | 使用临时 Git index 包含所有新增文件，检查通过，实际 index 未改变 |
| 独立代码审查 | 修复设置前台仍可触发后台编辑命令的问题后，复核无剩余重要问题 |

新增测试先确认未实现时失败，再完成实现。关闭设置和后台编辑隔离也分别保留了失败再修复的验证过程。回归测试覆盖原有编辑、保存、导出、重命名和原生交互；仅调整依赖界面语言的断言，用户内容断言保留字面值。

可重复执行：

```sh
swift test
scripts/build.sh release
plutil -lint build/openSketch.app/Contents/Info.plist
codesign --verify --deep --strict --verbose=2 build/openSketch.app
```

完整本轮日志位于 `/tmp/opensketch-settings-full.log`、`/tmp/opensketch-settings-release.log`；临时日志不入 Git。

## 真实窗口验证

将 Release `.app` 单独复制到带空格的临时路径，更改副本 bundle ID 为 `org.opensketch.settings-validation` 并重新 ad-hoc 签名，以独立偏好执行 GUI 验收。副本不含 `.build`，实际启动和双语切换成功，验证了包内资源查找。

1. 应用菜单显示 Settings…；`⌘,` 打开设置，再次打开复用同一窗口。检查了通用侧栏、外观/语言表单及即时保存提示。
2. 中文切换 English 后，设置、主菜单、工具、检查器、导出、状态、缩放和图层树提示即时更新；已有中文页面名称保留。
3. 设置窗口中的 `⌘W` 关闭设置，主文档及页面 UUID 保持不变；编辑窗口仍为已保存状态。
4. 外观切换 Dark 即时生效。退出验证副本后重新启动，界面保持 English，外观保持 Dark，设置选择与主窗口一致。
5. 最终构建再次从 English 切换简体中文再切回 English，原文档与页面标识不变。工具栏容器的“文档标签页”/“缩放”辅助功能标签也正确更新为 Document tabs / Zoom。

验证副本已退出。用户原应用及其偏好、文档未修改；本轮产物是仓库内 `build/openSketch.app`，未安装到 `/Applications`。

## 边界

当前应用自有文案提供中英文；系统拥有的文件面板、窗口控制辅助说明及未映射的系统错误仍可能遵循 macOS 语言。后台命令隔离由原生菜单测试覆盖，GUI 额外验证了关闭设置行为。本轮未在 macOS 15 实机运行，也未重复所有历史人工验收场景；历史待验项目仍以各自记录为准。
