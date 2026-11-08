# OpenSketch 名称大小写统一

日期：2026-11-08。基线提交 `679295c`。用户要求项目和应用名称统一为 `OpenSketch`。

## 范围

- 本地项目目录改为 `/Users/tsmax/Develop/MacOS/AwesomeProjects/OpenSketch`。
- SwiftPM 包名和可执行产品改为 `OpenSketch`，入口 target 与目录改为 `OpenSketchApp`。
- 应用包为 `build/OpenSketch.app`，可执行文件为 `Contents/MacOS/OpenSketch`，`CFBundleName`、`CFBundleDisplayName`、`CFBundleExecutable` 均使用 `OpenSketch`。
- SwiftPM 资源 bundle 改为 `OpenSketch_OpenSketchUI.bundle`；显式资源查找和打包脚本同步更新。
- 应用菜单、退出菜单、主窗口标题、文档类型显示名称、新建示例问候语及双语词条统一大小写；README、当前源码结构、图标元数据与项目版权署名同步更新。

macOS 当前文件系统不区分路径大小写。项目目录和入口目录通过临时名称中转，核对目录项的实际拼写；旧构建包移至 `build/backups` 后重新生成，避免旧目录、可执行文件及资源 bundle 的大小写被沿用。SwiftPM 清理旧构建缓存后重新测试和构建。

## 兼容性

保持应用 Bundle ID `org.opensketch.app`、文档格式/UTI `org.opensketch.document`、文件扩展名 `.opensketch`、剪贴板类型、偏好键和既有内部通知名称。已有文档名称及正文不改写；Core 文档模型、外观偏好和语言偏好实现与基线逐字节一致。

历史验收记录、原始图标生成提示词及用于测试用户文本的旧名称保留原样，它们记录当时状态。当前操作以 README 和构建脚本中的 `OpenSketch` 名称为准。

## 验证

| 检查 | 结果 |
| --- | --- |
| 清理缓存后的 `swift test` | UI 243 + Core 88，共 331 项通过，无编译 warning/error |
| `scripts/build.sh release` | 成功，完整 Release 构建 21.03 秒 |
| 实际目录项与包元数据 | 项目目录、入口目录、app、可执行文件和资源 bundle 的大小写均准确 |
| 包内本地化资源 | en/zh-Hans 各 215 项；产品显示文案不含旧大小写 |
| `plutil -lint`、严格签名、Bash/zsh 语法检查 | 通过 |

系统安装路径采用 `/Applications/OpenSketch.app`。安装前保留旧包，安装后比较构建包和安装包的逐文件清单并检查真实窗口。安装证据写入 Git 忽略的 `build/name-capitalization-install.json`。测试和 Release 日志分别为 `/tmp/OpenSketch-capitalization-tests.log`、`/tmp/OpenSketch-capitalization-release.log`。
