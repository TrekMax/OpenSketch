# openSketch 应用图标

主题是一只朝右上方飞行的金色纸飞机。配色和立体切面参考 Sketch 的应用图标，主体采用原创折纸轮廓；浅色圆角底板外保留透明通道。

| 文件 | 用途 |
| --- | --- |
| [AppIcon.svg](AppIcon.svg) | 1024 × 1024 可编辑矢量母版，无嵌入位图、字体或外链 |
| [AppIcon.png](AppIcon.png) | 从 SVG 渲染的 1024 × 1024 RGBA 预览 |
| [AppIcon.icns](AppIcon.icns) | macOS 应用图标，含 16、32、64、128、256、512、1024 像素表示 |
| [Concept.png](Concept.png) | imagegen 生成的原始视觉稿，作为重绘参考；应用使用 SVG 导出的 ICNS |

SVG 中 `app-tile` 是底板组，`paper-plane` 是飞机组；移除前者可得到透明背景的独立纸飞机。`upper-wing`、`under-fold`、`center-fold`、`lower-wing` 控制四个折纸面的渐变，阴影使用标准 SVG 滤镜。可以在支持 SVG 的矢量编辑器中继续调整。

## 导出与构建

普通 `scripts/build.sh release` 直接复制已生成的 ICNS，无需 Node.js 或额外工具。`Resources/Info.plist` 的 `CFBundleIconFile` 已指向 `AppIcon`。

修改 SVG 后，在仓库根目录执行：

```sh
npm install --prefix build/icon-tools --ignore-scripts --no-audit --no-fund --save-exact @resvg/resvg-js@2.6.2
node scripts/generate-icons.mjs
scripts/build.sh release
```

可选导出工具 [resvg-js](https://github.com/thx/resvg-js) 安装在 Git 忽略的 `build/icon-tools`，不进入应用包。使用它渲染渐变和柔和阴影，再由系统 `iconutil` 合成 ICNS；系统 `sips` 的 SVG 渲染会忽略这里的模糊滤镜，不用于最终导出。临时各尺寸 PNG 位于 `build/AppIcon.iconset`。

2026-11-08 已检查 16/32/64/128 像素在亮暗背景中的轮廓，验证 SVG 的本地引用、PNG 透明通道、ICNS 尺寸和应用包内图标一致性；Release 构建、Info.plist 与严格签名检查通过。未安装到 `/Applications`，未刷新当前运行应用的 Dock 缓存。

## 视觉稿来源

使用内置 imagegen 生成视觉稿，然后手工以 SVG 路径与渐变重绘。仅以本机 Sketch 2026.3.1 的图标作为风格参考，未将 Sketch 图标复制进仓库或应用。生成提示词如下：

> Use case: logo-brand. Create one polished macOS application icon for openSketch. Reference image is the installed Sketch app icon: use it ONLY for its warm amber/gold/orange folded-facet visual language, soft gloss, precision and restrained depth. Replace the diamond entirely with an ORIGINAL single origami paper airplane flying diagonally toward the UPPER RIGHT, tip aimed roughly at 1:30 o'clock. No diamond. The paper airplane must read clearly at 32px: a large broad pale-gold upper wing, a saturated amber lower wing, a narrow darker burnt-orange central folded keel and elegant crisp paper fold edges. Minimal 4-5 large triangular planes, each with a smooth subtle gradient; no extra tiny decorative facets. The silhouette must be a recognisable folded paper airplane, viewed from slightly above, generous wings, pointed upper-right nose, asymmetric rear wing corners at lower-left. A small soft warm contact shadow. Put the golden plane prominently centered on a luminous ivory / off-white macOS rounded-square tile, inset 8% from the 1024x1024 canvas; silhouette of the tile and its restrained exterior shadow against genuine alpha transparency outside. The plane occupies about 72% of the tile and has generous margin. Premium, sculpted but clean vector-friendly artwork, not photorealistic crumpled paper, no chrome, no glass, no text, no letters, no wordmark, no border ornament, no flight trail, no surrounding objects. Single icon, not presentation sheet. Keep boundaries geometrically simple so the design can be faithfully redrawn as editable SVG paths and gradients.
