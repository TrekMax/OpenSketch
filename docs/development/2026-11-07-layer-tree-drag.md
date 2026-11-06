# 左侧图层树拖拽

后续用户报告实际无法拖拽，SwiftUI 图层区域与 provider 桥接现已由原生树形列表替代，见[原生列表修复记录](2026-11-07-native-layer-tree.md)。以下保留最初实现及验收边界。

基线 `02cb652`。本轮为图层树增加顺序与父级调整，不修改既有 Canvas 拖入画板规则或 v1 文件格式。

## 操作与语义

- 拖动行上/下边缘，在该对象上方/下方插入同级图层。列表自上而下对应画布自前而后的绘制顺序。
- 画板和编组的中间区域接收子层，放入后展开目标。行上下各 25% 用于同级插入，中间 50% 用于归属；普通节点以上下半行区分顺序。
- 列表底部“移到页面根层级”将对象移出容器，并放在根层级列表末尾。
- 拖已选对象会带上其他已选对象；拖未选对象只选择并移动该对象。父子同时选中时仅搬运最高祖先，完整保留子树与多个根的原相对绘制顺序。
- 跨父级转换坐标，保留世界位置/旋转/尺寸和 UUID；同父重排不重新计算几何。新父级的裁剪、透明度继承会正常生效；不自动重算编组边界。
- 悬停只显示插入线/容器边框，不改变文档。松手后一次历史事务，失败、取消、无变化不增加撤销记录。展开容器之后的插入线显示在最后可见后代之后，并使用该容器的缩进。
- 仅支持当前文档当前页面；拒绝循环嵌套、锁定/隐藏源或目的父级、超深/无效坐标与过期请求。画板允许通过树操作重排或嵌套。原位改名期间不开始图层拖动。

## 实现及审查

`LayerTreeEditing` 将源校验与目标坐标转换分开，支持 above/below/inside/pageEnd，生成完整候选值后经 `DocumentCodec` 验证，再由 EditorSession 提交历史。源校验不依赖能否移到根坐标系，避免极端父坐标阻止合法的同父重排。

会话请求包含 UUID、页面 ID、选择集合与文档值快照。NSItemProvider 在本进程提供固定基础类型及该请求独有的类型，数据仅包含 UUID；不使用 suggestedName 作为身份依据。悬停通过 advertised type 判断会话与目标；`itemProviders` 只在 `performDrop` 使用，异步交付后再次核对数据、请求、页面与文档。该阶段限制依据 [Apple DropInfo 文档](https://developer.apple.com/documentation/swiftui/dropinfo/itemproviders(for:)-b6fo)。

独立只读审查提出的源校验、悬停 API 时机与展开容器插入线三项问题均已修复；最终复审无 Critical/Important/Minor 遗留。

## 自动化证据

2026-11-07，当前 macOS 主机：

| 检查 | 结果 |
| --- | --- |
| 图层拖动/重命名/选择相关测试 | UI 32 + Core 9 = 41 项通过 |
| 完整 `swift test` | UI 230 + Core 88 = 318 项通过 |
| `swift build -c release` | 通过，11.76 秒 |
| Info.plist / deep strict ad-hoc 签名 | 通过 |
| `git diff --check` | 通过 |

Core 新增 9 项测试，覆盖反向索引、多选/父子归一、旋转父级与后代世界点、精确同父重排、画板嵌套、跨父插入、循环/跨页/锁定/隐藏、深度和坐标限制、原始负尺寸。UI 新增 11 项，覆盖多选/未选入口、一次撤销、no-op 保留 redo、过期 token/文档、切页/输入取消、锁定、真实 provider 数据传递/重复提交/坏数据、源坐标边界及落点/插入线。

日志位于本机 `/tmp/opensketch-layer-drag-{core-red,ui-red,size-red,start-red,provider-red,marker-red,green,full,release}.log`。源坐标限制、负尺寸和缺失 suggestedName 均先复现失败再修复。

```sh
swift test --filter 'LayerTreeDragTests|LayerTreeEditingTests|SidebarSelectionTests|SidebarRenameTests'
swift test
swift build -c release
plutil -lint build/openSketch.app/Contents/Info.plist
codesign --verify --deep --strict build/openSketch.app
```

## 包与实窗边界

新包已在独立目录组装、验证后替换 `build/openSketch.app`；旧包保留于 `build/backups/openSketch-before-layer-drag-20261107-002934.app`，避免覆盖正在运行的可执行文件 inode。可执行文件 SHA-256：`c32fe7a18003f6b80a65ff5d0505c6f2febda451070a7ea187e2dc44b4ea982c`。没有修改用户文档、强制退出进程、安装系统目录或推送。

本轮多次重新获取 openSketch 窗口均返回 `cgWindowNotFound`，访达窗口也不可读取，因此尚未重启新包或进行真实鼠标拖拽验收。自动化 provider 测试不替代 SwiftUI/系统 pasteboard 桥接与手势验收。

待窗口可访问后：使用独立样例检查单层/多层排序、拖入展开与折叠容器、跨容器及根层级、旋转对象位置、拖动取消/无效落点、一次撤销与保存重开；同时复查整行点击、Shift、右键、展开/锁定/显示按钮及原位文本编辑，长列表边缘滚动亦需实窗确认。
