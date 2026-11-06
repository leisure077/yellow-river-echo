import * as THREE from '../experience/vendor/three.module.js';
import { GLTFLoader } from '../experience/vendor/GLTFLoader.js';
import { OrbitControls } from '../experience/vendor/OrbitControls.js';
import { toCreasedNormals } from '../experience/vendor/BufferGeometryUtils.js';
import { MeshoptDecoder } from '../experience/vendor/MeshoptDecoder.js';

const RELICS = [
  {
    file: 'models/dancer-brick.glb',
    name: '修定寺塔舞者砖',
    era: '唐',
    material: '模制陶胎、施化妆土',
    collection: '克利夫兰艺术博物馆',
    note: '砖面浮雕蓄须舞者，披帛翻卷，为塔身砌砖。',
    scope: '黄河流域文化圈 · 河南安阳修定寺塔（唐 · 塔身模制砖）',
    theme: '丝路交融',
    credit: '藏品扫描：Cleveland Museum of Art · CC BY 4.0 · 压缩版',
    recomputeNormals: false,
    yaw: 0,
    pitch: 0,
    elevation: 0.04,
    zoom: 1.1
  },
  {
    file: 'models/dragon-amphora.glb',
    name: '三彩双龙耳瓶',
    era: '唐',
    material: '三彩陶',
    collection: '芝加哥艺术博物馆',
    note: '双龙形耳贴塑于瓶颈两侧，黄绿釉在肩部交融。',
    scope: '黄河流域文化圈 · 出土地未著录（唐 · 三彩陶瓶）',
    theme: '三彩窑火',
    credit: '藏品扫描：Art Institute of Chicago · CC BY 4.0 · 压缩版',
    recomputeNormals: true,
    yaw: 0,
    pitch: 0,
    elevation: 0.16,
    zoom: 1.06
  },
  {
    file: 'models/bell.glb',
    name: '青铜镈钟',
    era: '东周',
    material: '青铜',
    collection: '大英博物馆',
    note: '舞部饰透雕交龙钮，篆间列枚，鼓部满布细纹。',
    scope: '黄河流域文化圈 · 河南出土（东周 · 青铜礼乐器）',
    theme: '礼乐文明',
    credit: '藏品扫描：artfletch · CC BY 4.0 · 压缩版',
    recomputeNormals: false,
    yaw: 0,
    pitch: 0,
    elevation: 0.16,
    zoom: 1.06
  },
  {
    file: 'models/fangyi.glb',
    name: '兽面纹青铜方彝',
    era: '西周早期',
    material: '青铜',
    collection: '史密森尼学会（美国）',
    note: '器身满饰饕餮纹、蛇纹与鸟纹，属盛酒礼器。',
    scope: '黄河流域文化圈 · 河南洛阳出土（西周早期 · 青铜礼器）',
    theme: '青铜礼器',
    credit: '藏品扫描：Smithsonian Institution · Public Domain（Zenodo）· 压缩版',
    recomputeNormals: false,
    yaw: -Math.PI / 6,
    pitch: 0,
    elevation: 0.16,
    zoom: 1.06
  },
  {
    file: 'models/andersson-vessel.glb',
    name: '安特生藏陶罐',
    era: '新石器时代',
    material: '陶',
    collection: '世界文化博物馆（瑞典）',
    note: '口沿外侈，颈侧置双耳，腹表留有烧成黑斑。',
    scope: '黄河上游文化圈 · 甘肃—青海采集（仰韶—马家窑系统 · 盛储器）',
    theme: '文明溯源',
    credit: '藏品扫描：Världskulturmuseerna · CC BY 4.0 · 压缩版',
    recomputeNormals: false,
    yaw: 0,
    pitch: 0,
    elevation: 0.16,
    zoom: 1.06
  },
  {
    file: 'models/sancai-horse.glb',
    name: '三彩马',
    era: '唐',
    material: '三彩陶',
    collection: '馆藏未著录（公开扫描）',
    note: '马身施黄褐釉，鞍鞯俱全，是唐三彩里常见的出行题材。',
    scope: '黄河流域文化圈 · 出土地未著录（唐 · 三彩陶马）',
    theme: '出行风尚',
    credit: '藏品扫描：shining3dTC · CC BY 4.0 · 压缩版',
    recomputeNormals: false,
    yaw: 0,
    pitch: 0,
    elevation: 0.14,
    zoom: 1.08
  }
];

const stage = document.getElementById('stage');
const ui = {
  back: document.getElementById('back'),
  reset: document.getElementById('reset'),
  prev: document.getElementById('prev'),
  next: document.getElementById('next'),
  hint: document.getElementById('hint'),
  loading: document.getElementById('loading'),
  loadText: document.getElementById('loadText'),
  retry: document.getElementById('retry'),
  still: document.getElementById('still'),
  stillBadge: document.getElementById('stillBadge'),
  name: document.getElementById('name'),
  era: document.getElementById('era'),
  count: document.getElementById('count'),
  theme: document.getElementById('theme'),
  note: document.getElementById('note'),
  scope: document.getElementById('scope'),
  material: document.getElementById('material'),
  collection: document.getElementById('collection'),
  credit: document.getElementById('credit')
};

function clampIndex(v) {
  const n = Number.parseInt(v, 10);
  return Number.isFinite(n) ? Math.max(0, Math.min(RELICS.length - 1, n)) : 0;
}

let index = clampIndex(new URLSearchParams(location.search).get('id'));
let loading = true;
let disposed = false;
let viewer = null;
let hintTimer = 0;
let hintShown = false;

function setLoading(show, text) {
  loading = show;
  ui.loading.classList.toggle('hidden', !show);
  ui.loading.classList.remove('error');
  ui.retry.hidden = true;
  if (text) ui.loadText.textContent = text;
}
function setLoadText(text) {
  ui.loadText.textContent = text;
}
function showFatal(text) {
  loading = true;
  ui.loading.classList.remove('hidden');
  ui.loading.classList.add('error');
  ui.loadText.textContent = text;
  ui.retry.hidden = false;
}
function showHint(text) {
  if (text) ui.hint.textContent = text;
  if (hintShown) return;
  hintShown = true;
  ui.hint.classList.add('show');
  clearTimeout(hintTimer);
  hintTimer = setTimeout(() => ui.hint.classList.remove('show'), 3600);
}
function flashHint(text) {
  if (text) ui.hint.textContent = text;
  ui.hint.classList.add('show');
  clearTimeout(hintTimer);
  hintTimer = setTimeout(() => ui.hint.classList.remove('show'), 2600);
}
function hideHint() {
  clearTimeout(hintTimer);
  ui.hint.classList.remove('show');
}
function updateFooter(relic, i) {
  ui.name.textContent = relic.name;
  ui.era.textContent = relic.era;
  ui.count.textContent = `${i + 1} / ${RELICS.length}`;
  ui.theme.textContent = relic.theme || '';
  ui.theme.hidden = !relic.theme;
  ui.note.textContent = relic.note;
  ui.scope.textContent = relic.scope || '';
  ui.material.textContent = relic.material;
  ui.collection.textContent = relic.collection;
  ui.credit.textContent = relic.credit;
}

const TURN_FRAMES = 24;

function bootTurntable(reason) {
  console.info('[relic] WebGL 不可用，改用离线转台', reason);
  ui.still.hidden = false;
  ui.stillBadge.hidden = true;
  hideHint();

  let frame = 0;
  let scale = 1;
  let dragging = false;
  let startX = 0;
  let startFrame = 0;
  let pinchDist = 0;
  let pinchScale = 1;
  let autoTimer = 0;
  let resumeTimer = 0;
  let loadToken = 0;
  let stillOnly = false;
  let cache = new Map();

  const urlOf = (i, f) => `turntable/${i}/${((f % TURN_FRAMES) + TURN_FRAMES) % TURN_FRAMES}.jpg`;

  function paint() {
    const src = stillOnly ? `stills/${index}.jpg` : urlOf(index, frame);
    if (ui.still.getAttribute('src') !== src) ui.still.src = src;
    ui.still.style.transform = scale === 1 ? '' : `scale(${scale.toFixed(3)})`;
  }

  function stopAuto() {
    clearInterval(autoTimer);
    clearTimeout(resumeTimer);
  }
  function startAuto(delay = 2600) {
    stopAuto();
    resumeTimer = setTimeout(() => {
      if (document.hidden || stillOnly) return;
      autoTimer = setInterval(() => {
        if (dragging || loading || document.hidden) return;
        frame = (frame + 1) % TURN_FRAMES;
        paint();
      }, 170);
    }, delay);
  }

  function preload(i, token) {
    cache = new Map();
    stillOnly = false;
    for (let f = 0; f < TURN_FRAMES; f++) {
      const img = new Image();
      img.src = urlOf(i, f);
      cache.set(f, img);
    }
    const first = cache.get(0);
    const done = () => {
      if (token !== loadToken) return;
      setLoading(false);
      showHint('左右拖动 · 转动文物');
    };
    first.onload = done;
    if (first.complete && first.naturalWidth > 0) done();
    first.onerror = () => {
      if (token !== loadToken) return;
      stillOnly = true;
      paint();
      setLoading(false);
      flashHint('左右拖动切换 · 真机可旋转');
    };
  }

  const pts = new Map();
  function onDown(e) {
    if (e.pointerType === 'mouse' && e.button !== 0) return;
    pts.set(e.pointerId, { x: e.clientX, y: e.clientY });
    stopAuto();
    if (pts.size === 1) {
      dragging = true;
      startX = e.clientX;
      startFrame = frame;
    } else if (pts.size === 2) {
      const [a, b] = [...pts.values()];
      pinchDist = Math.hypot(a.x - b.x, a.y - b.y);
      pinchScale = scale;
    }
  }
  function onMove(e) {
    if (!pts.has(e.pointerId)) return;
    pts.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (pts.size >= 2) {
      const [a, b] = [...pts.values()];
      const d = Math.hypot(a.x - b.x, a.y - b.y);
      if (pinchDist > 0) {
        scale = Math.min(2.4, Math.max(1, pinchScale * (d / pinchDist)));
        paint();
      }
      if (e.cancelable) e.preventDefault();
      return;
    }
    if (!dragging || stillOnly) return;
    const dx = e.clientX - startX;
    frame = ((startFrame - Math.round(dx / 9)) % TURN_FRAMES + TURN_FRAMES) % TURN_FRAMES;
    paint();
    if (e.cancelable) e.preventDefault();
  }
  function onUp(e) {
    if (!pts.has(e.pointerId)) return;
    pts.delete(e.pointerId);
    if (pts.size === 0) {
      dragging = false;
      if (scale < 1.02) scale = 1;
      paint();
      startAuto(2600);
    } else if (pts.size === 1) {
      const p = [...pts.values()][0];
      startX = p.x;
      startFrame = frame;
    }
  }
  stage.addEventListener('pointerdown', onDown);
  stage.addEventListener('pointermove', onMove, { passive: false });
  window.addEventListener('pointerup', onUp);
  window.addEventListener('pointercancel', onUp);

  viewer = {
    load(i) {
      const relic = RELICS[i];
      if (!relic) return;
      index = i;
      frame = 0;
      scale = 1;
      pts.clear();
      dragging = false;
      stopAuto();
      updateFooter(relic, i);
      const token = ++loadToken;
      setLoading(true, '正在调取文物…');
      paint();
      preload(i, token);
      startAuto(4200);
      flashHint('左右拖动 · 转动文物');
    },
    reset() {
      frame = 0;
      scale = 1;
      paint();
      startAuto(2600);
      flashHint('已复位视角');
    },
    retry() {
      this.load(index);
    }
  };
  viewer.load(index);
}

function makeRenderer() {
  const options = [
    { antialias: true, alpha: true, powerPreference: 'high-performance' },
    { antialias: false, alpha: true },
    { antialias: false, alpha: true, preserveDrawingBuffer: true }
  ];
  let last = null;
  for (const opts of options) {
    try {
      return new THREE.WebGLRenderer(opts);
    } catch (e) {
      last = e;
    }
  }
  const probe = document.createElement('canvas');
  const gl2 = probe.getContext('webgl2');
  const gl1 = gl2 ? null : probe.getContext('webgl');
  const detail = `WEBGL2=${!!gl2} WEBGL1=${!!gl1}`;
  if (last) last.message = `${last.message || ''} ${detail}`.trim();
  throw last || new Error(`无法创建 WebGL 上下文 ${detail}`);
}

function boot3D() {
  let renderer;
  try {
    renderer = makeRenderer();
  } catch (err) {
    bootTurntable(err && err.message ? err.message : String(err));
    return;
  }

  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.0;
  renderer.domElement.setAttribute('aria-label', '可旋转的文物三维模型');
  stage.appendChild(renderer.domElement);

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(38, 1, 0.01, 200);
  camera.position.set(0, 0.9, 6);

  function makeEnvironment() {
    const w = 512;
    const h = 256;
    const canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext('2d');
    const grad = ctx.createLinearGradient(0, 0, 0, h);
    grad.addColorStop(0, '#fffdf8');
    grad.addColorStop(0.42, '#f3e9d9');
    grad.addColorStop(0.72, '#d9c8ae');
    grad.addColorStop(1, '#8e7c66');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, w, h);
    const box = ctx.createRadialGradient(w * 0.3, h * 0.22, 2, w * 0.3, h * 0.22, h * 0.55);
    box.addColorStop(0, 'rgba(255,255,255,1)');
    box.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = box;
    ctx.fillRect(0, 0, w, h);
    const tex = new THREE.CanvasTexture(canvas);
    tex.mapping = THREE.EquirectangularReflectionMapping;
    tex.colorSpace = THREE.SRGBColorSpace;
    const pmrem = new THREE.PMREMGenerator(renderer);
    const env = pmrem.fromEquirectangular(tex).texture;
    tex.dispose();
    pmrem.dispose();
    return env;
  }
  const environment = makeEnvironment();
  scene.environment = environment;

  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dampingFactor = 0.075;
  controls.enablePan = false;
  controls.rotateSpeed = 0.82;
  controls.zoomSpeed = 0.85;
  controls.autoRotate = true;
  controls.autoRotateSpeed = 0.8;
  controls.touches = { ONE: THREE.TOUCH.ROTATE, TWO: THREE.TOUCH.DOLLY_ROTATE };
  controls.minPolarAngle = 0.22;
  controls.maxPolarAngle = Math.PI / 2 + 0.05;
  controls.minDistance = 1.6;
  controls.maxDistance = 12;
  controls.target.set(0, 0, 0);

  scene.add(new THREE.HemisphereLight(0xfff8ec, 0xcbbba2, 0.5));
  const keyLight = new THREE.DirectionalLight(0xfff1d8, 1.05);
  keyLight.position.set(2.6, 3.6, 4.2);
  scene.add(keyLight);
  const fillLight = new THREE.DirectionalLight(0xdfe9f2, 0.32);
  fillLight.position.set(-3.4, 1.2, 2.2);
  scene.add(fillLight);
  const rimLight = new THREE.DirectionalLight(0xffffff, 0.45);
  rimLight.position.set(-0.8, 2.2, -4.4);
  scene.add(rimLight);

  function makeShadowTexture() {
    const size = 256;
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = size;
    const ctx = canvas.getContext('2d');
    const g = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
    g.addColorStop(0, 'rgba(58,40,22,0.42)');
    g.addColorStop(0.45, 'rgba(58,40,22,0.24)');
    g.addColorStop(0.74, 'rgba(58,40,22,0.07)');
    g.addColorStop(1, 'rgba(58,40,22,0)');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, size, size);
    const tex = new THREE.CanvasTexture(canvas);
    tex.colorSpace = THREE.SRGBColorSpace;
    return tex;
  }
  const shadow = new THREE.Mesh(
    new THREE.PlaneGeometry(1, 1),
    new THREE.MeshBasicMaterial({
      map: makeShadowTexture(),
      transparent: true,
      opacity: 0.78,
      depthWrite: false,
      toneMapped: false
    })
  );
  shadow.rotation.x = -Math.PI / 2;
  shadow.visible = false;
  shadow.renderOrder = 1;
  scene.add(shadow);

  const loader = new GLTFLoader();
  loader.setMeshoptDecoder(MeshoptDecoder);

  let holder = null;
  let loadToken = 0;
  let resumeTimer = 0;
  let contextAlive = true;

  function pauseAuto() {
    controls.autoRotate = false;
    clearTimeout(resumeTimer);
  }
  function resumeAuto(delay = 3000) {
    clearTimeout(resumeTimer);
    resumeTimer = setTimeout(() => {
      if (!loading && !document.hidden) controls.autoRotate = true;
    }, delay);
  }
  controls.addEventListener('start', () => {
    pauseAuto();
    hideHint();
  });
  controls.addEventListener('end', () => resumeAuto(3000));
  renderer.domElement.addEventListener('wheel', () => {
    pauseAuto();
    resumeAuto(3000);
  }, { passive: true });
  renderer.domElement.addEventListener('pointerdown', () => {
    pauseAuto();
    hideHint();
  }, { passive: true });

  function disposeObject(root) {
    if (!root) return;
    root.traverse((o) => {
      if (o.geometry) o.geometry.dispose();
      const mats = Array.isArray(o.material) ? o.material : (o.material ? [o.material] : []);
      mats.forEach((m) => {
        for (const k in m) {
          const v = m[k];
          if (v && v.isTexture) v.dispose();
        }
        m.dispose();
      });
    });
  }
  function clearCurrent() {
    if (!holder) return;
    scene.remove(holder);
    disposeObject(holder);
    holder = null;
    shadow.visible = false;
    if (renderer.renderLists) renderer.renderLists.dispose();
  }

  async function buildRoot(gltf, relic) {
    const root = gltf.scene;

    if (relic.recomputeNormals) {
      setLoadText('正在重算表面光照…');
      await new Promise((r) => setTimeout(r, 30));
      root.traverse((o) => {
        if (!o.isMesh || !o.geometry) return;
        const old = o.geometry;
        try {
          const next = toCreasedNormals(old, Math.PI / 3);
          o.geometry = next;
          if (next !== old) old.dispose();
        } catch (e) {
          console.warn('[relic] toCreasedNormals failed', e);
          old.computeVertexNormals();
        }
        o.geometry.computeBoundingBox();
        o.geometry.computeBoundingSphere();
      });
    }

    root.traverse((o) => {
      if (!o.isMesh) return;
      o.castShadow = false;
      o.receiveShadow = false;
      const mats = Array.isArray(o.material) ? o.material : (o.material ? [o.material] : []);
      mats.forEach((m) => {
        if (m.map) m.map.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
        if (typeof m.roughness === 'number') {
          m.roughness = THREE.MathUtils.clamp(m.roughness, 0.42, 0.94);
        }
        if (typeof m.metalness === 'number') m.metalness = Math.min(m.metalness, 0.08);
        if (typeof m.ior === 'number') m.ior = THREE.MathUtils.clamp(m.ior, 1.0, 1.8);
        if (typeof m.specularIntensity === 'number') m.specularIntensity = Math.min(m.specularIntensity, 0.7);
        if ('envMapIntensity' in m) m.envMapIntensity = 0.6;
        m.dithering = true;
        m.needsUpdate = true;
      });
    });

    const group = new THREE.Group();
    group.add(root);
    group.updateMatrixWorld(true);

    const box = new THREE.Box3().setFromObject(group);
    if (box.isEmpty()) throw new Error('模型没有可显示的几何体');
    const center = box.getCenter(new THREE.Vector3());
    const rawSize = box.getSize(new THREE.Vector3());
    root.position.sub(center);
    group.updateMatrixWorld(true);

    const norm = 2 / Math.max(rawSize.x, rawSize.y, rawSize.z, 1e-6);
    group.scale.setScalar(norm);
    group.rotation.set(relic.pitch || 0, relic.yaw || 0, 0);
    group.userData.baseYaw = relic.yaw || 0;
    group.updateMatrixWorld(true);

    const fitted = new THREE.Box3().setFromObject(group);
    const size = fitted.getSize(new THREE.Vector3());
    const sphere = fitted.getBoundingSphere(new THREE.Sphere());
    const maxSpan = Math.max(size.x, size.y, size.z);
    shadow.visible = true;
    shadow.position.set(
      fitted.min.x + size.x / 2,
      fitted.min.y + 0.006,
      fitted.min.z + size.z / 2
    );
    const spread = Math.max(size.x, size.z, maxSpan * 0.55, 0.7) * 1.45;
    shadow.scale.set(spread, spread * 0.8, 1);

    holder = group;
    scene.add(holder);

    const vFov = THREE.MathUtils.degToRad(camera.fov);
    const hFov = 2 * Math.atan(Math.tan(vFov / 2) * camera.aspect);
    const dist = (sphere.radius / Math.sin(Math.min(vFov, hFov) / 2)) * (relic.zoom || 1.08);
    const elev = relic.elevation || 0.14;
    camera.position.set(0, dist * Math.sin(elev), dist * Math.cos(elev));
    controls.target.copy(sphere.center);
    controls.minDistance = dist * 0.62;
    controls.maxDistance = dist * 2.1;
    controls.update();
    controls.saveState();
  }

  function loadRelic(i) {
    const relic = RELICS[i];
    if (!relic) return;
    index = i;
    updateFooter(relic, i);
    const token = ++loadToken;
    loading = true;
    pauseAuto();
    clearCurrent();
    shadow.visible = false;
    setLoading(true, '正在调取文物…');

    loader.load(
      relic.file,
      async (gltf) => {
        if (token !== loadToken) {
          disposeObject(gltf.scene);
          return;
        }
        loading = false;
        setLoadText('正在布置展台…');
        await new Promise((r) => setTimeout(r, 0));
        if (token !== loadToken) {
          disposeObject(gltf.scene);
          return;
        }
        if (!contextAlive || disposed) {
          disposeObject(gltf.scene);
          return;
        }
        try {
          await buildRoot(gltf, relic);
        } catch (err) {
          console.warn('[relic] build failed', err);
          disposeObject(gltf.scene);
          showFatal('这件文物暂时无法展示');
          return;
        }
        if (token !== loadToken) {
          clearCurrent();
          return;
        }
        setLoading(false);
        showHint('拖动旋转 · 双指缩放');
        resumeAuto(1100);
      },
      (ev) => {
        if (token !== loadToken) return;
        if (ev && ev.lengthComputable && ev.total > 0) {
          const pct = Math.min(99, Math.round((ev.loaded / ev.total) * 100));
          setLoadText(`正在调取文物 ${pct}%`);
        }
      },
      (err) => {
        if (token !== loadToken) return;
        console.warn('[relic] load failed', err);
        loading = false;
        showFatal('文物加载失败，请检查网络或重试');
      }
    );
  }

  function resize() {
    const rect = stage.getBoundingClientRect();
    const w = Math.max(1, Math.round(rect.width));
    const h = Math.max(1, Math.round(rect.height));
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    renderer.setSize(w, h);
  }
  resize();
  if (window.ResizeObserver) new ResizeObserver(resize).observe(stage);
  else window.addEventListener('resize', resize);

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      pauseAuto();
      hideHint();
    } else {
      resize();
      resumeAuto(1000);
    }
  });

  function shutdown() {
    if (disposed) return;
    disposed = true;
    loadToken++;
    clearTimeout(resumeTimer);
    clearTimeout(hintTimer);
    clearCurrent();
    controls.dispose();
    shadow.geometry.dispose();
    shadow.material.map.dispose();
    shadow.material.dispose();
    environment.dispose();
    renderer.dispose();
    if (renderer.domElement.parentNode) renderer.domElement.parentNode.removeChild(renderer.domElement);
  }
  window.addEventListener('pagehide', shutdown);

  renderer.domElement.addEventListener('webglcontextlost', (e) => {
    e.preventDefault();
    contextAlive = false;
    pauseAuto();
    showFatal('3D 视图已暂停，点“重试”恢复');
  });
  renderer.domElement.addEventListener('webglcontextrestored', () => {
    contextAlive = true;
    loadRelic(index);
  });

  const clock = new THREE.Clock();
  function tick() {
    if (disposed) return;
    requestAnimationFrame(tick);
    if (document.hidden) return;
    const dt = Math.min(clock.getDelta(), 0.1);
    controls.update(dt);
    renderer.render(scene, camera);
  }

  viewer = {
    load: loadRelic,
    reset() {
      controls.reset();
      pauseAuto();
      resumeAuto(3000);
      flashHint('已复位视角');
    },
    retry() {
      if (!loading) loadRelic(index);
    }
  };

  window.__relicSpin = (deg) => {
    if (!holder) return false;
    pauseAuto();
    controls.autoRotate = false;
    holder.rotation.y = (holder.userData.baseYaw || 0) + THREE.MathUtils.degToRad(Number(deg) || 0);
    holder.updateMatrixWorld(true);
    return true;
  };
  window.__relicReady = () => !!holder && !loading;

  updateFooter(RELICS[index], index);
  loadRelic(index);
  tick();
}

function step(delta) {
  if (!viewer || loading) return;
  viewer.load((index + delta + RELICS.length) % RELICS.length);
}

function bindTap(el, fn) {
  let last = 0;
  const run = (e) => {
    const now = Date.now();
    if (now - last < 350) return;
    last = now;
    if (e && e.cancelable) e.preventDefault();
    fn();
  };
  el.addEventListener('touchend', run, { passive: false });
  el.addEventListener('click', run);
}

bindTap(ui.prev, () => step(-1));
bindTap(ui.next, () => step(1));
bindTap(ui.reset, () => {
  if (viewer) viewer.reset();
});
bindTap(ui.retry, () => {
  if (viewer) viewer.retry();
});
bindTap(ui.back, () => {
  if (window.Native && typeof window.Native.back === 'function') window.Native.back();
  else history.back();
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'ArrowLeft') step(-1);
  else if (e.key === 'ArrowRight') step(1);
});

window.openRelic = (i) => {
  const n = Number(i);
  if (Number.isFinite(n) && n >= 0 && n < RELICS.length && n !== index) viewer && viewer.load(n);
};

updateFooter(RELICS[index], index);
boot3D();
