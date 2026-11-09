# 来源与第三方材料

## 原创材料与许可

原生初始原型的源码、测试、脚本、内置示例和文档适用仓库 [MIT License](LICENSE)，版权归 `2026 OpenSketch contributors`。当前源码、应用资源和 Swift Package 未引入第三方应用代码、二进制、图标、字体文件或外部包依赖；基准程序只编译本仓库核心与原创测量代码。

## Apple 系统依赖

原型使用 macOS 自带的 Foundation、CoreGraphics、AppKit、SwiftUI、Observation、UniformTypeIdentifiers 与 Darwin API；测试使用工具链提供的 Swift Testing。字体按系统字体名称调用，缺失字体回退，不随项目分发字体文件。工具栏使用系统 SF Symbols API，没有复制符号资源。

构建/验证使用系统 Swift、Xcode SDK、Bash、`codesign`、`plutil`；基准另外读取 `sw_vers`、`uname`、`sysctl`、`xcodebuild`。Sketch 元数据检查通过系统 `/usr/bin/unzip` 有界读取 ZIP 的 `meta.json`，不解压到磁盘。Apple 系统框架、SDK 和工具由系统/开发环境提供，遵循各自条款，仓库 MIT 许可不覆盖它们。

## 当前来源审核结论

早期开发曾将 Compositor 作为架构和交互研究材料，并在设置与语言功能中保留过改写代码及其许可证。2026-11-09 已完成相关实现的独立重写：语言选择、资源目录解析和设置界面均使用 OpenSketch 自有实现，行为回归测试通过；当前源码不再包含该第三方实现或版权声明，构建脚本也不再打包其许可证。

历史开发记录仍可能描述当时的研究过程，不代表当前源码包含第三方代码。后续若重新引入任何外部代码、资源或协议，必须在合并前重新登记来源、许可证和分发文件。

## Sketch（兼容性观察）

历史对标对象为本机 Sketch 2026.3.1（234013），依据其公开文档、正常应用交互和原创本地测试文档观察格式。原始测试文档放在 Git 忽略的 `research/local/`，不分发用户项目。观察到的 `meta.json` 字段为 `version=196`、`appVersion=2026.3.1`、`build=234013`、`compatibilityVersion=99`，这四项含义独立。

Sketch 应用本体、框架、图标和品牌素材没有复制进项目；公开 JSON Schema 未作为依赖引入。当前功能仅检查元数据，不声明可编辑导入或无损往返。Sketch 名称及相关商标归其权利人所有；OpenSketch 与 Sketch 官方产品没有隶属关系。

## OpenSketch 纸飞机图标

`Resources/AppIcon` 的金色纸飞机以 Sketch 的琥珀金切面风格为视觉参考，由 imagegen 生成原创视觉稿，再使用 SVG 路径和渐变重绘。没有复制 Sketch 的钻石形状或原图像资产；源文件、生成提示词和导出方法见[图标说明](Resources/AppIcon/README.md)。

维护者可选用 `@resvg/resvg-js` 2.6.2（[MPL-2.0](https://github.com/thx/resvg-js/blob/main/LICENSE)）渲染 SVG，并使用 Apple 系统 `iconutil` 生成 ICNS。此工具只安装在忽略的 `build/icon-tools`，其代码和二进制不随应用分发，不是 Swift Package 或应用运行时依赖。
