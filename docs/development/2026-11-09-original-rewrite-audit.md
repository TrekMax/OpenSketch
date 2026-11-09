# Compositor 相关实现独立重写审核

日期：2026-11-09。

## 审核范围

本轮针对早期参考 Compositor 的三处实现进行独立重写：

- `Sources/OpenSketchUI/Localization/LanguageSettings.swift`
- `Sources/OpenSketchUI/Localization/L10n.swift`
- `Sources/OpenSketchUI/UI/Settings/ApplicationSettingsView.swift`

同时检查了编辑器配色注释、构建脚本、第三方声明和应用包中的许可证文件。

## 重写内容

- 语言解析改为 OpenSketch 自有的语言优先级与区域标识处理，不再调用原参考实现的本地化选择流程。
- 本地化资源定位拆分为 OpenSketch 自有的资源查找和目录加载函数；保留 SwiftPM 测试资源与安装包资源两种运行环境。
- 设置页面拆分为设置分类列表和通用设置表单，界面事件、绑定、辅助功能标识和现有设置行为保持不变。
- 编辑器配色注释改为项目自身的工作区配色说明。
- 删除 Compositor 许可证文件、构建复制步骤和当前第三方代码登记；构建时主动清理旧应用包中的残留 `Licenses` 目录。

## 审核结果

| 检查 | 结果 |
|---|---|
| `swift test` | UI 243 + Core 88，共 331 项通过 |
| `scripts/build.sh release` | 通过，无编译 warning/error |
| `plutil -lint build/OpenSketch.app/Contents/Info.plist` | 通过 |
| `codesign --verify --deep --strict build/OpenSketch.app` | 通过 |
| `scripts/benchmark.sh` | 1,000/10,000 节点正确性和几何基准通过 |
| 源码版权/来源扫描 | 未发现 `Wonder Assembly LLC`、`Compositor-MIT` 或 `Adapted from Compositor` |
| 应用包许可证检查 | 不再包含 `Contents/Resources/Licenses/Compositor-MIT.txt` |
| `git diff --check` | 通过 |

## 结论

当前 OpenSketch 源码和应用包不再包含 Compositor 的改写实现、版权声明或许可证文件。历史评估和开发记录保留为过程记录，不代表当前源码依赖第三方实现。

独立重写审核通过，可以进入下一阶段 **M2 矢量 Alpha 与插件基础设计**。下一阶段先冻结插件清单、快照、能力声明、权限、事务和导出接口，再实现内置格式插件；本轮未提前加入插件运行时代码。
