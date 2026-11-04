#!/usr/bin/env node
/**
 * 彩陶工坊 · 从 ArkTS 生成 Web 侧的画法模块
 *
 * 干什么：把 ets/common/PotteryArt.ets 和 ets/common/Theme.ets 里的彩陶画法
 * （轮廓、六种纹样、纹样带、题字、纸底、展示座、色板）机械剥掉类型注解，
 * 生成 entry/src/main/resources/rawfile/pottery/art.js，供 ArkWeb 里的真 3D 主路径
 * （rawfile/pottery/pottery.js）把釉色和纹样贴到 three.js 网格上。
 *
 * 为什么要生成而不是手写一份 JS：纹样画法在仓库里必须只有一份真值。
 * 二维版（PotteryCanvas）、降级转台（PotteryTurntable）、真 3D（pottery.js）三条链路
 * 要的正是「同一张纹样」——手写第二份，改一种纹样就会只在一边生效，
 * 而这种差异只有并排比两台设备才看得出来。geometry.js 镜像 PotteryCanvas 是同一个道理，
 * 只是这次连镜像都省了，直接从 .ets 生成。
 *
 * 用法：
 *   node tools/emit_pottery_art.mjs          # 生成/覆盖 rawfile/pottery/art.js
 *   node tools/emit_pottery_art.mjs --check  # 只重新生成到内存，和 rawfile 里那份比对
 *
 * 守卫：只许删 import / 类型别名 / 类型注解；两边剥掉类型后的数字字面量必须逐个相等，
 * 少一个数字就说明剥类型吃掉了真正的参数，直接失败退出。
 *
 * 纯本地开发工具，不进 App 代码。产物 art.js 才进包。
 */
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const ART_ETS = join(ROOT, 'entry', 'src', 'main', 'ets', 'common', 'PotteryArt.ets');
const THEME_ETS = join(ROOT, 'entry', 'src', 'main', 'ets', 'common', 'Theme.ets');
const OUT = join(ROOT, 'entry', 'src', 'main', 'resources', 'rawfile', 'pottery', 'art.js');
const CHECK = process.argv.slice(2).includes('--check');

// 出现过的类型注解一律列在这里：剥的时候按整词删，比数字前先两边同删
const TYPES = ['CanvasRenderer', 'CanvasRenderingContext2D', 'CanvasGradient', 'MotifPainter',
  'number[][]', 'string[]', 'number[]', 'Palette', 'string', 'number', 'boolean', 'void'];

function fail(msg) {
  console.error('生成失败: ' + msg);
  process.exit(1);
}

/* 注释状态机：字符串里的 #D9A173 算字面量要留着，注释里的数字不算 */
function noComments(src) {
  let out = '';
  let i = 0;
  let mode = 'code';
  let q = '';
  while (i < src.length) {
    const ch = src[i];
    const nx = src[i + 1];
    if (mode === 'code') {
      if (ch === '/' && nx === '/') { mode = 'line'; i += 2; continue; }
      if (ch === '/' && nx === '*') { mode = 'block'; i += 2; continue; }
      if (ch === '"' || ch === "'" || ch === '`') { mode = 'str'; q = ch; out += ch; i++; continue; }
      out += ch; i++; continue;
    }
    if (mode === 'line') {
      if (ch === '\n') { mode = 'code'; out += ch; }
      i++; continue;
    }
    if (mode === 'block') {
      if (ch === '*' && nx === '/') { mode = 'code'; i += 2; continue; }
      if (ch === '\n') out += ch;
      i++; continue;
    }
    if (ch === '\\') { out += ch + (nx || ''); i += 2; continue; }
    if (ch === q) mode = 'code';
    out += ch; i++;
  }
  return out;
}

const nums = (s) => (s.match(/\d+\.\d+|\d+/g) || []).join(',');
const norm = (s) => {
  let t = s;
  for (const ty of TYPES) t = t.split(ty).join('');
  return nums(t);
};

// 只删 import 行和 export type 别名，其余一行都不许动
function strip(src) {
  const lines = src.split(/\r?\n/);
  const out = [];
  const dropped = [];
  for (let i = 0; i < lines.length; i++) {
    const t = lines[i].trim();
    if (t.startsWith('import ')) {
      dropped.push({ why: 'import', line: t });
      continue;
    }
    if (t.startsWith('export type ')) {
      let j = i;
      while (j < lines.length && !lines[j].endsWith(';')) {
        dropped.push({ why: 'type', line: lines[j].trim() });
        j++;
      }
      i = j;
      continue;
    }
    out.push(lines[i]);
  }
  const kept = out.join('\n');
  let js = kept;
  for (const ty of TYPES) {
    js = js.split(': ' + ty).join('');
    js = js.split(':' + ty).join('');
  }
  js = js.replace(/\s+as\s+[A-Za-z_][\w<>|. ]*/g, '');
  return { js, kept, dropped };
}

// 按大括号配对抠出一个顶层函数（含 export 前缀原样保留）
function topFn(src, name) {
  const i = src.indexOf('function ' + name + '(');
  if (i < 0) fail('找不到函数 ' + name);
  const head = src.slice(Math.max(0, src.lastIndexOf('\n', i) + 1), i);
  let depth = 0;
  let k = src.indexOf('{', i);
  for (; k < src.length; k++) {
    if (src[k] === '{') depth++;
    else if (src[k] === '}' && --depth === 0) break;
  }
  const st = strip(noComments(src.slice(i, k + 1)));
  if (norm(st.kept) !== norm(st.js)) fail(`抠 ${name}() 时剥类型动了数字`);
  return (head.includes('export') ? 'export ' : '') + st.js;
}

function checked(label, st) {
  for (const d of st.dropped) {
    if (d.why !== 'import' && d.why !== 'type') fail(`${label}: 剥类型删掉了代码行 ${d.line}`);
  }
  if (norm(st.kept) !== norm(st.js)) {
    const a = norm(st.kept).split(',');
    const b = norm(st.js).split(',');
    let k = 0;
    while (k < a.length && k < b.length && a[k] === b[k]) k++;
    fail(`${label}: 第 ${k} 个数字起不一致 ets=${a.slice(k, k + 8)} js=${b.slice(k, k + 8)}`);
  }
  console.log(`  ${label}: 删 ${st.dropped.length} 行 import/类型，`
    + `留下的 ${norm(st.js).split(',').filter((x) => x !== '').length} 个数字字面量逐个一致`);
}

/* ── PotteryArt.ets 整体剥成模块体 ─────────────────────────────── */
const artSrc = readFileSync(ART_ETS, 'utf8');
const art = strip(noComments(artSrc));
checked('PotteryArt.ets', art);
// 画法是纯函数：不该出现组件状态或 ArkUI 专有 API
if (/\bthis\.(shape|motif|glaze|seed|word|pedestal|c2d)\b/.test(art.js)) {
  fail('PotteryArt.ets 里出现了组件字段，生成出来的模块在 Web 侧跑不了');
}

/* ── Theme.ets：色板 + paletteOf/withAlpha/hexLum 同样机械抠 ─────── */
const themeSrc = readFileSync(THEME_ETS, 'utf8');
const palEntries = [...themeSrc.matchAll(/\['([a-z]+)',\s*\{([^}]*)\}\]/g)];
if (palEntries.length !== 6) fail(`从 Theme.ets 取到 ${palEntries.length} 套色板，应为 6 套`);
for (const [, key, inner] of palEntries) {
  const fields = [...inner.matchAll(/(\w+):\s*'#[0-9A-Fa-f]{6}'/g)].map((m) => m[1]);
  if (fields.length !== 5) fail(`色板 ${key} 只有 ${fields.length} 个字段，应为 base/deep/accent/ink/paper`);
}
const themeFn = ['paletteOf', 'withAlpha', 'hexLum'].map((n) => topFn(themeSrc, n)).join('\n\n');
console.log(`  Theme.ets: 色板 ${palEntries.length} 套 ×5 字段，paletteOf/withAlpha/hexLum 取自源码`);

const HEADER = `/*
 * ⚠ 生成文件，别手改：改 ets/common/PotteryArt.ets 或 Theme.ets，
 *   然后跑 \`node tools/emit_pottery_art.mjs\` 重新生成。
 *
 * 这是彩陶画法的唯一真值在 Web 侧的投影：ArkWeb 真 3D 页（pottery.js）用它把
 * 釉色渐变、六种纹样带、题字、纸底、展示座画进一张展开的 CanvasTexture，
 * 所以「真 3D 看到的纹样」和「二维版 / 降级转台罩的纹样」是同一份代码画的。
 * 类型注解按「只删注解不删数字」的规则剥掉，生成时断言过两边数字字面量逐个相等。
 */
`;

const module = HEADER
  + '\n// ↓ Theme.ets 的色板与颜色工具\n'
  + 'const PALETTES = new Map([\n'
  + palEntries.map(([, k, inner]) => `  ['${k}', {${inner}}]`).join(',\n')
  + '\n]);\n\n' + themeFn
  + '\n\n// ↓ PotteryArt.ets 剥类型后的画法本体（export 原样保留）\n'
  + art.js.replace(/\r\n/g, '\n') + '\n';

if (CHECK) {
  if (!existsSync(OUT)) fail('rawfile 里没有 art.js，先跑一次生成');
  const cur = readFileSync(OUT, 'utf8').replace(/\r\n/g, '\n');
  if (cur !== module) {
    fail('rawfile/pottery/art.js 与 .ets 源码不同步，跑 node tools/emit_pottery_art.mjs 重新生成');
  }
  console.log('校验通过：art.js 与 PotteryArt.ets / Theme.ets 同步');
} else {
  writeFileSync(OUT, module);
  console.log(`生成 → ${OUT}（${(Buffer.byteLength(module) / 1024).toFixed(1)} KiB）`);
}
