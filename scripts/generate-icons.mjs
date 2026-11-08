#!/usr/bin/env node
// Optional asset-authoring step. Normal app builds use the checked-in ICNS.
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(join(root, 'build/icon-tools/package.json'));
let Resvg;
try {
  ({ Resvg } = require('@resvg/resvg-js'));
} catch {
  console.error('Install the optional SVG renderer from the repository root:');
  console.error('npm install --prefix build/icon-tools --ignore-scripts --no-audit --no-fund --save-exact @resvg/resvg-js@2.6.2');
  process.exit(1);
}

const assets = join(root, 'Resources/AppIcon');
const iconset = join(root, 'build/AppIcon.iconset');
await mkdir(iconset, { recursive: true });
const svg = await readFile(join(assets, 'AppIcon.svg'));
const render = size => new Resvg(svg, {
  fitTo: { mode: 'width', value: size },
  font: { loadSystemFonts: false },
}).render().asPng();

await writeFile(join(assets, 'AppIcon.png'), render(1024));
for (const size of [16, 32, 128, 256, 512]) {
  await writeFile(join(iconset, `icon_${size}x${size}.png`), render(size));
  await writeFile(join(iconset, `icon_${size}x${size}@2x.png`), render(size * 2));
}
execFileSync('/usr/bin/iconutil', ['--convert', 'icns', '--output', join(assets, 'AppIcon.icns'), iconset], { stdio: 'inherit' });
console.log('Generated Resources/AppIcon/AppIcon.png (1024×1024) and AppIcon.icns (16–1024 px).');
