# openSketch

面向 macOS 的开源矢量 UI 设计软件，目标是逐步替代本机 Sketch 的日常设计工作流。参照 Compositor 的原生应用工程经验，建立独立的矢量文档和编辑核心。

**当前阶段：可行性评估。尚无可运行的应用、Xcode 工程或已实现的设计功能。**

- 已确认方向：macOS 原生优先，后续再考虑跨平台。
- 对标基线：Sketch 2026.3.1，build 234013。
- 参考源码：Compositor `f6cd2f05525e7ca61d680cd221a690b796ef21d2`。
- 建议路线：Swift + AppKit/SwiftUI 外壳，独立矢量对象模型，Core Graphics 原型，按测量结果优化渲染。
- 本地文件和离线编辑优先；Sketch 文件迁移是重要能力，兼容范围需要逐项验收。

## 评估材料

- [可行性、架构建议与阶段投入](docs/assessment/2026-11-05-feasibility.md)
- [Compositor 源码复用审计](docs/assessment/compositor-audit.md)
- [Sketch 替代能力与验收矩阵](docs/assessment/replacement-matrix.md)
- [本机 Sketch 实测记录](docs/assessment/sketch-observations.md)
- [机器可读的评估基线](docs/assessment/evidence/baseline.json)

这些材料是评估建议，尚未成为批准实施的详细设计。下一步建议先验证矢量模型、文字排版和文件兼容三个高风险点，再展开完整应用开发。

## 开源与来源

本仓库当前新增材料采用 [MIT License](LICENSE)。尚未复制 Compositor 源码或引入第三方运行依赖。后续移植代码时保留原版权和许可，并记录来源提交及修改内容，见 [来源说明](THIRD_PARTY_NOTICES.md)。

openSketch 是本项目名称，与 Sketch 官方产品没有隶属关系。本仓库目前只在本地建立，未配置远程或发布。
