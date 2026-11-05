# 本机 Sketch 实测记录

时间：2026-11-05。应用：`/Applications/Sketch.app`。

## 版本与环境

通过 `Contents/Info.plist` 读取：

- `CFBundleIdentifier`: `com.bohemiancoding.sketch3`
- `CFBundleShortVersionString`: `2026.3.1`
- `CFBundleVersion`: `234013`
- `LSMinimumSystemVersion`: `15.0.0`

与 [官方 2026.3.1 发行说明](https://www.sketch.com/changelog/2026-3-1/) 对应。声明的可打开文档类型含 Sketch、PDF、图像与 Figma；文件类型注册不等于本次已验证这些导入能力。

## GUI 操作与观察

最初显示登录界面；用户随后使应用可以正常打开，本次已继续进入实际编辑器，登录界面不再是评估阻塞。

在本次新建的空白文档中执行：

1. 进入“未命名”编辑窗口。左侧有文档、页面和图层区；中央画布与标尺；右侧为上下文属性面板。截图和 AX 树均确认。
2. 按 `F` 进入画框工具，右侧出现 Phone/Tablet/Desktop 画框模板。
3. 选择一个 402 × 874 模板。新增 Frame 在图层树中可见；属性面板展示位置、尺寸、裁剪内容、角、填充、边框、阴影、内阴影、效果和导出。
4. 按 `⌘L` 转换为 Stack。图层图标变为纵向 Stack，名称为“层叠”；右侧新增方向、对齐、间距、padding 等布局控件，宽高显示 Fixed 状态。
5. 通过系统保存对话框将自建文档保存在本地 `/tmp/sketch-evaluation-20261105.sketch`，读取并检查其 ZIP/JSON 结构。

后台部分合成输入没有产生预期结果，切到前台后完成画框创建与保存。结论依据状态变化和文件内容，不仅依据自动化接口返回成功。这里只验证了空 Frame 转 Stack，未声称已经验证含子项的自动重排。

未打开或修改用户原有项目，未上传到 Sketch Workspace。测试文件副本保留在本仓库 `research/local/`（Git 忽略），版本化证据仅保留结构字段和哈希。

## 实际文件结构

样本大小 9,838 字节，SHA-256：

`19f62988abd37dc93ab13ee9e92334df2c67661388a42a9d4e58e2aec62ee25c`

ZIP 中包含 `document.json`、`meta.json`、`user.json`、一个 `pages/<UUID>.json` 和 `previews/preview.png`。本样本未放置图片，因此没有图片资源目录。

`meta.json` 中 `version = 196`、`appVersion = 2026.3.1`、`build = 234013`、`compatibilityVersion = 99`。`compatibilityVersion` 是观察到的字段值，不能据此宣称本项目支持所有对应旧版本。

该 Stack 的部分字段如下，完整的筛选结果见 [证据 JSON](evidence/baseline.json)：

```json
{
  "_class": "group",
  "groupBehavior": 1,
  "clippingBehavior": 1,
  "horizontalSizing": 0,
  "verticalSizing": 0,
  "groupLayout": {
    "_class": "MSImmutableFlexGroupLayout",
    "flexDirection": 1,
    "wrappingEnabled": false,
    "version": 1
  }
}
```

由此可确定：当前样本的 Frame/Stack 不能只通过旧式 `_class = artboard` 识别。各枚举值、旧文档迁移和复杂布局规则还要用公开 schema 与更多对照样本验证，不能从一个样本推断整个格式。

`document.json` 还出现 `foreignSymbols`、`foreignTextStyles`、`foreignLayerStyles`、`foreignSwatches`、`foreignVariantSets` 和 `perDocumentLibraries` 等字段；字段存在不代表样本已覆盖这些功能。

## 可重复检查

在仓库根目录运行下列只读命令；本地样本不进入远程源码库：

```sh
plutil -extract CFBundleShortVersionString raw /Applications/Sketch.app/Contents/Info.plist
plutil -extract CFBundleVersion raw /Applications/Sketch.app/Contents/Info.plist
unzip -l research/local/sketch-evaluation-20261105.sketch
unzip -p research/local/sketch-evaluation-20261105.sketch meta.json
shasum -a 256 research/local/sketch-evaluation-20261105.sketch
```

`sketchtool --help` 和 `sketchtool help run-script` 可正常返回，其 CLI 包含 metadata、export、diff、run-script 等入口。本次未通过脚本生成测试文档，也未调用 migrate/detach 等改写命令。

尚未验证：复杂组件/覆盖、路径节点编辑、实际字体排版、原型、批量导出、Figma 导入、大文档性能及完整文件往返。这些应进入 M0 样本集和后续替代验收。
