# 原生初始原型验收记录（2026-11-06）

本轮交付包含 SwiftPM 核心、原生编辑界面和本地 `build/openSketch.app`（0.1.0，build 1）。实现基线为 `feat/native-prototype` 的 `44ef0ca`；后续文档与基准脚本不修改应用/核心代码。结论是自动化行为测试与 Release 打包验证通过，**真实 GUI 交互验收被锁屏阻塞，尚未完成**。完整 Sketch 替代能力仍需后续实现与验收。

## 环境与产物

| 项目 | 记录 |
| --- | --- |
| 硬件 | Apple M2 Max，arm64，34,359,738,368 字节内存（32 GiB） |
| 操作系统 | macOS 27.2，build 26B123 |
| Xcode | 27.1，build 27A9275 |
| Swift | Apple Swift 6.4，swiftlang-6.4.0.34.1 / clang-2100.3.34.1；项目使用 Swift 6 语言模式 |
| 部署目标 | macOS 15.0；尚未在 macOS 15 系统运行验收 |
| Bundle | `build/openSketch.app`；`org.opensketch.app`；0.1.0（1）；本地 ad-hoc 签名 |
| 原生文件 | `.opensketch` 目录包 / `document.json` / `org.opensketch.document` / version 1 |
| 外部包 | 无；Apple 系统框架及系统工具依赖见[来源说明](../../THIRD_PARTY_NOTICES.md) |

复现命令（仓库根目录）：

```sh
swift test
scripts/build.sh release
plutil -lint build/openSketch.app/Contents/Info.plist
plutil -p build/openSketch.app/Contents/Info.plist
codesign --verify --deep --strict build/openSketch.app
open build/openSketch.app
scripts/benchmark.sh
```

产物保留在 Git 忽略的 `build/`，未安装到 `/Applications`，未推送或发布。`open` 命令只是启动入口，不能代替真实交互验收。

## 自动化与构建证据

以下命令及结果对应应用基线 `44ef0ca`。后续仅增加文档和独立基准程序，应用与核心源码保持不变。

| 检查 | 实际结果与证据 |
| --- | --- |
| 完整 `swift test` | 最终运行通过：UI 集成 14 项（0.258 s）、核心 23 项（0.083 s）；日志 `/tmp/opensketch-parent-tests-final.log`，未发现 warning/error |
| Release bundle | `scripts/build.sh release` 成功；日志 `/tmp/opensketch-ui-review-release-bundle.log`；此前 Release 可执行构建也已通过 |
| Info.plist / 签名 | 最终 Release 的 plist 合法、原生包类型及 15.0 部署目标已验证，`codesign --verify --deep --strict` 通过；交付前复查仍通过 |
| 构建入口 | 已从 `/tmp` 用绝对路径构建，并通过含空格的仓库目录符号链接构建；日志 `/tmp/opensketch-ui-space-build.log` |
| 本轮基准入口 | 直接执行、Bash 跨目录执行、Zsh 跨目录且仓库路径含空格执行；均成功；Bash/Zsh 语法检查通过；非法参数退出 2 且保留上次结果 |

行为覆盖包括：递归旋转/命中/裁剪与隐藏锁定祖先、顺序和父子选择；拖动撤销事务、Escape 取消后的坐标和脏状态；保存重开保留 UUID/路径/中文 emoji；格式/版本/重复 ID/非有限数值/资源上限/符号链接拒绝；失败保存保留原文件；页面撤销后的创建及粘贴、插入失败时内容与选择保持；复制保持组合顺序；Unicode 与缺字体现有布局回退；透明组像素与导出分配上限；原创示例编解码；Sketch ZIP 元数据读取成功/无效/超限及输入不被修改。

这些是状态、文件、几何和渲染服务的自动化验证，不等于鼠标、菜单、输入法及原生文件面板已经完成实机交互验收。

## 真实 GUI 验收状态

使用原生 macOS CUA/AX 与截图尝试启动并读取窗口，返回 `cgWindowNotFound`；随后 `ioreg -n Root -d1` 确认 `IOConsoleLocked = Yes`，交付前复查仍处于锁屏状态。诊断版运行日志记录到可见 NSWindow，但不能据此确认解锁桌面上的布局或输入可用。诊断源码与进程已清理，最终包是无诊断代码的 Release。以下项目需在桌面解锁后实际执行。

| 验收步骤 | 当前状态 | 已有相关证据 |
| --- | --- | --- |
| 启动 bundle，目视原生窗口与布局 | 锁屏阻塞/未验收 | 仅进程及诊断 NSWindow 创建证据 |
| 新建 → 矩形 → 移动 → 缩放 → 撤销/重做 | 待执行 | 状态/几何集成测试，不是输入事件验收 |
| 输入中文 + emoji → 提交 → 保存 → 重开 | 待执行 | 模型/布局/编解码测试；输入法候选窗未验收 |
| 修改填充 → 导出 PNG/PDF → 目视检查 | 待执行 | 共享渲染器、像素与分配上限测试 |
| 拖动中 Escape 恢复位置及脏状态 | 待执行 | Session 取消回归通过；真实 Canvas 事件路由待验收 |
| Sketch 检查显示 196 且标明仅元数据 | 待执行 | 元数据解码与有界 ZIP 测试；历史本地 fixture 的字段如下 |
| 脏文档关闭 → 取消保留当前编辑 | 待执行 | 取消/脏状态测试；系统提示面板待验收 |
| 关闭窗口后从 Dock 重开 | 待执行 | 已实现 reopen 委托；真实交互待验收 |

后续 GUI 验收只创建新的本地测试文档，不修改用户原有文件。历史自建 Sketch fixture 观察值为 `version=196`、`appVersion=2026.3.1`、`build=234013`、`compatibilityVersion=99`；这些值只说明元数据检查，不证明可编辑导入。

## 可复现几何基准

源码：[benchmark.sh](../../scripts/benchmark.sh)、[GeometryBenchmark.swift](../../scripts/GeometryBenchmark.swift)。运行 `scripts/benchmark.sh` 会使用系统 `xcrun swiftc` 将当前 `Sources/OpenSketchCore/*.swift` 与测量程序一起编译，参数为 `-swift-version 6 -O -whole-module-optimization -target arm64-apple-macosx15.0`（Intel 主机自动使用 x86_64），SDK 由 `xcrun --sdk macosx --show-sdk-path` 选择。二进制及 JSON 存于 `build/benchmark/`；成功后替换 `geometry-results.json` 并打印到标准输出，失败不覆盖上次 JSON。

场景是 1,000 或 10,000 个扁平矩形节点：固定 UUID，100 列，节点 20×16，网格间距 30×24，索引 `%3==1` 的节点旋转 15°。每批固定 100 次顺序查询：索引 `%4==0` 查询 (-1000,-1000)，其余查询节点 `(i*97)%count` 的中心，即 75 次命中、25 次未命中。逐次校验返回 UUID，并累计校验包括预热的 1,725 次命中，避免仅计时未使用的结果。

每个规模先预热 3 批，随后采样 20 批，用单调时钟 `DispatchTime.uptimeNanoseconds` 计时。计时包括查询、断言及计数，不包括场景构建、环境读取或 JSON 编码。median 为排序后第 10/11 项的平均，p95 为 nearest-rank 第 19 项。JSON 保留 20 个原始采样及设备/编译器信息。该规模测试的是当前线性遍历命中实现；没有渲染或 GUI 操作，不能换算为 GUI FPS，也不代表复杂嵌套/路径/文字文档的性能。

2026-11-06 首次直接运行结果（未修改的 `44ef0ca` 核心，同上设备）：

| 节点数 | 每批查询 | median ms/批 | p95 ms/批 | 校验命中（含预热） |
| --- | --- | --- | --- | --- |
| 1,000 | 100 | 4.5970625 | 5.343 | 1,725 |
| 10,000 | 100 | 42.586479 | 46.7005 | 1,725 |

本地原始首次输出另保留为 `build/benchmark/geometry-results-initial.json`；跨目录 Bash 输出为 `/tmp/opensketch-benchmark-cwd.json`，含空格路径 Zsh 输出为 `/tmp/opensketch-benchmark-spaced-zsh.json`。对三次输出独立重算 median/p95 并检查命中数，全部一致。`xcrun vtool -show-build build/benchmark/geometry-benchmark` 确认 `minos 15.0`。后续入口检查会重新测量并覆盖默认 JSON，数值随调度与系统负载变化，无性能阈值承诺。

## 范围、审阅与后续验收

实现包含稳定矢量值、原子本地保存、原生基本编辑、共享变换/文字渲染与 PNG/PDF 导出。核心和界面源码已分别审阅；界面审阅发现的页面撤销后插入、组合顺序、描边/裁剪选择范围及像素分配上限问题已在 `44ef0ca` 修复并由回归测试验证。

仍无组件实例、Stack 求解、钢笔/节点 UI、分组命令、页面重命名、完整 SVG 互操作、Sketch 可编辑导入、自动恢复、实时协作或生产签名。行内文字只支持根级未旋转对象；旋转尺寸使用检查器，手柄仅右下角。历史快照暂无数量上限。部分旋转裁剪的导出范围可能含额外透明边缘。Sketch 检查有约 3 秒同步上限。大文档 GUI 性能、macOS 15 运行与输入法候选窗均未验收。

交付前使用 `git -C ../Compositor rev-parse HEAD` 和 `git -C ../Compositor status --porcelain` 确认参考仓库仍为 `f6cd2f05525e7ca61d680cd221a690b796ef21d2`，工作区干净。
