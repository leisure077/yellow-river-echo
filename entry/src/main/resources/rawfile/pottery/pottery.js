import * as THREE from '/experience/vendor/three.module.js';
import { VIEW, SHAPES, buildVessel, glazeMaterial, lights } from '/pottery/geometry.js';
import { paletteOf, drawBand, drawWord, drawPaper, drawPedestal, halfWidthAt } from '/pottery/art.js';

const FW = VIEW.w;
const FH = VIEW.h;
const SPIN_DEG_PER_MS = 360 / 8000;
const RESUME_MS = 2500;
const LIGHT_K = 1.34;

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
let scale = 1;
let kCss = 1;
let dpr = 1;

function shapeKey(label) {
  const hit = SHAPES.find((s) => s.label === label);
  return hit ? hit.key : SHAPES[0].key;
}

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
  if (meta === null || meta.shapeKey !== key) {
    const probe = buildVessel(THREE, key, VIEW,
      new THREE.MeshBasicMaterial(), new THREE.MeshBasicMaterial());
    meta = probe.userData;
    probe.traverse((o) => {
      if (o.geometry) { o.geometry.dispose(); }
    });
  }
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
  const trim = new THREE.MeshStandardMaterial({
    color: new THREE.Color(p.base), roughness: 0.95, metalness: 0.0, side: THREE.DoubleSide
  });
  mats = [mat, trim];
  holder = buildVessel(THREE, shapeKey(S.shape), VIEW, mat, trim);
  meta = holder.userData;
  scene.add(holder);
  drawBg(p);
}

function drawBg(p) {
  bgc.setTransform(dpr, 0, 0, dpr, 0, 0);
  bgc.clearRect(0, 0, window.innerWidth, window.innerHeight);
  drawPaper(bgc, p, S.seed, window.innerWidth, window.innerHeight);
  bgc.setTransform(scale, 0, 0, scale, stage.offsetLeft * dpr, stage.offsetTop * dpr);
  drawPedestal(bgc, p, S.shape, S.box, meta.botPx, FW, FH);
}

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
  pixelStats() {
    const c = document.createElement('canvas');
    c.width = gl.width;
    c.height = gl.height;
    const g = c.getContext('2d', { willReadFrequently: true });
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
      at: [Math.round(gl.offsetLeft), Math.round(gl.offsetTop),
        Math.round(stage.offsetLeft), Math.round(stage.offsetTop)]
    });
  },
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
    const uu = 2 * Math.tan(THREE.MathUtils.degToRad(VIEW.fov / 2)) * VIEW.camZ / VIEW.h;
    const lineAt = (f) => {
      const t = meta.band[0] + (meta.band[1] - meta.band[0]) * f;
      const y = meta.topPx + (meta.botPx - meta.topPx) * t;
      const z = halfWidthAt(S.shape, t, FW) * uu;
      return FH / 2 + (y - FH / 2) * VIEW.camZ / Math.max(0.001, VIEW.camZ - z);
    };
    return JSON.stringify({
      top: rr(first), bottom: rr(last), cands: cands,
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
