# 设置面板与中英文界面实施计划

用户要求参考 Compositor 增加设置菜单、面板和中英文本地化。在已完成但未提交的 Sources 整理上继续实施，保留其全部变更。

## 设计

- 应用菜单提供“设置…”/“Settings…”和 `⌘,`。设置窗口可复用，参考 Compositor 的侧栏分类与通用设置表单；首期只展示已有功能的通用分类，包含外观、语言。
- 语言选项为跟随系统、English、简体中文，默认跟随系统，不支持的系统语言回退英语；自动保存并立即刷新应用自己的 SwiftUI、AppKit 菜单、标题栏、图层树和画布提示。
- 外观继续共享 AppAppearance 和既有 appearanceMode 偏好，底栏/视图菜单与设置面板同步。
- 使用独立 LanguageSettings、L10n、en/zh-Hans Localizable.strings；资源归 OpenSketchUI 的 SwiftPM bundle，打包脚本复制 bundle，应用脱离构建目录仍能查找资源。
- 界面文字使用明确查找，动态文字使用格式参数；状态提示保留键与参数，语言切换后重新解析。用户名称和正文不作为翻译键；切换语言不重建工作区或写入文档，不改变 ID、快捷键或格式版本。
- 新建文档/页面的默认名称按创建时语言产生并作为文档数据保存；已有名称不随语言切换改写。纯 Core 的既有格式和默认值保持兼容。
- 保持 macOS 15 和 Swift 6，无第三方依赖。系统文件面板等系统拥有的界面仍受 macOS 语言影响。

## 步骤

- [x] 新增 LanguageSettingsTests，确认语言、资源、菜单及设置窗口契约在实现前失败。
- [x] 新增 Localization/LanguageSettings.swift、L10n.swift、LocalizedMessage.swift 和双语资源，接入 Package.swift。
- [x] 新增 UI/Settings/ApplicationSettingsView.swift、SettingsWindowController.swift，接入 AppController 菜单与语言刷新。
- [x] 逐项迁移静态、动态、原生界面文案；保留用户数据，补齐即时刷新路径及错误映射。
- [x] 补充构建资源复制和应用语言声明；更新现有测试中依赖界面语言的断言。
- [x] 运行定向及全量测试，检查目录/占位符/语言覆盖、Release 包与签名、脱离构建目录的双语资源查找。
- [x] 检查真实设置窗口、英文/中文切换与返回编辑窗口，记录验证证据和限制，更新 README 与源码结构。
