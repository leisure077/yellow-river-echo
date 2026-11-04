#!/usr/bin/env node
/**
 * 彩陶工坊 · 无 WebGL 降级用的 24 帧转台序列烘焙
 *
 * 干什么：用本地 headless Chrome + 仓库里已打包的 three.js r160，把 5 种器型
 * 各转 24 个角度（每 15° 一帧）渲成透明底灰模帧，写进
 *   entry/src/main/resources/rawfile/pottery/turntable/<器型键>/<帧号>.webp
 * 并生成映射表 turntable/index.json（ArkTS 侧按它决定每个器型有几帧、
 * 器身在帧里的像素位置、纹样带区间）。
 *
 * 为什么灰模不带颜色：釉色和纹样要由 App 端实时叠加（换釉色不能重烘 120 张图），
 * 所以帧必须是中性灰 + 透明背景，ArkTS 用 Canvas 的 source-atop 把颜色罩在器物上。
 *
 * 用法：
 *   node tools/bake_pottery_frames.mjs            # 烘全部 5 器型，写 rawfile
 *   node tools/bake_pottery_frames.mjs --dry      # 只烘到 .tmp 并打印报告，不动 rawfile
 *   node tools/bake_pottery_frames.mjs --check    # 只校验：帧数/映射表/是否出画，不重写文件
 *   node tools/bake_pottery_frames.mjs --compare  # 同一帧试几种编码，报体积，用来定格式
 *   node tools/bake_pottery_frames.mjs --fmt=image/png --dry   # 换编码格式
 *
 * 纯本地开发工具，不进 App 代码、不进包。
 */
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync, rmSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const RAW = join(ROOT, 'entry', 'src', 'main', 'resources', 'rawfile');
const VENDOR = join(RAW, 'experience', 'vendor');
const GEOMETRY = join(RAW, 'pottery', 'geometry.js');
const OUT_DIR = join(RAW, 'pottery', 'turntable');
const STAGE = join(ROOT, '.tmp', 'pottery_bake');
const CHROME = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const WEB_PORT = 9241;
const CDP_PORT = 9242;
const FRAMES = 24;
// VIEW 直接从 geometry.js 取：烘焙视口和 App 里真 3D 页用的是同一个数，
// 免得脚本里改成了 512×640、geometry 里还是别的值，烘出来的帧和映射表错位
const { VIEW } = await import(pathToFileURL(GEOMETRY).href);

const argv = process.argv.slice(2);
const DRY = argv.includes('--dry');
const fmtArg = argv.find((a) => a.startsWith('--fmt='));
/* 默认 webp q=0.99，不是 png。实测（512×640 透明灰模、同一批帧）：
     png  toDataURL → 120.6 KiB/帧、120 帧 14.13 MiB（Chrome 的 png 编码器不带调色板）
     webp q=0.99     →  12.8 KiB/帧、120 帧 1.50 MiB
     webp q=1        →  55.2 KiB/帧、120 帧 6.46 MiB（再往上就跳一个量级，不值）
   关键是 Chrome 的 webp 走 VP8X 扩展格式，alpha 通道是无损的：
   与 png 真值逐像素比，alpha MAE=0.00、max=0，也就是器物轮廓一位不差；
   有损只发生在 RGB 上，器身内部 MAE≈1.0、max≤6（占 255 的 2.4%）。
   轮廓无损是硬要求——App 端用 source-atop 把釉色和纹样裁进器身，
   alpha 一旦有毛边，罩色就会漏到器物外面。 */
const FMT = fmtArg ? fmtArg.slice(6) : 'image/webp';
const MIME_EXT = { 'image/png': 'png', 'image/webp': 'webp' };
const QUALITY = (() => {
  const a = argv.find((v) => v.startsWith('--q='));
  if (!a) return FMT === 'image/webp' ? 0.99 : undefined;
  const n = Number(a.slice(4));
  // toDataURL 的 quality 是 0~1 的浮点；写成 85 这种百分数时帮他换算，
  // 否则会被浏览器钳成 1，等于悄悄换了档
  return n > 1 ? n / 100 : n;
})();
const CHECK = argv.includes('--check');
const COMPARE = argv.includes('--compare');

const BAKE_HTML = `<!doctype html>
<html lang="zh"><head><meta charset="utf-8">
<style>html,body{margin:0;padding:0;background:transparent;overflow:hidden}
canvas{display:block;width:${VIEW.w}px;height:${VIEW.h}px}</style>
<script type="module">
import * as THREE from '/vendor/three.module.js';
import { VIEW, SHAPES, buildVessel, greyMaterial, lights } from '/pottery/geometry.js';

window.__errs = [];
window.addEventListener('error', (e) => window.__errs.push(String(e.message)));

const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(1);
renderer.setSize(VIEW.w, VIEW.h, false);
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(VIEW.fov, VIEW.w / VIEW.h, 0.05, 100);
camera.position.set(0, 0, VIEW.camZ);
camera.lookAt(0, 0, 0);
lights(THREE, scene);

let holder = null;
const mat = greyMaterial(THREE);

window.__potBake = (key) => {
  if (holder) { scene.remove(holder); }
  holder = buildVessel(THREE, key, VIEW, mat);
  scene.add(holder);
  renderer.render(scene, camera);
  return JSON.parse(JSON.stringify(holder.userData));
};
window.__potSpin = (deg) => {
  if (!holder) return false;
  holder.rotation.y = THREE.MathUtils.degToRad(Number(deg) || 0);
  holder.updateMatrixWorld(true);
  renderer.render(scene, camera);
  return true;
};

/* 像素级出画校验：把 WebGL 画布搬到 2D 画布上读 alpha，算真正有内容的包围盒。
   顶点投影只能算个大概，视口尺寸对不对、器身有没有被切掉，只有量像素说得清。 */
let scratch = null;
function to2d() {
  if (!scratch) {
    scratch = document.createElement('canvas');
    scratch.width = VIEW.w;
    scratch.height = VIEW.h;
  }
  const g = scratch.getContext('2d', { willReadFrequently: true });
  g.clearRect(0, 0, VIEW.w, VIEW.h);
  g.drawImage(renderer.domElement, 0, 0, VIEW.w, VIEW.h);
  return g;
}

window.__potAlphaBox = () => {
  if (!holder) return null;
  const g = to2d();
  const d = g.getImageData(0, 0, VIEW.w, VIEW.h).data;
  let minX = 1e9, maxX = -1, minY = 1e9, maxY = -1;
  for (let y = 0; y < VIEW.h; y++) {
    for (let x = 0; x < VIEW.w; x++) {
      if (d[(y * VIEW.w + x) * 4 + 3] > 8) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  return { minX, maxX, minY, maxY, w: VIEW.w, h: VIEW.h };
};

/* 出图走 toDataURL，不走 Page.captureScreenshot：
   后者带 omitBackground 时会把 WebGL 的透明背景拍平成纯白（实测角点 255,255,255,255），
   灰模帧一旦没有 alpha，App 端就没法用 source-atop 把釉色和纹样裁进器身轮廓里。 */
window.__potShot = (mime, q) => {
  if (!holder) return null;
  to2d();
  return scratch.toDataURL(mime || 'image/png', q).split(',')[1];
};
/* 出图尺寸自检。注意 scratch 是 module 作用域的变量，Runtime.evaluate 看不到，
   只能通过 window 上的函数问它——直接在表达式里写 scratch.width 会 ReferenceError。 */
window.__potDims = () => JSON.stringify({
  got: scratch ? [scratch.width, scratch.height] : null,
  want: [VIEW.w, VIEW.h]
});
window.__potShapes = () => JSON.stringify(SHAPES.map((s) => s.key));
window.__potOk = () => !!renderer.getContext();
<\/script></head><body></body></html>`;

function serve() {
  const mime = { '.html': 'text/html', '.js': 'text/javascript' };
  return new Promise((res, rej) => {
    const s = createServer(async (req, rep) => {
      const path = req.url.split('?')[0];
      let file = null;
      if (path === '/bake.html') {
        rep.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
        rep.end(BAKE_HTML);
        return;
      }
      if (path.startsWith('/vendor/')) {
        file = join(VENDOR, path.slice('/vendor/'.length));
      } else if (path === '/pottery/geometry.js') {
        file = GEOMETRY;
      }
      if (!file || !existsSync(file)) {
        rep.writeHead(404); rep.end('not found: ' + path); return;
      }
      rep.writeHead(200, { 'content-type': (mime[path.slice(-3)] || 'text/plain') + '; charset=utf-8' });
      rep.end(readFileSync(file));
    });
    s.on('error', rej);
    s.listen(WEB_PORT, '127.0.0.1', () => res(s));
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function cdpSession() {
  let page = null;
  for (let i = 0; i < 80 && !page; i++) {
    await sleep(250);
    try {
      const list = await (await fetch(`http://127.0.0.1:${CDP_PORT}/json/list`)).json();
      page = list.find((t) => t.type === 'page');
    } catch (e) { /* Chrome 还在起 */ }
  }
  if (!page) {
    throw new Error('拿不到 CDP target，Chrome 可能没起来（看 stderr）');
  }
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  let seq = 0;
  const waiting = new Map();
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && waiting.has(msg.id)) {
      waiting.get(msg.id)(msg);
      waiting.delete(msg.id);
    }
  };
  const send = (method, params = {}) => new Promise((res) => {
    const id = ++seq;
    waiting.set(id, res);
    ws.send(JSON.stringify({ id, method, params }));
  });
  const evalJs = async (expression) => {
    const r = await send('Runtime.evaluate', { expression, returnByValue: true });
    const inner = r.result || {};
    if (inner.exceptionDetails) {
      throw new Error('页面异常: ' + JSON.stringify(inner.exceptionDetails).slice(0, 300));
    }
    return inner.result ? inner.result.value : undefined;
  };
  return { ws, send, evalJs };
}

function hash(buf) {
  return createHash('sha1').update(buf).digest('hex').slice(0, 12);
}

/* --check：不重烘，只核对 rawfile 里的帧文件与 index.json 声明是否一致。
   改了 geometry.js 忘了重烘时，这一步会直接失败。 */
function checkOnly() {
  const json = join(OUT_DIR, 'index.json');
  if (!existsSync(json)) {
    throw new Error('rawfile 里没有 ' + json + '，先跑一次烘焙');
  }
  const table = JSON.parse(readFileSync(json, 'utf8'));
  let bytes = 0;
  for (const key of Object.keys(table.shapes)) {
    const s = table.shapes[key];
    const dir = join(OUT_DIR, key);
    if (!existsSync(dir)) {
      throw new Error(`${key} 缺目录 ${dir}`);
    }
    const ext = table.ext || 'png';
    const files = readdirSync(dir).filter((n) => n.endsWith('.' + ext));
    if (files.length !== s.frames) {
      throw new Error(`${key}(${s.label}) 声明 ${s.frames} 帧，目录里 ${files.length} 个 ${ext}`);
    }
    for (let f = 0; f < table.frames; f++) {
      if (!existsSync(join(dir, `${f}.${ext}`))) {
        throw new Error(`${key} 缺第 ${f} 帧`);
      }
    }
    for (const n of files) {
      bytes += readFileSync(join(dir, n)).length;
    }
    console.log(`  ${s.label}(${key}) ${s.frames} 帧 ✓`);
  }
  console.log(`校验通过：${Object.keys(table.shapes).length} 个器型、共 ${(bytes / 1024 / 1024).toFixed(2)} MiB`);
}

async function main() {
  if (CHECK) {
    checkOnly();
    return;
  }
  if (!existsSync(CHROME)) {
    throw new Error('找不到 Chrome：' + CHROME + '（可用环境变量 CHROME 指定）');
  }
  // Windows 上刚关掉的 Chrome 偶尔还会占着这个目录几百毫秒，直接删会 EPERM
  rmSync(STAGE, { recursive: true, force: true, maxRetries: 8, retryDelay: 250 });
  mkdirSync(STAGE, { recursive: true });

  const server = await serve();
  const chrome = spawn(CHROME, [
    '--headless=new', `--remote-debugging-port=${CDP_PORT}`, '--window-size=512,640',
    '--force-device-scale-factor=1', '--hide-scrollbars', '--no-sandbox',
    '--disable-dev-shm-usage', '--use-gl=angle', '--use-angle=swiftshader',
    '--enable-unsafe-swiftshader', 'about:blank'
  ], { stdio: ['ignore', 'ignore', 'pipe'] });
  let chromeErr = '';
  chrome.stderr.on('data', (d) => { chromeErr += d.toString(); });

  try {
    const cdp = await cdpSession();
    await cdp.send('Page.enable');
    await cdp.send('Runtime.enable');
    // 关键：--window-size 不等于视口（实测给出的是 500×486），不锁死视口的话
    // 截出来的帧比 512×640 小一圈，等于把罐底裁掉了
    await cdp.send('Emulation.setDeviceMetricsOverride',
      { width: VIEW.w, height: VIEW.h, deviceScaleFactor: 1, mobile: false });
    await cdp.send('Page.navigate', { url: `http://127.0.0.1:${WEB_PORT}/bake.html` });

    let ok = false;
    for (let i = 0; i < 60 && !ok; i++) {
      await sleep(300);
      ok = await cdp.evalJs(`window.__potOk ? !!window.__potOk() : false`);
    }
    if (!ok) {
      const errs = await cdp.evalJs(`JSON.stringify(window.__errs || 'no page')`);
      throw new Error(`烘焙页没跑起来 errs=${errs} stderr=${chromeErr.slice(0, 300)}`);
    }
    const keys = JSON.parse(await cdp.evalJs(`window.__potShapes()`));
    console.log(`three.js 就绪，器型：${keys.join(' / ')}`);

    /* --compare：同一帧用几种编码各出一次图，报文件头、体积和 120 帧外推值。
       透明灰模帧的体积直接决定走 png 还是 webp，先量再选，别按印象拍。 */
    if (COMPARE) {
      await cdp.evalJs(`window.__potBake('guan')`);
      await cdp.evalJs(`window.__potSpin(75)`);
      const combos = [['image/png', 1], ['image/webp', 1], ['image/webp', 0.99],
        ['image/webp', 0.98], ['image/webp', 0.95], ['image/webp', 0.9], ['image/webp', 0.8]];
      for (const [mime, q] of combos) {
        const b64 = await cdp.evalJs(`window.__potShot('${mime}', ${q})`);
        const buf = Buffer.from(b64, 'base64');
        const magic = buf.toString('latin1', 0, 16).replace(/[^\x20-\x7e]/g, '.');
        console.log(`  ${mime} q=${q} → ${(buf.length / 1024).toFixed(1)} KiB/帧` +
          ` 外推 120 帧 ${(buf.length * 120 / 1024 / 1024).toFixed(2)} MiB | 头 ${magic}`);
      }
      cdp.ws.close();
      return;
    }

    const table = {
      frames: FRAMES,
      canvas: [VIEW.w, VIEW.h],
      degStep: 360 / FRAMES,
      ext: MIME_EXT[FMT] || 'png',
      enc: `${FMT}${QUALITY === undefined ? '' : ' q=' + QUALITY}`,
      shapes: {}
    };
    let totalBytes = 0;
    const targetRoot = DRY ? join(STAGE, 'out') : OUT_DIR;

    for (const key of keys) {
      const meta = JSON.parse(await cdp.evalJs(`JSON.stringify(window.__potBake('${key}'))`));
      const dir = join(targetRoot, key);
      mkdirSync(dir, { recursive: true });
      let box = null;
      const hashes = new Set();
      let dup = 0;
      const t0 = Date.now();
      for (let f = 0; f < FRAMES; f++) {
        await cdp.evalJs(`window.__potSpin(${f * table.degStep})`);
        // 逐帧累计内容包围盒：24 个角度都不许贴到画布边（贴边=被裁=出画）
        const b = JSON.parse(await cdp.evalJs(`JSON.stringify(window.__potAlphaBox())`));
        box = box ? {
          minX: Math.min(box.minX, b.minX), maxX: Math.max(box.maxX, b.maxX),
          minY: Math.min(box.minY, b.minY), maxY: Math.max(box.maxY, b.maxY)
        } : b;
        const b64 = await cdp.evalJs(`window.__potShot('${FMT}', ${QUALITY})`);
        if (!b64 || typeof b64 !== 'string' || b64.length < 1000) {
          throw new Error(`${key} 第 ${f} 帧没截出来（toDataURL 返回 ${String(b64).slice(0, 40)}）`);
        }
        const buf = Buffer.from(b64, 'base64');
        if (f === 0) {
          // 尺寸断言放在页面里做，不去解析图片头：webp 的宽高散在 VP8/VP8L/VP8X
          // 三种子块里、偏移各不相同，手写解析错过一次（算出过 16129x1025 这种鬼数）。
          // scratch 画布的宽高就是帧的宽高，量它既准又不会因编码格式变化而失效。
          const { got, want } = JSON.parse(await cdp.evalJs(`window.__potDims()`));
          if (!got || got[0] !== want[0] || got[1] !== want[1]) {
            throw new Error(`出图画布是 ${JSON.stringify(got)}，不是 ${want.join('x')}`);
          }
          const magic = buf.toString('latin1', 0, 16).replace(/[^\x20-\x7e]/g, '.');
          console.log(`  ${key} 帧头 ${magic} 出图 ${got.join('x')}`);
        }
        // 不做「相同帧只留一份」的去重：旋转体每转 15° 刻面与灯光的相对角度都会变，
        // 逐像素哈希基本不重复，留 24 帧也让 ArkTS 侧的映射表退化成一句 frame % 24。
        if (hashes.has(hash(buf))) {
          dup++;
        }
        hashes.add(hash(buf));
        writeFileSync(join(dir, `${f}.${MIME_EXT[FMT] || 'png'}`), buf);
        totalBytes += buf.length;
      }
      const out = {
        key,
        label: meta.label,
        frames: FRAMES,
        symmetric: !!meta.symmetric,
        topPx: Math.round(meta.topPx),
        botPx: Math.round(meta.botPx),
        maxHalfPx: Math.round(meta.maxHalfPx),
        rimHalfPx: Math.round(meta.rimHalfPx),
        band: meta.band,
        ms: Date.now() - t0
      };
      table.shapes[key] = out;
      const clipped = box.minX <= 1 || box.maxX >= VIEW.w - 2
        || box.minY <= 1 || box.maxY >= VIEW.h - 2;
      console.log(`  ${out.label}(${key}) ${out.frames} 帧（重复 ${dup}）` +
        ` 带附件=${!out.symmetric} 内容框=[${box.minX},${box.maxX}]×[${box.minY},${box.maxY}]` +
        `${clipped ? '  ⚠ 贴边/出画' : ''} ${out.ms}ms`);
      if (clipped) {
        throw new Error(`${key} 的帧内容贴到画布边（被裁），不能烘`);
      }
    }
    table.totalBytes = totalBytes;
    writeFileSync(join(targetRoot, 'index.json'), JSON.stringify(table, null, 2) + '\n');
    console.log(`映射表：${join(targetRoot, 'index.json')}`);
    console.log(`序列帧合计 ${(totalBytes / 1024 / 1024).toFixed(2)} MiB` +
      `${DRY || CHECK ? '（--dry/--check，未写 rawfile）' : ' → rawfile/pottery/turntable'}`);
    if (DRY) {
      writeFileSync(join(STAGE, 'report.json'), JSON.stringify(table, null, 2) + '\n');
      console.log('--dry：报告写在 .tmp/pottery_bake/report.json，未改 rawfile');
    }
    cdp.ws.close();
  } finally {
    chrome.kill();
    server.close();
  }
}

main().catch((e) => {
  console.error('烘焙失败:', e.message);
  process.exit(1);
});
