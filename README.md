# openSketch

面向 macOS 的开源矢量 UI 设计软件。目前已实现 **0.1.0 原生初始原型**，包含可构建的本地可执行文件和 `.app`，用于验证编辑模型、文字、持久化与导出。完整替代 Sketch 仍是后续目标。

## 构建与运行

需要 macOS 15+、支持 Swift 6 的 Xcode/系统工具链，无第三方包依赖。在仓库根目录执行：

```sh
swift test
scripts/build.sh release
plutil -lint build/openSketch.app/Contents/Info.plist
codesign --verify --deep --strict build/openSketch.app
open build/openSketch.app
```

`scripts/build.sh debug` 构建调试包；`swift build -c release --product openSketch` 只构建命令行可执行产物。`open Package.swift` 可在 Xcode 打开工程。构建脚本支持从其他目录调用其绝对路径，产物固定写入仓库的 `build/openSketch.app`，使用本地 ad-hoc 签名。没有安装到 `/Applications`。

## 已实现范围

- AppKit 画布与 SwiftUI 面板，简体中文界面；单文档窗口、页面增加/切换、图层树、锁定与显示控制。文件菜单提供原创可编辑的“打开示例设计”。
- 选择、画板、矩形、椭圆、文字工具；点击/拖动创建、Shift 多选、移动、右下角缩放手柄、复制与删除。检查器编辑坐标、尺寸、旋转、填充/描边、圆角及文字排版。
- 原生 `NSTextView` 文字编辑，保存 Unicode/中文/emoji，缺失字体回退；绘制与 PNG/PDF 导出共用文字布局和变换规则。嵌套/旋转文字使用检查器编辑。
- 缩放、平移、适合窗口、100% 和网格；拖动/文字编辑事务的撤销重做、取消与脏状态；新建/打开/关闭/退出前的保存提示。
- `.opensketch` 目录包保存可编辑矢量值、稳定 UUID 和有序子节点；内部为 `document.json`，格式 `org.opensketch.document`、版本 1。保存前验证，采用原子包替换；对格式、大小、深度及符号链接有检查。
- 通过共享渲染器导出 PNG/PDF；选中画板导出该画板，否则导出当前页面可见内容范围。PNG 限制为最长边 16,384 像素且不超过 64,000,000 像素。
- **Sketch 仅元数据检查**：有界读取 `meta.json` 并显示四个版本字段，不导入可编辑图层，不支持无损往返。

以上是实现范围；实际验证状态见[验收记录](docs/development/2026-11-06-prototype-acceptance.md)。2026-11-06 自动化测试为 UI 集成 14 项、核心 23 项通过，Release 包、Info.plist 和严格签名验证通过；真实 GUI 交互验收受到本机锁屏阻塞，尚未完成。

## 操作

| 操作 | 快捷键/入口 |
| --- | --- |
| 选择 / 画板 / 矩形 / 椭圆 / 文字 | 画布获得焦点时 `V` / `F` / `R` / `O` / `T` |
| 多选 / 删除 | `Shift` 点击 / `Delete` |
| 完成 / 取消行内文字编辑 | `⌘ Return` / `Escape`；选择工具双击根级未旋转文字再次编辑 |
| 取消进行中的拖动 | `Escape` |
| 新建 / 打开 / 保存 / 另存为 | `⌘ N` / `⌘ O` / `⌘ S` / `⇧⌘ S` |
| 撤销 / 重做 / 复制图层 | `⌘ Z` / `⇧⌘ Z` / `⌘ D` |
| 拷贝 / 粘贴 | `⌘ C` / `⌘ V`；图层使用 openSketch 自有剪贴板格式 |
| 平移 / 锚点缩放 | 滚动 / `⌘` 滚动或触控板捏合 |
| 适合窗口 / 实际大小 | `⌘ 1` / `⌘ 0` |
| PNG/PDF / Sketch 检查 | 文件菜单 |

## 已知限制与验证边界

当前没有组件实例、Stack 自动布局、钢笔/节点编辑 UI、分组命令、页面重命名、完整 SVG 互操作、Sketch 可编辑导入、自动恢复、实时协作或生产签名。核心可表示并渲染 group/path，但尚无相应创作工具。缩放手柄仅支持未旋转节点的右下角；旋转节点使用检查器修改尺寸。

历史使用文档值快照，暂无长度上限；大文档的 GUI 响应/内存与帧率尚未测量。部分旋转裁剪导出的范围是保守包围盒，可能有额外透明边缘。Sketch 检查同步执行、最多约 3 秒，复杂 ZIP 可能超时。原生系统提示的语言随系统环境变化。

部署目标是 macOS 15，当前测试主机为 Apple M2 Max / macOS 27.2；尚未在 macOS 15 实机验收。真实窗口操作、文件面板、导出目视效果和输入法候选窗仍待验证。

## 几何基准与开发材料

```sh
scripts/benchmark.sh
```

系统 Swift 以 Release 优化编译现有核心，测量固定 1,000/10,000 节点的命中查询，校验结果并输出环境、逐批时间、median/p95 到 `build/benchmark/geometry-results.json`。这是几何查询基准，**不是 GUI 帧率**；方法与实测值见[验收记录](docs/development/2026-11-06-prototype-acceptance.md)。

- [核心 API 与文件格式](docs/development/core-api.md)
- [原型实施计划](docs/superpowers/plans/2026-11-06-native-prototype.md)
- [初期可行性评估](docs/assessment/2026-11-05-feasibility.md)、[Compositor 审计](docs/assessment/compositor-audit.md)、[替代能力矩阵](docs/assessment/replacement-matrix.md)、[Sketch 观察](docs/assessment/sketch-observations.md)（历史评估材料，不代表当前全部能力）

## 开源与来源

代码、示例与文档为本项目原创，采用 [MIT License](LICENSE)，仅使用 Apple 系统框架及系统工具，没有引入第三方源代码或包依赖。Compositor 仅作为架构参考。来源、系统依赖及商标说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。openSketch 与 Sketch 官方产品没有隶属关系。
