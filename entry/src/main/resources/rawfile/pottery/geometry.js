
export const VIEW = {
  w: 512,
  h: 640,
  vTop: 0.12,
  vBot: 0.76,
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

export function pxToUnit(THREE, view) {
  return 2 * Math.tan(THREE.MathUtils.degToRad(view.fov / 2)) * view.camZ / view.h;
}

function toWorld(THREE, view, t, halfRatio) {
  const u = pxToUnit(THREE, view);
  const yPx = view.h * (view.vTop + t * (view.vBot - view.vTop));
  return new THREE.Vector3(halfRatio * view.w * u, -(yPx - view.h / 2) * u, 0);
}

function smoothProfile(THREE, profile, samples) {
  const pts = profile.map(([t, hw]) => new THREE.Vector3(hw, t, 0));
  const curve = new THREE.CatmullRomCurve3(pts, false, 'catmullrom', 0.4);
  return curve.getPoints(samples || 56).map((p) => ({ t: p.y, hw: Math.max(p.x, 0.001) }));
}

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

export function bodyOf(THREE, shape, view) {
  const sm = smoothProfile(THREE, shape.profile, 72);
  const rimHw = sm[0].hw;

  const pts = [[0.0006, 0]];
  pts.push([rimHw, 0]);
  for (let i = 1; i < sm.length; i++) {
    pts.push([sm[i].hw, sm[i].t]);
  }
  const last = sm[sm.length - 1];
  pts.push([last.hw * 0.88, 1.004]);
  pts.push([0.0006, 1.004]);

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

export function attach(THREE, group, shape, body, view, material, trim) {
  const part = trim || material;
  const u = pxToUnit(THREE, view);
  const px = (v) => v * u;
  const yAt = (t) => -(view.h * (view.vTop + t * (view.vBot - view.vTop)) - view.h / 2) * u;
  const wallPx = (t) => bodyOf_half(shape, t) * view.w;

  if (shape.ears === 'pair') {
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

export function greyMaterial(THREE) {
  return new THREE.MeshStandardMaterial({
    color: 0xd9d3c7, roughness: 0.95, metalness: 0.0, side: THREE.DoubleSide
  });
}

export function glazeMaterial(THREE, map) {
  return new THREE.MeshStandardMaterial({
    color: 0xffffff, roughness: 0.95, metalness: 0.0, map, side: THREE.DoubleSide
  });
}

export function lights(THREE, scene, k) {
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
