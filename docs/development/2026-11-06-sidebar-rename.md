# 页面与图层行内重命名验收

## 交互与实现

基线 `08b9adf` 的页面和图层右键菜单缺少重命名。最初实现于 `2a810b1`，随后根据用户要求移除弹窗，改为原行的原生 `NSTextField`。页面、画板、编组、矩形、椭圆、文字和路径共用目标/事务逻辑；本轮没有新增 Symbol/组件实例模型。

右键点击对象后选择“重命名”，旧名称自动全选。Enter 或点击其他控件提交，Escape 取消；名称仅影响右键目标，不切换页面或修改其他选中对象。锁定/隐藏状态和几何不受影响。空白及非法名称保留原名并显示底部消息。

草稿独立于文档，每次有效改名只产生一条历史；同名/取消保持原有 redo。输入结束协调器在保存、切页/切文档等边界读取原生编辑器最新内容，然后清除 ownership 并提交，避免通知迟到漏值和重复提交。请求 UUID 同时约束原生事件、字段注册和文本 reader，过期字段不会影响新请求。现有 v1 文档格式不变。

## 自动化与构建

2026-11-06，Apple M2 Max / macOS 27.2，Swift 6 工具链：

- `swift test --filter SidebarRenameTests`：15 项测试通过，参数化覆盖 6 种节点、4 种非法名称及 Enter/Escape。
- `swift test`：UI 213、Core 79，共 292 项通过。
- `scripts/build.sh release`：通过，最终 Release 编译 10.00 秒；Info.plist 与 deep/strict ad-hoc 签名检查通过。
- `git diff --check`：通过。独立只读审查最终无 Critical/Important/Minor 遗留。

回归包含：非当前页面、多选时仅改右键目标、嵌套锁定/隐藏、Unicode 保存加载、undo/redo、空白/控制字符/超限、目标删除/移动/替换/并发改名、Canvas/Inspector 输入独立事务、原生 Enter/Escape/失焦只提交一次、通知到达前读取最新编辑值、过期字段不得覆盖新 reader。

后两项均先验证旧实现失败再修正。日志位于本机 `/tmp/opensketch-sidebar-inline-{green,full,package,boundary-red,stale-red}.log`，日志不是仓库产物。

复现：

```sh
swift test --filter SidebarRenameTests
swift test
scripts/build.sh release
plutil -lint build/openSketch.app/Contents/Info.plist
codesign --verify --deep --strict build/openSketch.app
```

## 实窗验证与边界

使用独立样例 `research/local/sidebar-rename-source-20261106.opensketch`：

1. 暗色：未选中的第二页面通过右键进入原行输入框，旧名全选，无 sheet；输入“设置页面 ✨”并 Enter，第一页面保持选中。
2. 暗色：嵌套“组件组”在原名称位置编辑，输入临时名称后 Escape，恢复“组件组”。
3. 亮色：编组输入“导航组件”，点击“独立图层”后提交并正确选择该图层；一次 Cmd-Z 恢复编组名，之前页面改名保留。原行输入框亮暗外观均已观察。

菜单 AX 的第一次快照有时只显示选中项，后续快照才显示输入框；未据此误判菜单未执行。中文通过原生粘贴验证，未据此宣称真实输入法候选窗验收。

后续接口返回 `cgWindowNotFound`，进程仍存在且未发现 openSketch 崩溃报告；未强制终止进程。因此本轮未完成普通图层改名与保存重开的额外实窗步骤，也未重新启动最终包含 reader token 加固的包。上述逻辑由自动化覆盖，最终可运行包位于 `build/openSketch.app`。没有安装 `/Applications` 或推送远端。

## 用户编辑保留

验收前原有设计已保存到 `research/local/preserved-user-inspector-testing-20261106.opensketch`，`document.json` SHA-256 为 `fad201226bfb96635591a3b8cab98f44148802bf2b602660924b00d7e9de8cf8`。

用户在新版本中新建的两页面/三画板设计另存到 `research/local/preserved-user-inline-testing-20261106.opensketch`，SHA-256 为 `1bd949324dbff24462ddeb966e0d15afd530d85c16ceeaf24c0a309ac44e77a5`。该文档保持打开，测试使用另一个标签。用户随后切换为亮色，未还原为旧偏好；测试样例的临时改名尚未另存，未覆盖源文件。
