# 原生初始原型验收记录（2026-11-06）

本轮交付包含 SwiftPM 核心、原生编辑界面和本地 `build/openSketch.app`（0.1.0，build 1）。最终应用基线为 `feat/native-prototype` 的 `0705d80`，包含文字复制提交顺序、无填充文字、大圆角渲染、菜单撤销和行内文字提交修复。自动化行为测试与 Release 打包验证通过；真实 GUI 交互验收状态见下文。完整 Sketch 替代能力仍需后续实现与验收。

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

以下最终测试和 Release 结果对应应用源码基线 `0705d80`；之后只补 Canvas 鼠标事件取消回归与文档，未修改产品源码或重复 Release 构建。构建入口及几何基准入口的历史检查另行标明。

| 检查 | 实际结果与证据 |
| --- | --- |
| 完整 `swift test` | 最终运行通过：UI 集成 23 项（0.613 s）、核心 24 项（0.082 s）；日志 `/tmp/opensketch-final-fix-delivery-tests.log`，未发现 warning/error |
| Release bundle | `scripts/build.sh release` 成功（5.15 s）；日志 `/tmp/opensketch-final-fix-complete-release.log` |
| Info.plist / 签名 | 最终 Release 的 plist 合法，`org.opensketch.document` 包类型及 15.0 部署目标已验证；`codesign --verify --deep --strict --verbose=2` 返回 valid on disk / satisfies its Designated Requirement；`codesign -dv` 确认 Signature=adhoc |
| 构建入口（历史基线 `44ef0ca`） | 已从 `/tmp` 用绝对路径构建，并通过含空格的仓库目录符号链接构建；日志 `/tmp/opensketch-ui-space-build.log` |
| 基准入口（历史基线 `a1767fe`） | 直接执行、Bash 跨目录执行、Zsh 跨目录且仓库路径含空格执行；均成功；Bash/Zsh 语法检查通过；非法参数退出 2 且保留上次结果 |

行为覆盖包括：递归旋转/命中/裁剪与隐藏锁定祖先、顺序和父子选择；拖动撤销事务、Escape 取消后的坐标和脏状态；保存重开保留 UUID/路径/中文 emoji；格式/版本/重复 ID/非有限数值/资源上限/符号链接拒绝；失败保存保留原文件；页面撤销后的创建及粘贴、插入失败时内容与选择保持；复制保持组合顺序；Unicode 与缺字体现有布局回退；透明组像素与导出分配上限；原创示例编解码；Sketch ZIP 元数据读取成功/无效/超限及输入不被修改。

最终修复先新增断言并确认失败，再修改产品源码。直接调用侧栏使用的 session 复制入口，真实 `NSTextView` 从 A 编辑为 B 后，原件与副本均为 B，两次撤销依次删除副本和恢复 A。无填充文字在直接离屏画布绘制、PNG、PDF 再栅格化中均无可见像素，显式默认黑色仍可绘制，布局测量保持；文字描边仍不支持。200×20、radius=100 的矩形采用半短边 10 的均匀圆角，核心命中与 PNG 对应点像素一致。定向 red / green 日志分别为 `/tmp/opensketch-final-fix-red.log`（UI 3 项共 5 个断言失败）和 `/tmp/opensketch-final-fix-green.log`（UI 3 项、核心 1 项通过）。新增核心大圆角命中测试在修复前已通过，用于保留正确的现有规则。

真实窗口验收还发现并修复两个输入路由问题（`0705d80`）：文档撤销/重做菜单显式路由到文档历史，当前 NSTextView/字段编辑器继续使用原生 UndoManager；行内 Command-Return/Enter 使用专用 NSTextView 键盘处理，marked text 交回原生处理。菜单/文本上下文回归先产生 11 个失败断言；Command-Return 的 keyDown 和 performKeyEquivalent 回归先产生 7 个失败断言，修复后全部通过，Escape 事件取消也通过。另验证 marked text 期间不提前提交，unmark 后提交为一个文档事务。这些离屏回归补足源码验证，真实输入结果见下一节。

这些状态、文件、几何和渲染服务的自动化验证不能代替下文的实际交互验收。

## 真实 GUI 验收状态

早期启动检查曾受 `IOConsoleLocked = Yes` 阻塞；桌面解锁后已在最终 `0705d80` Release 包上进行原生窗口、AX/截图及实际键盘/鼠标验收。菜单撤销和 Command-Return 的实际缺陷已修复，并在该包复测通过。早期后台 NSWindow 诊断不作为 GUI 通过证据。

| 验收步骤 | 当前状态 | 实际结果与边界 |
| --- | --- | --- |
| 启动 bundle，目视原生窗口与布局 | 通过 | 解锁桌面实际显示原生窗口、工具栏、图层树、画布和检查器 |
| 新建 → 矩形 → 移动 → 缩放 | 通过 | 实际绘制 125×75，移动至 (94,117)，右下角手柄缩放至 175×105；工具栏撤销/重做正确 |
| 文档键盘撤销/重做 | 通过（最终包复测） | 矩形 (114,137) → Command-Z 回 (94,117) → Command-Shift-Z 回 (114,137) |
| 中文 + emoji → 提交 → 保存 → 重开 | 通过 | 粘贴中文/emoji 后显示完整；Command-S 通过原生保存面板保存，重新用打开面板选择 `.opensketch` 后图层与 Unicode 保留；另解析保存 JSON 核对几何/文字/颜色。输入法候选窗仍未验收 |
| 行内文字原生撤销/重做与 Command-Return | 通过（最终包复测） | 粘贴“中文验收 ✅ openSketch”，Command-Z 恢复旧 Unicode；重做后 Command-Return 移除 editor.inlineText 并更新检查器文字 |
| 侧栏复制当前行内文字及两步撤销 | 通过（最终包复测） | 待提交文字“复制验收 ✨”经侧栏复制后原件/副本均为新内容；第一次撤销仅删副本并保留新文字，第二次撤销恢复此前“中文验收”内容 |
| Escape 取消文字编辑 | 通过（最终包复测） | 实际 Escape 取消后保留原文 |
| 修改填充 → 导出 PNG/PDF → 目视检查 | 填充开关及导出通过 | 实际填充开关关闭/开启将蓝色矩形恢复为白色并保存 RGBA 1/1/1/1；文件菜单导出 400×235 PNG 和一页 400×235 PDF，灰底 PNG 预览与原生 PDFKit 预览核对中文/emoji、白矩形和画布位置，PDF 文字提取成功；已观察到 Colors 浮窗，但任意面板选色未验收 |
| 拖动中 Escape 恢复位置及脏状态 | 事件回归通过，手动中途取消未验收 | CanvasView 实际 NSEvent mouseDown → mouseDragged 已改变坐标并变脏 → Escape keyDown → mouseUp，验证恢复坐标/干净/无撤销重做条目；工具拖动与按键串行，不能证明真实 GUI 中途取消 |
| Sketch 检查显示 196 且标明仅元数据 | 通过 | 真实样本显示 196 / 2026.3.1 / 234013 / 99，并明确仅元数据、不能可编辑导入，当前文档不变 |
| 脏文档关闭 → 取消保留当前编辑 | 通过（最终包复测） | 移动至 (134,157) 后 Command-W 显示保存/取消/不保存；取消保留窗口和坐标，再 Command-Z 回 (114,137) |
| 关闭窗口后重开 | 重开行为已观察，独立 Dock 点击未验收 | 调用关闭后再次唤起显示同一文档；没有独立 Dock 图标点击证据 |

GUI 仅新建本地验收文档。PNG/PDF 及 `*-png-preview.png` / `*-pdf-preview.png` 保留在 `research/local/`，预览未修改导出原文件。原有用户设计已保存为 `research/local/preserved-session-20261106.opensketch`，解析确认为两页/七个根图层；验收使用独立 `research/local/prototype-acceptance-20261106.opensketch`，不改动保留副本。结束前最后一次人工测试移动到 (214,237)，随后桌面再次锁屏，未完成窗口中的撤销或用户设计重新打开；该未保存移动仅属于验收文档，已存验收包仍为 (114,137)，用户设计的独立文件保持安全。实际检查的本地 Sketch fixture 字段为 `version=196`、`appVersion=2026.3.1`、`build=234013`、`compatibilityVersion=99`；这些值只说明元数据检查，不证明可编辑导入。

补充的 Canvas 事件回归未修改产品源码：`swift test --filter canvasEscapeDuringMouseDrag` 一次通过（0.068 s），日志 `/tmp/opensketch-final-fix-canvas-escape.log`。这是正确既有逻辑的覆盖补充，没有声称发生 red → green 产品修复。随后完整测试 23 + 24 项通过。

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

实现包含稳定矢量值、原子本地保存、原生基本编辑、共享变换/文字渲染与 PNG/PDF 导出。核心和界面源码已分别审阅；页面撤销后插入、组合顺序、描边/裁剪选择范围及像素分配上限问题已在 `44ef0ca` 修复。最终审阅发现的侧栏复制旧文字、关闭文字填充仍绘制和超大圆角绘制/命中不一致问题已在 `a9f1d90` 修复；实际窗口发现的菜单撤销与 Command-Return 提交问题已在 `0705d80` 修复，均有真实 red → green 回归验证。

仍无组件实例、Stack 求解、钢笔/节点 UI、分组命令、页面重命名、完整 SVG 互操作、Sketch 可编辑导入、自动恢复、实时协作或生产签名。行内文字只支持根级未旋转对象；旋转尺寸使用检查器，手柄仅右下角。历史快照暂无数量上限。部分旋转裁剪的导出范围可能含额外透明边缘。Sketch 检查有约 3 秒同步上限。大文档 GUI 性能、macOS 15 运行与输入法候选窗均未验收。

交付前使用 `git -C ../Compositor rev-parse HEAD` 和 `git -C ../Compositor status --porcelain` 确认参考仓库仍为 `f6cd2f05525e7ca61d680cd221a690b796ef21d2`，工作区干净。
