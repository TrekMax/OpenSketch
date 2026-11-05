# 来源与第三方材料

## 原创材料与许可

原生初始原型的 `Sources/`、`Tests/`、`scripts/`、Info.plist、内置示例设计及新增文档为本项目原创，适用仓库 [MIT License](LICENSE)，版权归 `2026 openSketch contributors`。没有复制第三方应用源代码、二进制、图标、字体文件或 Sketch 内部框架；Swift Package 未声明外部包依赖。基准程序同样只编译本仓库核心与原创测量代码。

## Apple 系统依赖

原型使用 macOS 自带的 Foundation、CoreGraphics、AppKit、SwiftUI、Observation、UniformTypeIdentifiers 与 Darwin API；测试使用工具链提供的 Swift Testing。字体按系统字体名称调用，缺失字体回退，不随项目分发字体文件。工具栏使用系统 SF Symbols API，没有复制符号资源。

构建/验证使用系统 Swift、Xcode SDK、Bash、`codesign`、`plutil`；基准另外读取 `sw_vers`、`uname`、`sysctl`、`xcodebuild`。Sketch 元数据检查通过系统 `/usr/bin/unzip` 有界读取 ZIP 的 `meta.json`，不解压到磁盘。Apple 系统框架、SDK 和工具由系统/开发环境提供，遵循各自条款，仓库 MIT 许可不覆盖它们。

## Compositor（仅参考）

- 上游：<https://github.com/robbietilton/Compositor>
- 本机参考分支：`feat/module-manager`。
- 本机参考提交：`f6cd2f05525e7ca61d680cd221a690b796ef21d2`。
- 本机仓库：`../Compositor`。
- 源码许可证：MIT，版权行 `Copyright (c) 2026 Wonder Assembly LLC`。

本次仅审阅其原生工程经验，没有移植源码或资源。若后续复制或改写相关代码，应保留原版权与完整许可，并登记源文件、来源提交、目的路径及修改摘要；外部资源应分别核实许可。

## Sketch（兼容性观察）

历史对标对象为本机 Sketch 2026.3.1（234013），依据其公开文档、正常应用交互和原创本地测试文档观察格式。原始测试文档放在 Git 忽略的 `research/local/`，不分发用户项目。观察到的 `meta.json` 字段为 `version=196`、`appVersion=2026.3.1`、`build=234013`、`compatibilityVersion=99`，这四项含义独立。

Sketch 应用本体、框架、图标和品牌素材没有复制进项目；公开 JSON Schema 未作为依赖引入。当前功能仅检查元数据，不声明可编辑导入或无损往返。Sketch 名称及相关商标归其权利人所有；openSketch 与 Sketch 官方产品没有隶属关系。
