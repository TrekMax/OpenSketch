# 缩放菜单与参数检查器

2026-11-06，基线 `a8d23e7`，在 `feat/native-prototype` 延续开发。用户要求缩短缩放滑条、增加适合画布/实际尺寸下拉、点击缩放图标后看到倍率；随后提供 Sketch 检查器截图，要求参考其布局和拖动数值交互，导出面板延后。

## 缩放

工具栏使用 96 pt 原生滑条、8 pt 间距和 72 pt 百分比下拉按钮，总宽 176 pt。原独立“适合”按钮并入菜单，提供“适合画布”“实际尺寸（100%）”及 25/50/100/200/400/800% 选项。保留 5%–800% 连续滑动和拖动时悬浮比例；百分比按钮常显，放大/缩小及其他缩放入口同步更新。底栏统一四舍五入，修正约 29.8% 时底栏 29%、滑条 30% 的差异。

菜单激活时解析当前文档，复用原生滑条的 Observation 反馈链，保留同一 runloop 倍率返回上次 SwiftUI 值时的同步修复。倍率不进入文档历史。`⌘0` / `⌘1` 的入口与 [Sketch 官方 Canvas 文档](https://www.sketch.com/docs/interface-and-settings/the-mac-app-interface/the-canvas/) 一致。

提交 `58ab889`、`dd9bbdc`。真实 RED 日志 `/tmp/opensketch-task1-red.log` 捕获旧滑条 160 pt、缺少菜单等 12 个问题；GREEN：OrganizationControlsTests 18 项、WorkspaceIntegrationTests 20 项通过，补充 29.8%→30% 原生反馈定向 1 项通过。日志 `/tmp/opensketch-task1-green-org.log`、`/tmp/opensketch-task1-green-workspace.log`、`/tmp/opensketch-task1-rounded-green.log`。离屏窗口尺寸预算测试不能代替可见窄窗口验收。

## 检查器

提交 `a4b4306` 重排 260 pt 侧栏：名称、编组/层级、紧凑对齐分布、X/Y、布局、样式、填充、边框及按图层类型出现的文字区域。浅色参数背景为 244/244/246，暗色为中性 0.20 灰；原生 CALayer 按控件自身 effectiveAppearance 解析动态颜色。组宽高保持只读，没有添加未实现的约束、阴影、效果或导出面板。

共享字段定义覆盖 X/Y、宽高、旋转、透明度、线宽、圆角和字号。透明度显示百分数，模型仍使用原有 0...1；所有数值输入拒绝非有限值，沿用既有范围。左侧标签达到 3 pt 水平位移后开始拖动，默认每点 1、Shift 10、Option 0.1（同时按下时 Option 优先）。基于开始值计算，松开提交一次、Escape 取消、回到起点精确恢复原属性，包括原有 720° 旋转、零宽及高精度透明度。

数值输入沿用原生 NSTextField，保留文本选择、Return/Tab 与文本局部撤销。Session 使用独立 token 校验文档、页面、图层和选择；finishInput 协调器先完成检查器，再调用 Canvas 原有回调。切换选择/页面/文档、失焦和移除控件均结束事务，不把迟到事件写到新对象。

任务审查发现失焦后继续使用同一个 NSTextView 时，上一段 token 已清理而下一段未建立。`0ed614f` 在原生文本再次变化时开始新事务，并在绑定新图层前结束旧编辑器。回归测试没有重新 selectText，真实 RED 两项断言失败，修复后通过。单次截图中曾观察到切换图层瞬间的疑似 glyph 残留，后续截图正确；复用控件刷新与新控件的独立 bitmap 对比 3 cases 逐像素一致，没有据此扩大生产绘制修改。

`0ed614f` 完整测试 **UI 173 + Core 79 = 252 项通过**；Release 10.96 秒，无 warning/error。日志 `/tmp/opensketch-zoom-inspector-final-tests.log`、`/tmp/opensketch-zoom-inspector-final-release.log`。该记录对应焦点交接最终审查修复之前的版本。

最终整体审查发现 Canvas 内联文字转入检查器时，Canvas.finishText 无条件抢回 first responder，可能清除尚未建立 token 的拖动起点或结束刚进入的原生输入框。`a6edc9a` 在移除内联编辑器前记录其焦点所有权，仅当它仍持焦点时恢复 Canvas 焦点。同一 NSWindow 中的两项 RED 测试得到 7 个失败，修复后连续输入、两次 drag、向实际 first responder 发送 Escape，以及参数/先前文字各自独立撤销均通过；另验证 Canvas 自己用 Command Return / Escape 结束时仍正确恢复焦点。

最终源码 `a6edc9a`：受影响 **116 项**，完整 **UI 176 + Core 79 = 255 项**通过；Release **10.97 秒**。日志 `/tmp/openSketch-inspector-final-fix-{focused,full-test,release}.log`，无 warning/error。两项任务审查、一次整体审查与相应范围内复核已完成，已发现的问题均关闭，无未解决源码阻塞。最终打包日志 `/tmp/opensketch-zoom-inspector-a6edc9a-package.log`；`codesign --verify --deep --strict`、`plutil -lint`、`git diff --check` 均通过。产物为 `build/openSketch.app`，本地 ad-hoc 签名，未安装系统目录或推送。

## 数据保护

用户当前设计通过原生保存为 `research/local/preserved-before-zoom-inspector-20261106.opensketch`，初始保存 hash 为 `982c1b559f6c964b3953bb0f3f52b73f1e41b03cd18a0bedfde24dd6309c293f`。两页，第二页包含画板及矩形子层。用户数据与 GUI 样例均在 Git 忽略目录中。

独立验收源 `research/local/zoom-inspector-source-20261106.opensketch`：第一页“参数”包含矩形 `(40,70,160,120)`、线宽 2、圆角 8，以及文字“openSketch 参数”；第二页为原容器测试样例的椭圆。

重启前用户已自行关闭原设计，只留下干净的“未命名 4”。没有将用户关闭的文档重新打开。原保留包 hash 再次核对未变。

## 真实窗口验收

在 `a4b4306` Release 中完成：

1. 双列参数布局与亮/暗外观均可读，文字图层还显示内容、字体、字号和对齐；恢复跟随系统。
2. X 标签实际水平拖动 30 pt，矩形 X 从 40 到 70；一次撤销恢复 40 和干净状态，重做恢复 70。
3. 宽度直接输入 220，Return 提交、离开文本框后一次撤销回到 160。
4. 透明度标签向左拖动 30 pt，100% 到 70%，画布同步显示透明度。字号输入 32 并 Tab，文本绘制同步放大。
5. 放大图标使顶部常显比例、滑条 AX 与底栏同时变为 125%；下拉“适合画布”显示 159%，实际尺寸恢复 100%。

原生另存为 `research/local/gui-zoom-inspector-20261106.opensketch`，hash `cd7c6ca71d64269f9d0bf4217b535102334b4449b624ae0c4338350225624065`。对 JSON 做完整相等检查：相对源文件仅矩形 X=70、opacity=0.7、文字 fontSize=32 三处变化，其他内容精确一致。

在 `0ed614f` Release 中重开该包，参数与干净状态正确；输入 X=90 后一次撤销恢复 70。实际拖动 96 pt 滑条到 24%，顶部、AX 和底栏一致；切换空白文档显示 100%，切回显示 24%。这验证显示取整及文档独立性，缩放不使文档变脏。

用户随后继续在验收文档上试用并修改了尺寸、旋转、透明度、圆角、颜色和线宽。最终更新前原生另存到 `research/local/preserved-user-inspector-testing-20261106.opensketch`，保留验收副本不被覆盖。该用户最新文件 hash 为 `e642de8b5d08218f203af5f050c8f513824215deaf068d3a16c7da6abbe686e6`。在最终 `a6edc9a` 应用中重新打开、选择原矩形并适合画布，AX 确认宽 180.45、高 132.73、旋转 -23.3、透明度 99.43%、圆角 43.97、线宽 17.22、白填充/黑描边，文档干净，外观跟随系统。数值在文档中保留原精度，AX 显示到两位小数。最终窗口保留用户的最新设计及原空白标签，而非退回先前空白状态。

实窗边界：Shift/Option 拖动、中途 Escape、精确窗口失焦通知及最小 980 pt 标题栏布局依靠原生宿主行为/预算测试，没有声称全部组合完成可见 GUI 验收。独立浮层持续按住画面未可靠截取；常显百分比和真实滑条拖动已验收。系统颜色面板选色未在本轮逐项重测。目标 macOS 15+，当前工具链主机 macOS 27.2，未在 macOS 15 实机验证。
