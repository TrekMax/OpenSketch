# Sketch 参考亮色配色

日期：2026-11-06。代码基线：`2634fe1`。本次按用户要求调整亮色编辑器配色，暗色继续采用 Compositor 的中性深灰方案。

## 参考与实现

只读观察本机 `/Applications/Sketch.app` 的实际亮色窗口，以白色面板、浅灰工作区/输入框、蓝紫色选中态为参考。下表为本项目选择的近似 sRGB 值，并非提取 Sketch 内部设计变量或逐像素复刻。

| 用途 | 亮色值 |
| --- | --- |
| 标题栏、工具区、侧栏、检查器 | `#FFFFFF` |
| 画布外围 | `#F5F5F5` |
| 检查器输入框 | `#F4F4F6` |
| 强调色、选中图层、画布选择轮廓 | `#5E5BFF` |
| 当前工具及文档标签背景 | `#EFEEFF` |
| 面板分隔线 | `#E8E8EB` |
| 网格点 | `#DCDCE1` |

选中图层使用白色文字和图标；普通文字继续采用系统主/次标签色。`EditorPalette` 集中维护编辑器颜色，`EditorFieldStyle` 为原生 TextField 增加亮色背景和内边距，保留绑定与辅助功能标识。

暗色保留原面板 `0.14`、画布外围 `0.105` 灰度，工具/标签的白色 12% 选中背景、系统紫色画布轮廓和原生输入框样式。外观仍支持亮色、暗色和跟随系统。本次没有修改文档模型、图形默认颜色、共享渲染器或导出路径。

## 验证

环境：Apple M2 Max、macOS 27.2、Swift 6.4 / Xcode 27.1，部署目标 macOS 15。

```sh
swift test
scripts/build.sh release
codesign --verify --deep --strict build/openSketch.app
plutil -lint build/openSketch.app/Contents/Info.plist
git diff --check
```

- 92 项现有测试通过：UI 68、核心 24；构建日志无 warning/error。
- Release 构建通过（8.59 秒），严格签名检查通过，Info.plist 检查为 OK。
- 在本次 Release 的真实窗口检查白色面板、浅灰画布、蓝紫色图层选中态、标签/工具浅紫选中背景及检查器输入框。
- 创建测试矩形后切换亮色 → 暗色 → 亮色；暗色保持原深灰层次及输入框样式。一次撤销直接移除矩形，外观切换未增加文档撤销历史。
- 原生检查器辅助功能标识仍可读取。亮色输入框保留原生文本编辑；本次未扩展输入法或 macOS 15 实机验收。

更新产物为仓库内 `build/openSketch.app`，未安装到 `/Applications`，未推送远程仓库。

## 当前文档保留

更换运行中的应用前，通过原生保存面板将用户原有未保存设计另存到忽略目录：

`research/local/preserved-before-sketch-light-20261106.opensketch`

该文档包含 2 个页面和 1 个根画板；`document.json` 的 SHA-256 为 `b1a77376bf6de52006348214db7bbcd293ed9922bfa30d5412e04d0ff905e0b3`。验收后重新打开该文档，恢复显示页面 2 和原画板，关闭测试空白标签，保留亮色模式。未修改文档内容，文件校验值保持一致。
