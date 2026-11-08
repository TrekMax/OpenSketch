# Sources 目录整理与职责拆分验证

日期：2026-11-08。基线 `5ad65aa`，分支 `feat/native-prototype`，开始时工作区干净。用户先要求评估，再明确选择方案 B。目录与文件归属见[源码结构](../source-structure.md)，步骤见[实施计划](../superpowers/plans/2026-11-08-source-structure.md)。

## 变更

- 43 个现有源码文件在原 target 内移动；`Sources/openSketchApp/main.swift` 保持原位。
- `NativeLayerTree.swift` 从 453 行拆成桥接 19 行、协调器及私有辅助类 283 行、节点对象 10 行、原生列表 43 行、行控件及私有名称控件 106 行。行数包含 import、注释和空行。
- `EditorTool` 从 `EditorSession.swift` 提取到 `Editor/Tools/EditorTool.swift`；`EditorError` 从 `Exporter.swift` 提取到 `Editor/Session/EditorError.swift`。
- 源码由 44 个文件变为 50 个：Core 10、UI 39、App 1。SwiftPM 的实际 source 清单与磁盘递归清单完全一致。
- 几何基准使用 NUL 分隔路径递归发现 Core 源码；Bash 数组在展开前检查是否为空。编译器参数、查询场景和输出格式保持原样。
- 新增源码结构文档和 README 入口，更新原验收材料中的当前脚本说明；历史计划路径和历史测量数字保留。

## 源码等价与范围检查

先将 43 个移动后的文件逐字节对照 `git show HEAD:<旧路径>`，全部相同，再实施声明拆分。拆分完成后再次检查：

- 41 个原文件（含 App 入口）的内容与基线逐字节一致。
- 其余三个文件的全部原声明与拆出文件对照一致，变化仅包括 import、文件分隔，以及用 `extension NativeLayerTree` 承接原嵌套 Coordinator。
- `NativeLayerTree.Coordinator` 名称不变；`LayerTreeMenuItem`、`LayerTreeSelectionRow` 与协调器同文件，`LayerTreeName` 与行控件同文件，私有访问级别保持原样。
- `Package.swift`、`Tests`、`Resources` 内容与基线一致；没有新增依赖或修改文档格式。
- 使用临时 Git index 检查包括新增文件在内的完整 diff，识别出 43 项源码重命名，其中 40 项为 100% 相同；无未匹配删除，空白检查通过。实际 Git index 保持原样。

## 实际验证

环境：Apple silicon、macOS 27.2（26B123）、Apple Swift 6.4；部署目标仍为 macOS 15。

| 检查 | 结果 |
| --- | --- |
| 整理前 `swift test` | UI 236 + Core 88，共 324 项通过 |
| 整理后 `swift test` | 相同 324 项通过，无编译 warning/error |
| `scripts/build.sh release` | 成功，生产构建 12.31 秒，无编译 warning/error |
| `plutil -lint build/openSketch.app/Contents/Info.plist` | 通过 |
| `codesign --verify --deep --strict --verbose=2 build/openSketch.app` | 通过 |
| `scripts/benchmark.sh` | 1,000/10,000 节点两组正确性断言均通过 |
| 带空格的临时仓库路径 | 从 `/tmp` 使用 `/bin/bash`、`/bin/zsh` 分别运行，真实编译及两组基准通过 |
| 空 Core 目录 | 系统 Bash 返回 1，明确提示缺失源码，无 nounset 数组错误 |
| `/bin/bash -n scripts/benchmark.sh`、完整 diff 空白检查 | 通过 |

基准每组预热 3 批、测量 20 批，每批 100 次查询、75 次命中，累计校验 1,725 次命中。本轮主仓库直接运行的每批时间：

| 节点数 | median | p95 |
| --- | --- | --- |
| 1,000 | 4.577 ms | 5.248 ms |
| 10,000 | 42.942 ms | 44.559 ms |

这些是单次本机几何查询结果，不用于声明性能提升，也不是 GUI 帧率。完整结果位于 Git 忽略的 `build/benchmark/geometry-results.json`。带空格路径的临时源码副本在验证后已清理。

完整测试/构建/基准日志位于 `/tmp/opensketch-source-structure-before-tests.log`、`/tmp/opensketch-source-structure-after-tests.log`、`/tmp/opensketch-source-structure-release.log`、`/tmp/opensketch-source-structure-benchmark.log`；临时日志不入 Git。

## 验证边界

本次复用现有原生视图、输入、拖放、重命名、撤销、保存和导出自动化测试，没有重新执行真实窗口人工操作。Release 只更新仓库内 `build/openSketch.app`，未安装到 `/Applications`，未重启用户应用；未进行 macOS 15 实机验收。
