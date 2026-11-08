# Sources 目录整理与职责拆分实施计划

> **For agentic workers:** 使用 superpowers:executing-plans 按步骤在当前已确认的工作区执行；步骤用复选框记录。

**Goal:** 执行用户确认的方案 B，参考 Compositor 整理 Sources，并拆分原生图层树、工具类型和共享编辑错误。

**Architecture:** 保留 `openSketchApp → OpenSketchUI → OpenSketchCore`。按 [源码结构](../../source-structure.md) 的完整文件映射移动文件；通过完整声明的搬移拆分职责，保留行为与访问级别。

**Tech Stack:** Swift 6、Swift Package Manager、AppKit、SwiftUI、Foundation、CoreGraphics、macOS Bash 3.2。

## 全局约束

- 基线 `5ad65aa`，分支 `feat/native-prototype`，开始时工作区干净。
- 部署目标 macOS 15+；保留三个生产 target 和两个测试 target。
- 源文件名和声明名称保持不变；新增文件承接现有声明，不新增产品功能。
- 文档格式 v1、偏好键、剪贴板类型、辅助功能标识保持不变。
- 本次不安装或重启应用；运行现有行为测试，不添加绑定文件位置的测试。

## Task 1: 基线与目录移动

**Files:** `Sources/OpenSketchCore/**/*.swift`、`Sources/OpenSketchUI/**/*.swift`；映射见 `docs/source-structure.md`。

**Interfaces:** 消费现有全部 Swift 声明；产出相同 target 内的同名声明。

- [x] 运行基线 `swift test`，保存完整输出到 `/tmp/opensketch-source-structure-before-tests.log`，确认测试计数和退出码。
- [x] 按映射移动 43 个文件，保留 App 入口原位；将类型拆分前的搬移逐文件与 `git show HEAD:<旧路径>` 比较，确认字节相同。

## Task 2: 拆分声明

**Files:** 以下均相对 `Sources/OpenSketchUI/`。

- 修改：`UI/Layers/NativeLayerTree.swift`、`Editor/Session/EditorSession.swift`、`IO/Export/Exporter.swift`。
- 新增：`UI/Layers/NativeLayerTree+Coordinator.swift`、`UI/Layers/LayerTreeItem.swift`、`UI/Layers/NativeLayerOutline.swift`、`UI/Layers/LayerTreeCell.swift`、`Editor/Tools/EditorTool.swift`、`Editor/Session/EditorError.swift`。

**Interfaces:** `NativeLayerTree.Coordinator`、`LayerTreeItem`、`NativeLayerOutline`、`LayerTreeCell`、`EditorTool`、`EditorError` 保持既有名称、成员和访问级别。

- [x] 将嵌套 `Coordinator` 连同其私有 `LayerTreeMenuItem`、`LayerTreeSelectionRow` 搬入独立文件，容器改为 `extension NativeLayerTree`。
- [x] 分离 `LayerTreeItem` 和 `NativeLayerOutline`。将 `LayerTreeCell` 与私有 `LayerTreeName` 放入同一文件，保留 hitTest 和全部约束。
- [x] 将 `EditorTool` 完整搬入 `Editor/Tools/EditorTool.swift`；将 `EditorError` 搬入 `Editor/Session/EditorError.swift` 并导入 Foundation。
- [x] 核对拆分后的声明与原始代码逐字一致，允许变化仅为 import、文件分隔和容纳嵌套 Coordinator 的 extension。

## Task 3: 基准脚本与文档

**Files:** 修改 `scripts/benchmark.sh`、`README.md`、`docs/development/2026-11-06-prototype-acceptance.md`；新增 `docs/source-structure.md`。

**Interfaces:** 基准仍无参数运行，产物仍为 `build/benchmark/geometry-results.json`；编译器参数、测量方法和 JSON 不变。

- [x] 在基准脚本中以如下方式收集源码，适配嵌套目录和带空格路径：

```bash
core_sources=()
while IFS= read -r -d '' source_file; do
    core_sources+=("$source_file")
done < <(find "$repo_dir/Sources/OpenSketchCore" -type f -name '*.swift' -print0)
if [ "${#core_sources[@]}" -eq 0 ]; then
    echo 'No OpenSketchCore Swift sources found' >&2
    exit 1
fi
```

- [x] 将 `swiftc` 的平铺 glob 参数替换为 `"${core_sources[@]}"`，空数组检查先于展开，保持 Bash 3.2 `set -u` 兼容。
- [x] README 加入源码结构入口；原验收材料保留历史测量结果，更新当前运行脚本的目录发现说明。

## Task 4: 验证与交付

**Files:** 全部变更；测试文件保持原位。

- [x] 运行 `swift test`，确认与基线相同的全部测试通过；审查完整日志中的 warning/error。
- [x] 运行 `scripts/build.sh release`、`plutil -lint build/openSketch.app/Contents/Info.plist`、`codesign --verify --deep --strict build/openSketch.app`。
- [x] 运行 `scripts/benchmark.sh`，核对 1,000/10,000 节点的查询、命中和批次数量；性能数字仅作本机结果，不宣称性能变化。
- [x] 用临时带空格仓库路径运行真实基准编译，验证递归参数和路径引用；清理本次创建的临时副本。
- [x] 核对新目录覆盖全部原文件、六个新增拆分文件、原声明/访问级别一致、测试内容未变，并运行 `git diff --check`。
- [x] 在开发记录中填写实际测试和构建结果，报告工作区变更与验证边界。
