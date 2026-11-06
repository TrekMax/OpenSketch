# 原生图层树与拖动入口修复

基线 `176df2e`。用户反馈“测试 无法拖拽”，随后要求参考 Sketch 并采用相同风格的树形列表。

## 观察与实现

在旧版实窗，从名称及行内空白处拖动均未改变层级。临时日志确认外层 SwiftUI onDrag 没有触发；移除内部选择 Button 后可触发源回调，但尚未完成目标回调的实窗验证。诊断日志及 `.all`/UTI 声明实验已移除，不把未证实的桥接假设作为根因。

本机 `/Applications/Sketch.app` 的辅助功能树显示 LayerList 的 outline/row/文本字段结构；另在独立文档绘制两个矩形观察交互。Compositor 的 `UI/Layers/NativeLayerList.swift` 提供 AppKit 列表、原生粘贴板与 source identity 检查的参考。Sketch 的源码不可见，本项目依据可观察交互和公开 AppKit 接口实现。

图层区域现在使用 `NSOutlineView`；页面列表继续使用原有实现。稳定 UUID 对象映射反向绘制顺序，父节点在子节点之前；按文档存活节点保留折叠集合。选择或重命名草稿变化不 reload，避免重建拖动对象和原生文本编辑器。

- 整行选择、高亮、Shift 连续范围多选、Command 切换成员、方向键导航及折叠/展开由原生树处理。
- 名称双击、Return 或右键重命名均复用 `NativeSidebarRenameField`；Enter 提交，Escape 取消，切换选择提交一次。显示/锁定仍是独立按钮，右键保留复制、删除、编组、层级、对齐与分布。
- 使用现代 `pasteboardWriterForItem` 提供各行 UUID；`willBeginAt` 在 AppKit 收集所有行之后捕获一次会话请求。固定私有 NSPasteboard 类型不含文档内容。
- 校验同一个源 outline、当前协调器/会话请求及完整行 UUID 集合，随后由原有 Core 校验页面、文档快照、循环、锁定、隐藏、深度和几何限制。拖动结束清理请求。
- 将原生 `childIndex` 映射为 above/below/inside/pageEnd，跳过正在移动的锚点，支持非连续多选。画板/编组接受内部放置，底部标签及根层级空白用于移出容器；跨父级保留世界几何，一次撤销。
- 原生单元格接入 `textField/imageView` outlets，供 AppKit 生成多项目拖动预览；保留明确的名称/编辑器、隐藏与锁定辅助功能子元素。

原生树使用系统拖动跟踪、插入标记及滚动机制。相关 API 契约参考 [NSOutlineViewDataSource](https://developer.apple.com/documentation/appkit/nsoutlineviewdatasource)、[NSTableCellView](https://developer.apple.com/documentation/appkit/nstablecellview) 及当前 Xcode SDK 头文件。

## 验证

`swift test`：UI 235 + Core 88 = **323 项通过**，无编译警告。旧 SwiftUI provider/手工行展开测试替换为原生树测试，保留 Core 图层移动与历史事务测试。

新增原生测试覆盖：实际 NSOutlineView 显示顺序/层级、原生插入索引、多选粘贴板交接与源身份、过期/取消/锁定、非连续选择落点、Delete/Forward Delete、选择同步与对象身份、跨页面折叠、真实 NSTextView 草稿/失焦提交、错误行数据、单元格拖动预览与独立辅助功能控件。非连续落点、删除键、预览 outlet 回归均记录先失败后通过。

只读审查发现的多选锚点、删除键、折叠状态与拖动预览四项问题已修复。

本机日志：`/tmp/opensketch-native-tree-{red,review-red,review-green,modern,inline,preview-red,final-tests,release}.log`。

```sh
swift test
swift build -c release --product openSketch
git diff --check
plutil -lint build/openSketch.app/Contents/Info.plist
codesign --verify --deep --strict build/openSketch.app
```

## 实窗与用户数据边界

已启动原生树版本，实窗辅助功能树确认 `outline layer.tree`、原生行、选择与展开三角；页面 5 的两块画板及子层正确显示。自动化鼠标拖动没有给出稳定的层级变更证据，同一工具在 Sketch 参考窗口中也未完成排序，不能据此宣布原生拖放验收通过。后续窗口访问间歇返回 `cgWindowNotFound/noWindowsAvailable`；已请求用户反馈手动拖动结果，最终鼠标验收尚待确认。

用户原文档保存为 `research/local/preserved-user-layer-drag-testing-20261107.opensketch`；后续用户在原生版本新建的三页文档另存为 `research/local/preserved-user-native-tree-testing-20261107.opensketch`。自动化操作使用 `gui-layer-drag-fix-20261107.opensketch` 独立副本。Sketch 参考样例保存为 `research/local/sketch-layer-drag-reference-20261107.sketch`，未改动用户原 Sketch 文件。

待实际确认：从名称/行空白开始拖动，单层与 Shift 多层重排，拖入展开/折叠容器，根层级移出，悬停展开及长列表自动滚动，Escape/无效落点取消，撤销/重做和保存重开。原位编辑、侧按钮与右键最终交互仍需一并实窗验收。

## Release 交付

Release 构建通过（11.83 秒），Info.plist 与 deep/strict ad-hoc 签名检查通过。最终包：`build/openSketch.app`，SHA-256：`40d033b6efbd63a5495477f1f4296c7ed42d0a627b11a35123f53588a166b4e3`。旧包保留在 `build/backups/openSketch-before-native-tree-final-20261107-012629.app`，在独立目录组装后原子替换，没有覆盖运行中的可执行文件 inode。

最终再次访问窗口仍返回 `cgWindowNotFound`，因此无法正常退出旧进程并加载最终 Release；需退出后重新打开上述包。没有强制结束进程、安装 `/Applications` 或推送远端。原用户文档 JSON SHA-256 保持 `016d5a147a73d5102182c3f6c7ffce290e840bc338c4a8815b3bdd068d488357`；新建三页测试文档为 `24859d9cbe7393584b619907036c62d717f5cbe736cd0393b8199bc9ee459bd7`。
