/*
 * 彩陶工坊 · 真 3D 主路径（ArkWeb 内的 three.js 页）
 *
 * 和降级链路的关系：这一页只在设备真有 WebGL 时才用（探针就是本页自己——
 * renderer 建不起来就报 fallback，宿主观景的 PotteryTurntable 顶上）。
 * 两条链路共用同一份数据源：
 *   器型网格  = pottery/geometry.js（和烘 24 帧灰模用的是同一个 buildVessel）
 *   画法/色板 = pottery/art.js（由 tools/emit_pottery_art.mjs 从 PotteryArt.ets 生成）
 * 所以「能跑 WebGL 看到的罐」和「跑不动 WebGL 看到的罐」是同一套轮廓、同一张纹样，
 * 不是两套近似实现。
 *
 * 贴图思路：器身是 LatheGeometry，展开方向天然就是圆周。geometry.js 里把它的 v
 * 重写成「帧像素」口径（y = topPx + t·(botPx-topPx)），于是这里只要把二维版那张
 * 「釉色渐变 + 纹样带 + 题字」按展开周期 per = π·maxHalfPx 画成一条横图，
 * 贴上去 repeat.x=2 / offset.x=0.5 就正好和降级转台的弧度罩层对齐同一圈位置。
 * 纸底和展示座画在 WebGL 画布下面的第二张 2D 画布上（器身以外全透明），
 * 这样二维版那套 drawPaper/drawPedestal 一行都不用改就能复用。
 */
import * as THREE from '/experience/vendor/three.module.js';
import { VIEW, SHAPES, buildVessel, glazeMaterial, lights } from '/pottery/geometry.js';
import { paletteOf, drawBand, drawWord, drawPaper, drawPedestal, halfWidthAt } from '/pottery/art.js';

const FW = VIEW.w;
const FH = VIEW.h;
const SPIN_DEG_PER_MS = 360 / 8000;   // 没人动的时候 8 秒转一圈，和转台自动轮播同量级
const RESUME_MS = 2500;               // 手离开多久后接着转
const LIGHT_K = 1.34;                 // 灯光总系数：按「罩完的中位亮度 = 二维目标」反解出来的
// 推导（.tmp/pot3d/check.mjs 第一轮实测）：sRGB 亮度在光照下是线性相乘再开 2.2 次方，
// K=0.62 时六套釉色一律比二维暗 27~55 个亮度级（仰韶 121 vs 目标 172.5），
// 换算成线性口径 E = 0.463 = 0.747·K，要 E=1 就得 K = 1/0.747 ≈ 1.34。
// 灰模那条链路用的是 K=1（烘帧时灯光就按接近白的灰模调过），不能拿过来直接用：
// 贴图本身就是釉色，再按灰模的亮度打光必然暗一截。

const stage = document.getElementById('stage');
const bg = document.getElementById('bg');
const gl = document.getElementById('gl');
const bgc = bg.getContext('2d');
const native = (fn, arg) => {
  try {
    if (window.Native && typeof window.Native[fn] === 'function') {
      window.Native[fn](arg === undefined ? '' : String(arg));
    }
  } catch (e) { /* 浏览器里直接跑（headless 自检）时没有宿主，忽略 */ }
};

const q = new URLSearchParams(location.search);
const S = {
  shape: q.get('shape') || '罐',
  motif: q.get('motif') || '鱼纹',
  glaze: q.get('glaze') || 'yangshao',
  box: q.get('box') || '素台',
  word: q.get('word') || '',
  seed: Number(q.get('seed') || 1)
};

let renderer = null;
try {
  renderer = new THREE.WebGLRenderer({ canvas: gl, antialias: true, alpha: true });
  if (!renderer.getContext()) {
    throw new Error('no gl context');
  }
} catch (e) {
  native('setMode', 'fallback');
  native('onErr', String((e && e.message) || e));
}

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(VIEW.fov, FW / FH, 0.05, 100);
camera.position.set(0, 0, VIEW.camZ);
camera.lookAt(0, 0, 0);
lights(THREE, scene, LIGHT_K);

let holder = null;
let meta = null;
let sheet = null;
let mats = [];
let deg = 0;
let dragging = false;
let lastX = 0;
let idleAt = 0;
let scale = 1;      // 画布像素 / 帧像素
let kCss = 1;       // CSS 像素 / 帧像素
let dpr = 1;

function shapeKey(label) {
  const hit = SHAPES.find((s) => s.label === label);
  return hit ? hit.key : SHAPES[0].key;
}

/* 展开贴图：一个周期 = 半周长 πR，画一次纹样，绕器身两周（repeat.x=2）。
   周期取 πR 而不是 2πR，是为了和降级转台的 wrap() 用同一个数——那边每转 15°
   罩的就是这条带的不同区段，两边周期不一致的话换设备就能看出纹样疏密不同。 */
function buildSheet(p) {
  const per = Math.PI * meta.maxHalfPx;
  const w = Math.max(2, Math.round(per));
  if (!sheet) {
    sheet = document.createElement('canvas');
  }
  sheet.width = w;
  sheet.height = FH;
  const c = sheet.getContext('2d');
  c.clearRect(0, 0, w, FH);
  const y0 = meta.topPx;
  const y1 = meta.botPx;
  // 釉色：stop 与二维版器身那一笔完全一致（base / base@0.55 / deep@1）。
  // 这里铺成实色，明暗交给 three 的灯光；转台那边反过来——底是灰模，得用半透明压色。
  const g = c.createLinearGradient(0, y0, 0, y1);
  g.addColorStop(0, p.base);
  g.addColorStop(0.55, p.base);
  g.addColorStop(1, p.deep);
  c.fillStyle = g;
  c.fillRect(0, y0, w, y1 - y0);
  const by0 = y0 + (y1 - y0) * meta.band[0];
  const by1 = y0 + (y1 - y0) * meta.band[1];
  drawBand(c, p, S.motif, S.seed, 0, w, by0, by1, FH);
  if (S.word.length > 0) {
    // 题字按二维版的宽高比取号、摆在展开带正中，和转台 wrap() 里同一套算法
    const wordW = 2 * meta.maxHalfPx / 0.92;
    c.save();
    c.translate(per / 2 - wordW / 2, 0);
    drawWord(c, p, S.word, S.shape, S.seed, wordW, FH);
    c.restore();
  }
}

function disposeHolder() {
  if (!holder) {
    return;
  }
  scene.remove(holder);
  holder.traverse((o) => {
    if (o.geometry) { o.geometry.dispose(); }
  });
  for (const m of mats) {
    if (m.map) { m.map.dispose(); }
    m.dispose();
  }
  mats = [];
  holder = null;
}

function rebuild() {
  const p = paletteOf(S.glaze);
  const key = shapeKey(S.shape);
  // meta 必须先于贴图更新成「这一个器型」的：带画在第几行、展开周期多长，全从它算。
  // 原来只在首次建网格时探一次 meta，之后换器型直接 buildSheet，于是每个器型贴的都是
  // 上一个器型的带（罐贴成鼎式的位置、鼎式贴成瓶的位置）。釉色亮度、器身包围盒两项
  // 断言都照样通过，是 bandRows() 那条「带落在第几行」的断言把它抓出来的。
  if (meta === null || meta.shapeKey !== key) {
    const probe = buildVessel(THREE, key, VIEW,
      new THREE.MeshBasicMaterial(), new THREE.MeshBasicMaterial());
    meta = probe.userData;
    probe.traverse((o) => {
      if (o.geometry) { o.geometry.dispose(); }
    });
  }
  // 先拆旧的再建新的：disposeHolder 认的是 mats 里那份旧材质，
  // 顺序反了就会把刚建好的贴图材质一起 dispose 掉，器物变纯白。
  if (holder) {
    disposeHolder();
  }
  buildSheet(p);
  const tex = new THREE.CanvasTexture(sheet);
  tex.wrapS = THREE.RepeatWrapping;
  tex.wrapT = THREE.ClampToEdgeWrapping;
  tex.repeat.set(2, 1);
  tex.offset.set(0.5, 0);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = renderer.capabilities.getMaxAnisotropy();
  const mat = glazeMaterial(THREE, tex);
  // 耳/足不共用器身那张展开图：Tube、Torus 自己的 UV 跟像素口径不搭，
  // 贴上去纹样会拉成面条，所以给它们一件纯色釉料（取这套釉的底色）。
  const trim = new THREE.MeshStandardMaterial({
    color: new THREE.Color(p.base), roughness: 0.95, metalness: 0.0, side: THREE.DoubleSide
  });
  mats = [mat, trim];
  holder = buildVessel(THREE, shapeKey(S.shape), VIEW, mat, trim);
  meta = holder.userData;
  scene.add(holder);
  drawBg(p);
}

// 纸底 + 展示座：画在 WebGL 画布下面那张 2D 画布上。
// 纸底铺满整个窗口（和 ArkTS 侧一样按组件宽高传 w/h，不是按 512×640 的帧），
// 展示座才用帧坐标——所以它的画布原点要平移到 stage 那一格的左上角。
function drawBg(p) {
  bgc.setTransform(dpr, 0, 0, dpr, 0, 0);
  bgc.clearRect(0, 0, window.innerWidth, window.innerHeight);
  drawPaper(bgc, p, S.seed, window.innerWidth, window.innerHeight);
  bgc.setTransform(scale, 0, 0, scale, stage.offsetLeft * dpr, stage.offsetTop * dpr);
  drawPedestal(bgc, p, S.shape, S.box, meta.botPx, FW, FH);
}

/* 视口适配：画布的像素尺寸随窗口变，但相机视场和 512:640 的宽高比锁死，
   所以器物在画布里的相对位置（topPx/botPx 那套比例）在任何分辨率下都一样。 */
function fit() {
  const vw = window.innerWidth;
  const vh = window.innerHeight;
  kCss = Math.min(vw / FW, vh / FH);
  dpr = Math.min(window.devicePixelRatio || 1, 2);
  scale = kCss * dpr;
  const sw = Math.round(FW * kCss);
  const sh = Math.round(FH * kCss);
  stage.style.width = sw + 'px';
  stage.style.height = sh + 'px';
  stage.style.left = Math.round((vw - sw) / 2) + 'px';
  stage.style.top = Math.round((vh - sh) / 2) + 'px';
  gl.style.width = sw + 'px';
  gl.style.height = sh + 'px';
  // WebGL 画布必须跟着 stage 一起平移：它是 absolute 的，不给 left/top 就退回
  // 静态位置（≈左上角），于是器身画在窗口上半格、展示座画在 stage 那一格里，
  // 两者错开一整个 letterbox 的高度——罐子直接悬在座子上方几十像素（截图实测差 116px）。
  gl.style.left = stage.style.left;
  gl.style.top = stage.style.top;
  const px = Math.max(2, Math.round(sw * dpr));
  const py = Math.max(2, Math.round(sh * dpr));
  gl.width = px;
  gl.height = py;
  bg.style.width = vw + 'px';
  bg.style.height = vh + 'px';
  bg.width = Math.max(2, Math.round(vw * dpr));
  bg.height = Math.max(2, Math.round(vh * dpr));
  renderer.setSize(px, py, false);
  camera.aspect = px / py;
  camera.updateProjectionMatrix();
  if (meta) {
    drawBg(paletteOf(S.glaze));
  }
}

// 拖多少像素就转多少：肚皮处的表面点在屏上走的正是 dx，所以 dφ = dx/R（和转台同一条式子）
function onDrag(dxPx) {
  if (!meta) {
    return;
  }
  const rCss = meta.maxHalfPx * kCss;
  if (rCss > 0) {
    deg += (dxPx / rCss) * (180 / Math.PI);
  }
}

let prevTs = 0;
function tick(ts) {
  const dt = prevTs ? Math.min(64, ts - prevTs) : 16;
  prevTs = ts;
  if (holder) {
    if (!dragging && ts - idleAt > RESUME_MS) {
      deg += SPIN_DEG_PER_MS * dt;
    }
    holder.rotation.y = THREE.MathUtils.degToRad(deg);
    renderer.render(scene, camera);
  }
  requestAnimationFrame(tick);
}

function bind() {
  window.addEventListener('pointerdown', (e) => {
    dragging = true;
    lastX = e.clientX;
  });
  window.addEventListener('pointermove', (e) => {
    if (!dragging) {
      return;
    }
    onDrag(e.clientX - lastX);
    lastX = e.clientX;
    idleAt = performance.now();
  });
  const up = () => {
    dragging = false;
    idleAt = performance.now();
  };
  window.addEventListener('pointerup', up);
  window.addEventListener('pointercancel', up);
  window.addEventListener('resize', fit);
}

// 宿主页在参数变化时调这些；返回值便于 ArkTS 侧核对「参数真的落到页面里了」
window.__pot = {
  set(json) {
    let next = {};
    try {
      next = typeof json === 'string' ? JSON.parse(json) : (json || {});
    } catch (e) {
      return 'bad json';
    }
    for (const key of ['shape', 'motif', 'glaze', 'box', 'word', 'seed']) {
      if (next[key] !== undefined) {
        S[key] = next[key];
      }
    }
    S.seed = Number(S.seed) || 1;
    rebuild();
    return window.__pot.report();
  },
  spin(degNow) {
    deg = Number(degNow) || 0;
    idleAt = performance.now();
    return String(Math.round(deg * 10) / 10);
  },
  report() {
    let vendor = 'n/a';
    try {
      const ctx = renderer.getContext();
      const dbg = ctx.getExtension('WEBGL_debug_renderer_info');
      vendor = dbg ? String(ctx.getParameter(dbg.UNMASKED_RENDERER_WEBGL)) : 'masked';
    } catch (e) { /* 拿不到就算了 */ }
    const parts = [];
    if (holder) {
      holder.traverse((o) => {
        if (o.userData && o.userData.part) { parts.push(o.userData.part); }
      });
    }
    return JSON.stringify({
      ok: !!renderer && !!renderer.getContext(),
      shape: S.shape,
      shapeKey: shapeKey(S.shape),
      motif: S.motif,
      glaze: S.glaze,
      box: S.box,
      word: S.word,
      seed: S.seed,
      deg: Math.round(deg * 10) / 10,
      scale: Math.round(scale * 1000) / 1000,
      sheet: sheet ? [sheet.width, sheet.height] : null,
      meta: meta ? {
        topPx: Math.round(meta.topPx), botPx: Math.round(meta.botPx),
        maxHalfPx: Math.round(meta.maxHalfPx), band: meta.band
      } : null,
      parts: parts.join(','),
      vendor: vendor
    });
  },
  /* 取样统计：只读 WebGL 那张画布（器身以外是透明的），并且逐行按轮廓半宽收边。
     为什么要收边：取样区是个矩形，罐子往上越来越窄，矩形的两个上角会落到纸底上；
     纸底比绝大多数釉色都亮，不收边就会把「纸」当成「釉」，六套釉色一律偏亮 30~77。
     口径与降级链路的自检脚本（.tmp/pot_preview）一字不差，两边数字才能直接对表。 */
  pixelStats() {
    const c = document.createElement('canvas');
    c.width = gl.width;
    c.height = gl.height;
    const g = c.getContext('2d', { willReadFrequently: true });
    // 现渲一帧再搬像素：没开 preserveDrawingBuffer 时，上一帧的缓冲在合成后就被清了，
    // 从 CDP 里隔帧 drawImage 会拿到一张空图。同一次任务里画完立刻读才可靠。
    if (holder) {
      holder.rotation.y = THREE.MathUtils.degToRad(deg);
      renderer.render(scene, camera);
    }
    g.drawImage(gl, 0, 0);
    const s = gl.width / FW;
    const top = meta.topPx + (meta.botPx - meta.topPx) * 0.06;
    const bot = meta.topPx + (meta.band[0] - 0.06) * (meta.botPx - meta.topPx);
    const y0 = Math.round(top * s);
    const y1 = Math.round(bot * s);
    const d = g.getImageData(0, y0, gl.width, Math.max(1, y1 - y0)).data;
    const lums = [];
    let chroma = 0;
    let n = 0;
    for (let row = 0; row < y1 - y0; row++) {
      const t = (top + row / s - meta.topPx) / (meta.botPx - meta.topPx);
      const hw = halfWidthAt(S.shape, t, FW) * 0.62 * s;
      const lo = Math.max(0, Math.round(gl.width / 2 - hw));
      const hi = Math.min(gl.width, Math.round(gl.width / 2 + hw));
      for (let x = lo; x < hi; x++) {
        const i = ((row * gl.width) + x) * 4;
        if (d[i + 3] < 250) {
          continue;
        }
        lums.push(0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2]);
        chroma += Math.max(d[i], d[i + 1], d[i + 2]) - Math.min(d[i], d[i + 1], d[i + 2]);
        n++;
      }
    }
    lums.sort((a, b) => a - b);
    const qq = (f) => lums[Math.min(lums.length - 1, Math.floor(lums.length * f))] || 0;
    const r = (v) => Math.round(v * 10) / 10;
    return JSON.stringify({
      px: n, lum: r(qq(0.5)), range: r(qq(0.95) - qq(0.05)), chroma: r(n ? chroma / n : 0)
    });
  },
  /* 器身在不透明像素里的包围盒，换算回帧坐标：
     这是「3D 画出来的位置 == 映射表说的位置」的直接断言。
     上一版 WebGL 画布忘了跟着 stage 平移，器物在窗口里整体上移了一整个
     letterbox 高度，釉色亮度却完全正常——只量颜色是抓不到的，必须量位置。 */
  bbox() {
    if (holder) {
      holder.rotation.y = THREE.MathUtils.degToRad(deg);
      renderer.render(scene, camera);
    }
    const c = document.createElement('canvas');
    c.width = gl.width;
    c.height = gl.height;
    const g = c.getContext('2d', { willReadFrequently: true });
    g.drawImage(gl, 0, 0);
    const d = g.getImageData(0, 0, c.width, c.height).data;
    let minX = 1e9;
    let maxX = -1;
    let minY = 1e9;
    let maxY = -1;
    for (let y = 0; y < c.height; y++) {
      for (let x = 0; x < c.width; x++) {
        if (d[(y * c.width + x) * 4 + 3] > 8) {
          if (x < minX) { minX = x; }
          if (x > maxX) { maxX = x; }
          if (y < minY) { minY = y; }
          if (y > maxY) { maxY = y; }
        }
      }
    }
    const s = gl.width / FW;
    const r = (v) => Math.round(v / s * 10) / 10;
    return JSON.stringify({
      left: r(minX), right: r(maxX), top: r(minY), bottom: r(maxY),
      want: { topPx: Math.round(meta.topPx), botPx: Math.round(meta.botPx) },
      // 画布在窗口里的落点：gl 的 left/top 必须和 stage 一致，否则器物和展示座错开
      at: [Math.round(gl.offsetLeft), Math.round(gl.offsetTop),
        Math.round(stage.offsetLeft), Math.round(stage.offsetTop)]
    });
  },
  /* 纹样带落在屏幕的哪几行：drawBand 会在带的上下沿各描一条 p.accent 横线，
     那两条线就是带在屏幕上的标尺。为什么单独量它：UV 口径一旦错一格（比如 v 直接
     用了归一化的 t 而不是像素 y），整条带会往下挪几十上百像素，而釉色亮度、器身
     包围盒两项照样全绿——它是「展开图真的贴在器身该在的那一圈」的独立证据。
     判据用「一行比上下都暗」而不是比色值：先按色值找 accent 像素试过，仰韶的
     deep(#A6553D) 在器身下部的暗部残差只有 26，整段下半身都被当成边线；龙山更糟，
     黑陶整件器物都落在容差圆里。边线的本质是「细、暗、横贯一圈」，那就直接量这个。 */
  bandRows() {
    if (holder) {
      holder.rotation.y = THREE.MathUtils.degToRad(deg);
      renderer.render(scene, camera);
    }
    const c = document.createElement('canvas');
    c.width = gl.width;
    c.height = gl.height;
    const g = c.getContext('2d', { willReadFrequently: true });
    g.drawImage(gl, 0, 0);
    const d = g.getImageData(0, 0, c.width, c.height).data;
    const s = gl.width / FW;
    const cx = c.width / 2;
    const half = meta.maxHalfPx * s * 0.35;
    const y0 = Math.round(meta.topPx * s);
    const y1 = Math.round(meta.botPx * s);
    const lum = new Float64Array(c.height).fill(-1);
    for (let y = y0; y <= y1; y++) {
      let sum = 0;
      let n = 0;
      for (let x = Math.round(cx - half); x <= cx + half; x++) {
        const i = (y * c.width + x) * 4;
        if (d[i + 3] > 250) {
          sum += 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];
          n++;
        }
      }
      if (n > half) {
        lum[y] = sum / n;
      }
    }
    const at = (y) => (y >= 0 && y <= c.height) ? lum[y] : -1;
    const rr = (v) => Math.round(v / s * 10) / 10;
    let first = -1;
    let last = -1;
    const cands = [];
    for (let y = y0 + 6; y <= y1 - 6; y++) {
      const v = at(y);
      if (v < 0) {
        continue;
      }
      // 邻域取 ±12 行、挖掉自身 ±5 行：带内那条题字横线宽只有几像素，
      // 而渐变是平滑的，只有真正的边线会在 12 行邻域里比基准暗 25 以上。
      let sum = 0;
      let n = 0;
      for (let k = -12; k <= 12; k++) {
        if (Math.abs(k) <= 5) {
          continue;
        }
        const w = at(y + k);
        if (w > 0) {
          sum += w;
          n++;
        }
      }
      if (n >= 8 && sum / n - v > 25) {
        if (first < 0) {
          first = y;
        }
        last = y;
        cands.push(rr(y));
      }
    }
    const rr2 = (v) => Math.round(v * 10) / 10;
    /* 「应为」那一行不能直接拿帧坐标比：3D 是透视投影，肚皮上离镜头最近的那一点
       会被放大 camZ/(camZ-z)，带子越靠上（离画面中心越远）被抬得越多——罐的上沿
       实测比正交位置高 5.7px，这是几何本身的行为，不是贴图贴歪。
       所以把同一个放大率算进期望值里，剩下的残差才是真正的 UV 误差。 */
    const uu = 2 * Math.tan(THREE.MathUtils.degToRad(VIEW.fov / 2)) * VIEW.camZ / VIEW.h;
    const lineAt = (f) => {
      const t = meta.band[0] + (meta.band[1] - meta.band[0]) * f;
      const y = meta.topPx + (meta.botPx - meta.topPx) * t;
      const z = halfWidthAt(S.shape, t, FW) * uu;
      return FH / 2 + (y - FH / 2) * VIEW.camZ / Math.max(0.001, VIEW.camZ - z);
    };
    return JSON.stringify({
      top: rr(first), bottom: rr(last), cands: cands,
      // want 直接就是帧坐标，别再除一次 s：上一版把 rr() 用在这里，
      // 报出来的「应为」被压到 0.66 倍，罐明明贴对了却判成偏 75px。
      want: [rr2(lineAt(0.03)), rr2(lineAt(0.97))]
    });
  }
};

if (renderer) {
  fit();
  rebuild();
  bind();
  native('setMode', '3d');
  requestAnimationFrame(tick);
}
