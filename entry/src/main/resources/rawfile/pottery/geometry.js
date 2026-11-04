/*
 * 彩陶器型几何定义（唯一数据源）
 *
 * 这份文件同时被两处使用：
 *   1) rawfile/pottery/pottery.js —— ArkWeb 里的实时 3D 主路径（真 WebGL 环境）
 *   2) tools/bake_pottery_frames.mjs —— 本地 headless Chrome 烘 24 帧灰模转台序列
 * 所以「无 WebGL 降级看到的器型」和「真机 3D 看到的器型」是同一套网格，不是两套近似。
 *
 * 轮廓数据镜像自 ets/view/PotteryCanvas.ets 的 profileOf() / bandOf()：
 * 二维版怎么画，三维版就怎么转，改一处要改两处（改完跑 tools/bake_pottery_frames.mjs --check）。
 * profile 每一项是 [t, 半宽占比]：t=0 是口沿、t=1 是器底，半宽按画布宽度 w 归一。
 */

export const VIEW = {
  w: 512,
  h: 640,
  vTop: 0.12,   // 口沿在画布高度的位置，与 PotteryCanvas 的 V_TOP 一致
  vBot: 0.76,   // 器底位置，与 V_BOT 一致
  // 长焦小视场：fov 与 camZ 是一对，改一个必须按 u=2·tan(fov/2)·camZ/h 反算另一个，
  // 否则像素↔世界的换算 u 会漂移，topPx/band 这些映射值就对不上二维版了。
  // 为什么不用 32° 广角（实测值）：广角下口沿那片封顶的「近边」会被放大 10~27%，
  // 投影到画布上就是器口向上鼓起几十像素（盆最严重，鼓到 y=11），
  // 看着像给罐子扣了个盘子底，而且 App 端按 topPx 画的口沿椭圆会整个错位。
  // 收到 8.123°/camZ=25 后近远边放大差只有 5%，器口基本回到一条线上——
  // 这正是二维版 PotteryCanvas 的画法（口沿椭圆靠矢量画，不靠透视）。
  fov: 8.123,
  camZ: 25
};

export const SHAPES = [
  {
    key: 'guan', label: '罐',
    profile: [[0, 0.20], [0.05, 0.26], [0.16, 0.37], [0.32, 0.45], [0.48, 0.46],
      [0.64, 0.42], [0.82, 0.30], [0.94, 0.21], [1, 0.19]],
    band: [0.32, 0.60], ears: 'pair', earT: [0.02, 0.14], feet: 0
  },
  {
    key: 'pen', label: '盆',
    profile: [[0, 0.46], [0.06, 0.45], [0.20, 0.42], [0.38, 0.36],
      [0.56, 0.29], [0.74, 0.20], [0.90, 0.12], [1, 0.09]],
    band: [0.32, 0.60], ears: null, earT: null, feet: 0
  },
  {
    key: 'hu', label: '壶',
    profile: [[0, 0.15], [0.04, 0.18], [0.12, 0.13], [0.24, 0.12], [0.36, 0.20],
      [0.48, 0.33], [0.60, 0.38], [0.74, 0.34], [0.86, 0.25], [0.94, 0.17], [1, 0.19]],
    band: [0.42, 0.70], ears: 'pair', earT: [0.02, 0.13], feet: 0
  },
  {
    key: 'ping', label: '瓶',
    profile: [[0, 0.11], [0.04, 0.14], [0.16, 0.10], [0.34, 0.12], [0.46, 0.25],
      [0.58, 0.31], [0.84, 0.31], [0.95, 0.28], [1, 0.27]],
    band: [0.48, 0.76], ears: null, earT: null, feet: 0
  },
  {
    key: 'ding', label: '鼎式',
    profile: [[0, 0.30], [0.05, 0.33], [0.14, 0.34], [0.32, 0.32],
      [0.50, 0.26], [0.68, 0.18], [0.86, 0.13], [1, 0.12]],
    band: [0.16, 0.44], ears: 'rim', earT: [0.0, 0.06], feet: 3
  }
];

export function shapeOf(key) {
  return SHAPES.find((s) => s.key === key) || SHAPES[0];
}

// 1 屏幕像素等于多少世界单位：相机在原点看向 +z，画布高 H 对应视锥在 camZ 处的高度
export function pxToUnit(THREE, view) {
  return 2 * Math.tan(THREE.MathUtils.degToRad(view.fov / 2)) * view.camZ / view.h;
}

// 归一化轮廓点 -> 世界坐标（画布 y 向下、three y 向上，这里统一翻转）
function toWorld(THREE, view, t, halfRatio) {
  const u = pxToUnit(THREE, view);
  const yPx = view.h * (view.vTop + t * (view.vBot - view.vTop));
  return new THREE.Vector3(halfRatio * view.w * u, -(yPx - view.h / 2) * u, 0);
}

// 折线轮廓 -> CatmullRom 平滑，避免转出来一圈硬折面（灰模上一眼就是棱）
function smoothProfile(THREE, profile, samples) {
  const pts = profile.map(([t, hw]) => new THREE.Vector3(hw, t, 0));
  const curve = new THREE.CatmullRomCurve3(pts, false, 'catmullrom', 0.4);
  return curve.getPoints(samples || 56).map((p) => ({ t: p.y, hw: Math.max(p.x, 0.001) }));
}

/*
 * 把 LatheGeometry 默认的 v = j/(点数-1) 换成「帧像素」口径：
 *   v = 1 - (topPx + t·(botPx - topPx)) / h
 * （three 的 v 从图的下边往上数，画布 y 从上往下数，所以有个 1-；
 *   t 是轮廓参数，0=口沿、1.004=器底，和 bodyOf 里那条折线一一对应）
 * u 不动，仍是 i/segments（φ=2πu，u=0 正对 +z 的镜头）。
 *
 * 为什么要换：App 端罩层和二维版的纹样带位置全按 y = topPx + t·(botPx-topPx) 算，
 * 默认 v 是「第几个点 / 总点数」，点在 t 上不均匀（口心、唇口、底足、器底是额外塞进去的），
 * 直接用默认 v 贴出来的纹样带会整体偏下几像素，鼎式这种点疏密悬殊的能偏出一个纹样高。
 * 换成像素口径后，真 3D 贴的这张展开图和降级转台罩的那张是同一张，不用各调各的。
 */
export function retexLathe(geometry, ts, view, topPx, botPx) {
  const uv = geometry.attributes.uv;
  const n = ts.length;
  for (let idx = 0; idx < uv.count; idx++) {
    const j = Math.min(n - 1, Math.max(0, Math.round(uv.getY(idx) * (n - 1))));
    uv.setY(idx, 1 - (topPx + (botPx - topPx) * ts[j]) / view.h);
  }
  uv.needsUpdate = true;
  return geometry;
}

/*
 * 器身：LatheGeometry 旋转体。轮廓是一条不自交的折线：
 *   口心 → 唇口 → 外壁 → 底足 → 器底心
 * 口做成平的封顶，不做内腔——相机与器口齐平，内腔在帧里只会糊成一坨「帽子」，
 * 而口沿那圈深色椭圆本来就由 App 端（和二维版 PotteryCanvas）按矢量现画，
 * 换釉色时口沿颜色要跟着变，烘进帧里就锁死了。
 */
export function bodyOf(THREE, shape, view) {
  const sm = smoothProfile(THREE, shape.profile, 72);
  const rimHw = sm[0].hw;

  const pts = [[0.0006, 0]];              // 口心（封顶）
  pts.push([rimHw, 0]);                   // 唇口
  for (let i = 1; i < sm.length; i++) {    // 外壁
    pts.push([sm[i].hw, sm[i].t]);
  }
  const last = sm[sm.length - 1];
  pts.push([last.hw * 0.88, 1.004]);      // 底足内收
  pts.push([0.0006, 1.004]);              // 器底中心

  const vec = pts.map(([hw, t]) => {
    const w = toWorld(THREE, view, t, hw);
    return new THREE.Vector2(w.x, w.y);
  });
  const geometry = new THREE.LatheGeometry(vec, 128);
  geometry.computeVertexNormals();

  const half = (t) => {
    const i = Math.max(0, Math.min(sm.length - 1, Math.round(t * (sm.length - 1))));
    return sm[i].hw * view.w;
  };
  const topPx = view.h * view.vTop;
  const botPx = view.h * (view.vTop + (view.vBot - view.vTop) * 1.004);
  retexLathe(geometry, pts.map(([, t]) => t), view, topPx, botPx);
  return {
    geometry,
    samples: sm,
    topPx,
    botPx,
    maxHalfPx: Math.max(...sm.map((p) => p.hw * view.w)),
    rimHalfPx: rimHw * view.w,
    baseHalfPx: half(1)
  };
}

/*
 * 附件：罐/壶的颈侧双耳（TubeGeometry 沿弧线）、鼎式的立耳与三足。
 * 盆、瓶没有附件，是纯旋转体——它们各帧只差在刻面与灯光的相对角度上，
 * 轮廓完全一致，转动反馈由 App 端叠加的纹样带提供。
 */
export function attach(THREE, group, shape, body, view, material, trim) {
  // 耳和足是贴在器身上的小件：真 3D 的器身用展开图做贴图，但 Tube/Torus/Cylinder
  // 自己的 UV 跟器身那套像素口径完全不搭，直接共用贴图会把纹样拉成一条面条。
  // 所以附件一律走 trim（纯色釉料），不传就跟器身一致（灰模烘焙时是同一个材质）。
  const part = trim || material;
  const u = pxToUnit(THREE, view);
  const px = (v) => v * u;
  const yAt = (t) => -(view.h * (view.vTop + t * (view.vBot - view.vTop)) - view.h / 2) * u;
  // 器壁半宽（像素）：t 处轮廓占比 × 画布宽
  const wallPx = (t) => bodyOf_half(shape, t) * view.w;

  if (shape.ears === 'pair') {
    // 颈侧双耳：鋬在颈部（器壁还窄的地方）向外鼓出一圈，转 90° 时从正面看是个环，
    // 转 0° 时在两侧。放在腹部最宽处会直接出画，所以 earT 取的是口沿下方一小段。
    // 控制点的纵向偏移一律取负（往下）：earT 上端离口沿只有几个像素，
    // 一旦让弧线往上走，转到 90° 时耳就会从器口上方顶出来，看着像罐子长了烟囱。
    const [t0, t1] = shape.earT;
    const r0 = wallPx(t0);
    const r1 = wallPx(t1);
    const rr = Math.max(r0, r1);
    const out = px(rr * 0.30);
    const tube = Math.max(px(rr * 0.055), 0.008);
    for (const side of [-1, 1]) {
      const base0 = new THREE.Vector3(side * px(r0 * 0.94), yAt(t0), 0);
      const base1 = new THREE.Vector3(side * px(r1 * 0.96), yAt(t1), 0);
      const mid = base0.clone().lerp(base1, 0.5);
      const curve = new THREE.CatmullRomCurve3([
        base0,
        mid.clone().add(new THREE.Vector3(side * out * 0.95, -out * 0.10, 0)),
        mid.clone().add(new THREE.Vector3(side * out * 1.05, -out * 0.45, 0)),
        base1
      ]);
      const g = new THREE.TubeGeometry(curve, 28, tube, 12, false);
      const m = new THREE.Mesh(g, part);
      m.userData.part = 'ear';
      group.add(m);
    }
  }

  if (shape.ears === 'rim') {
    // 鼎式立耳：口沿上方两只竖着的半环耳，尺寸照二维版 PotteryCanvas 的
    // c.arc(w/2 ± rx*0.86, top, rx*0.24, π, 2π)——半环半径 0.18rx + 管径 0.06rx = 0.24rx。
    // TorusGeometry 的 arc=π 默认就在 XY 平面上从 +x 扫到 -x（上半个环），
    // 所以直接摆在器口那条线上、不旋转，得到的就是「立在口沿上的半环」。
    // 长焦下转到镜头这一侧只放大 5%，不会再顶出画布上沿。
    const rx = body.rimHalfPx;
    for (const side of [-1, 1]) {
      const g = new THREE.TorusGeometry(px(rx * 0.18), px(rx * 0.06), 12, 28, Math.PI);
      const m = new THREE.Mesh(g, part);
      m.position.set(side * px(rx * 0.86), yAt(0), 0);
      m.userData.part = 'ear';
      group.add(m);
    }
  }

  if (shape.feet === 3) {
    const botY = yAt(1);
    const r = px(body.baseHalfPx * 1.05);
    const len = (view.vBot - view.vTop) * view.h * 0.20 * u;
    for (let i = 0; i < 3; i++) {
      const ang = (i / 3) * Math.PI * 2;
      const g = new THREE.CylinderGeometry(px(body.maxHalfPx * 0.052),
        px(body.maxHalfPx * 0.085), len, 16);
      const m = new THREE.Mesh(g, part);
      m.position.set(Math.sin(ang) * r, botY - len / 2, Math.cos(ang) * r);
      m.rotation.x = Math.cos(ang) * 0.10;
      m.rotation.z = -Math.sin(ang) * 0.10;
      m.userData.part = 'foot';
      group.add(m);
    }
  }
}

// 按 t 插值器壁半宽（与 PotteryCanvas.halfWidthAt 同口径）
function bodyOf_half(shape, t) {
  const sm = shape.profile;
  let lo = sm[0];
  let hi = sm[sm.length - 1];
  for (let i = 0; i < sm.length - 1; i++) {
    if (t >= sm[i][0] && t <= sm[i + 1][0]) {
      lo = sm[i];
      hi = sm[i + 1];
      break;
    }
  }
  const span = hi[0] - lo[0];
  const f = span <= 0 ? 0 : (t - lo[0]) / span;
  return lo[1] + (hi[1] - lo[1]) * f;
}

export { bodyOf_half };

/*
 * 灰模材质：无 WebGL 降级用的序列帧必须是接近白的中性灰，
 * 釉色由 App 端 source-atop 罩染上去，烘进帧里就没法换色了。
 */
export function greyMaterial(THREE) {
  // 封顶的口是双面画：不然从略高的角度看进去会直接看穿器身
  return new THREE.MeshStandardMaterial({
    color: 0xd9d3c7, roughness: 0.95, metalness: 0.0, side: THREE.DoubleSide
  });
}

/*
 * 真 3D 主路径的釉色材质：颜色一律来自那张展开贴图（pottery.js 用 art.js 画的），
 * 所以 color 必须是纯白——再乘一遍釉色等于把仰韶红罩成酱色。
 * 哑光（roughness 0.95 / metalness 0）和灰模一致：彩陶是低温陶衣，不是瓷器那种高光。
 */
export function glazeMaterial(THREE, map) {
  return new THREE.MeshStandardMaterial({
    color: 0xffffff, roughness: 0.95, metalness: 0.0, map, side: THREE.DoubleSide
  });
}

export function lights(THREE, scene, k) {
  // k 是给真 3D 页留的亮度系数：灰模帧的底色接近白，灯光按它调过；
  // 换成带釉色的贴图后同样的光会把红陶照成粉陶，所以贴图那条链路要压一档。
  const s = k === undefined ? 1 : k;
  scene.add(new THREE.HemisphereLight(0xffffff, 0xb9b1a2, 0.62 * s));
  const key = new THREE.DirectionalLight(0xffffff, 1.9 * s);
  key.position.set(2.8, 3.4, 4.2);
  scene.add(key);
  const rim = new THREE.DirectionalLight(0xffffff, 0.55 * s);
  rim.position.set(-3.2, 1.0, -2.4);
  scene.add(rim);
  const fill = new THREE.DirectionalLight(0xffffff, 0.25 * s);
  fill.position.set(0, -2.6, 2.4);
  scene.add(fill);
}

/*
 * 组装一件器物：返回 Group，userData 里带 ArkTS 侧叠加纹样/釉色需要的像素级元数据。
 */
export function buildVessel(THREE, key, view, material, trim) {
  const shape = shapeOf(key);
  const v = view || VIEW;
  const body = bodyOf(THREE, shape, v);
  const group = new THREE.Group();
  const mesh = new THREE.Mesh(body.geometry, material);
  mesh.userData.part = 'body';
  group.add(mesh);
  attach(THREE, group, shape, body, v, material, trim);
  group.userData = {
    shapeKey: shape.key,
    label: shape.label,
    topPx: body.topPx,
    botPx: body.botPx,
    maxHalfPx: body.maxHalfPx,
    rimHalfPx: body.rimHalfPx,
    baseHalfPx: body.baseHalfPx,
    band: shape.band.slice(),
    symmetric: !shape.ears && !shape.feet
  };
  return group;
}
