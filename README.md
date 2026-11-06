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

- AppKit 画布与 SwiftUI 面板，简体中文界面；单窗口多文档标签、页面增加/切换、图层树、锁定与显示控制。文件菜单提供原创可编辑的“打开示例设计”。
- 支持亮色、暗色、跟随系统，默认跟随系统并记住选择。亮色参照 Sketch 的白色面板、浅灰画布与输入框、蓝紫色选中态；暗色面板与画布参照 Compositor 的中性深灰配色。原生紧凑标题工具栏左侧放新建与可滚动文档标签，右侧放缩放控件，去除额外标题行和顶部分隔线。
- 选择、画板、矩形、椭圆、文字工具；点击/拖动单次创建后回到选择工具（文字在完成/取消编辑后返回）、Shift 多选、移动、右下角缩放手柄、复制与删除。检查器编辑坐标、尺寸、旋转、填充/描边、圆角及文字排版。
- 原生 `NSTextView` 文字编辑，保存 Unicode/中文/emoji，缺失字体回退；绘制与 PNG/PDF 导出共用文字布局和变换规则。嵌套/旋转文字使用检查器编辑。
- 缩放、平移、适合窗口、100% 和网格；拖动/文字编辑事务的撤销重做、取消与脏状态；各文档独立保存状态。新建/打开直接新增标签；关闭标签、窗口或退出时按需提示保存，途中取消保留全部待关闭文档。
- `.opensketch` 目录包保存可编辑矢量值、稳定 UUID 和有序子节点；内部为 `document.json`，格式 `org.opensketch.document`、版本 1。保存前验证，采用原子包替换；对格式、大小、深度及符号链接有检查。
- 通过共享渲染器导出 PNG/PDF；选中画板导出该画板，否则导出当前页面可见内容范围。PNG 限制为最长边 16,384 像素且不超过 64,000,000 像素。
- **Sketch 仅元数据检查**：有界读取 `meta.json` 并显示四个版本字段，不导入可编辑图层，不支持无损往返。

以上是实现范围；实际验证状态见[验收记录](docs/development/2026-11-06-prototype-acceptance.md)。2026-11-06 应用基线 `0705d80` 的自动化测试为 UI 集成 23 项、核心 24 项通过，Release 包、Info.plist 和严格签名验证通过；原生主要编辑、文字提交/撤销、保存重开、关闭取消、PNG/PDF 导出与 Sketch 元数据检查已完成真实 GUI 验收，具体边界见验收记录。

后续外观与标题栏更新通过 50 项测试（UI 26、核心 24）及 Release/签名检查；另修复打开/保存面板对 `.opensketch` 目录包的类型过滤。该次 GUI 验收与锁屏造成的剩余验证范围见[外观更新记录](docs/development/2026-11-06-appearance.md)。

多文档与单次绘制更新通过 92 项测试（UI 68、核心 24）及 Release/签名检查。解锁后已完成连续新建三文档、独立编辑/撤销/缩放、关闭及退出取消、保存重开、批量打开去重和窗口重开的真实 GUI 验证；横向手势及小窗口手动调整仍待人工确认，详见[更新记录](docs/development/2026-11-06-multiple-documents.md)。

Sketch 参考亮色更新通过相同 92 项回归测试、Release/签名检查，以及真实窗口的亮暗切换、选中态和检查器外观验证，详见[亮色配色记录](docs/development/2026-11-06-sketch-light.md)。

## 操作

| 操作 | 快捷键/入口 |
| --- | --- |
| 选择 / 画板 / 矩形 / 椭圆 / 文字 | 画布获得焦点时 `V` / `F` / `R` / `O` / `T` |
| 多选 / 删除 | `Shift` 点击 / `Delete` |
| 完成 / 取消行内文字编辑 | `⌘ Return` / `Escape`；选择工具双击根级未旋转文字再次编辑 |
| 取消进行中的拖动 | `Escape` |
| 新建 / 打开 / 保存 / 另存为 | `⌘ N` / `⌘ O` / `⌘ S` / `⇧⌘ S` |
| 切换 / 关闭文档 | 点击顶部标签 / 标签关闭按钮或 `⌘ W`；关闭窗口会处理所有标签 |
| 撤销 / 重做 / 复制图层 | `⌘ Z` / `⇧⌘ Z` / `⌘ D` |
| 拷贝 / 粘贴 | `⌘ C` / `⌘ V`；图层使用 openSketch 自有剪贴板格式 |
| 平移 / 锚点缩放 | 滚动 / `⌘` 滚动或触控板捏合 |
| 适合窗口 / 实际大小 | `⌘ 1` / `⌘ 0` |
| 亮色 / 暗色 / 跟随系统 | 底部“外观”，或“视图 → 外观” |
| 新建 / 适合 / 100% / 放大缩小 | 顶部原生工具栏 |
| PNG/PDF / Sketch 检查 | 文件菜单 |

## 已知限制与验证边界

当前没有组件实例、Stack 自动布局、钢笔/节点编辑 UI、分组命令、页面重命名、完整 SVG 互操作、Sketch 可编辑导入、自动恢复、实时协作或生产签名。核心可表示并渲染 group/path，但尚无相应创作工具。文字绘制支持填充，关闭填充后不绘制字形；不支持文字描边。缩放手柄仅支持未旋转节点的右下角；旋转节点使用检查器修改尺寸。

历史使用文档值快照，暂无长度上限；大文档的 GUI 响应/内存与帧率尚未测量。部分旋转裁剪导出的范围是保守包围盒，可能有额外透明边缘。Sketch 检查同步执行、最多约 3 秒，复杂 ZIP 可能超时。原生系统提示的语言随系统环境变化。

部署目标是 macOS 15，当前测试主机为 Apple M2 Max / macOS 27.2；尚未在 macOS 15 实机验收。手动拖动中途按 Escape、独立 Dock 点击重开、原生颜色面板选色及输入法候选窗仍待验证。

## 几何基准与开发材料

```sh
scripts/benchmark.sh
```

系统 Swift 以 Release 优化编译现有核心，测量固定 1,000/10,000 节点的命中查询，校验结果并输出环境、逐批时间、median/p95 到 `build/benchmark/geometry-results.json`。这是几何查询基准，**不是 GUI 帧率**；方法与实测值见[验收记录](docs/development/2026-11-06-prototype-acceptance.md)。

- [多文档与单次绘制验收](docs/development/2026-11-06-multiple-documents.md)
- [核心 API 与文件格式](docs/development/core-api.md)
- [原型实施计划](docs/superpowers/plans/2026-11-06-native-prototype.md)
- [初期可行性评估](docs/assessment/2026-11-05-feasibility.md)、[Compositor 审计](docs/assessment/compositor-audit.md)、[替代能力矩阵](docs/assessment/replacement-matrix.md)、[Sketch 观察](docs/assessment/sketch-observations.md)（历史评估材料，不代表当前全部能力）

## 开源与来源

代码、示例与文档为本项目原创，采用 [MIT License](LICENSE)，仅使用 Apple 系统框架及系统工具，没有引入第三方源代码或包依赖。Compositor 仅作为架构参考。来源、系统依赖及商标说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。openSketch 与 Sketch 官方产品没有隶属关系。
