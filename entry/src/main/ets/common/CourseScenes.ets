import { Palette } from './Theme';
import { profileOf, grid, mixHex } from './PotteryArt';

export interface ShotBox {
  c: CanvasRenderer;
  p: Palette;
  w: number;
  h: number;
  ph: number;
  t: number;
}

const MOUND: number[][] = [[0, 0.10], [0.06, 0.16], [0.20, 0.24], [0.38, 0.30],
  [0.56, 0.34], [0.74, 0.37], [0.90, 0.39], [1, 0.40]];

const STAGE_TOP: number = 0.23;

function clamp01(x: number): number {
  return x < 0 ? 0 : (x > 1 ? 1 : x);
}

function seg(ph: number, a: number, b: number): number {
  if (b <= a) {
    return ph >= b ? 1 : 0;
  }
  return clamp01((ph - a) / (b - a));
}

function ease(x: number): number {
  let k = clamp01(x);
  return k * k * (3 - 2 * k);
}

function smoothClosed(c: CanvasRenderer, pts: number[]): void {
  let n = pts.length / 2;
  c.beginPath();
  if (n < 3) {
    return;
  }
  c.moveTo((pts[(n - 1) * 2] + pts[0]) / 2, (pts[(n - 1) * 2 + 1] + pts[1]) / 2);
  for (let i = 0; i < n; i++) {
    let x = pts[i * 2];
    let y = pts[i * 2 + 1];
    let j = (i + 1) % n;
    c.quadraticCurveTo(x, y, (x + pts[j * 2]) / 2, (y + pts[j * 2 + 1]) / 2);
  }
  c.closePath();
}

function roundBar(c: CanvasRenderer, x: number, y: number, w: number, h: number,
  r: number): void {
  let rr = r;
  if (rr > w / 2) {
    rr = w / 2;
  }
  if (rr > h / 2) {
    rr = h / 2;
  }
  c.beginPath();
  c.moveTo(x + rr, y);
  c.lineTo(x + w - rr, y);
  c.quadraticCurveTo(x + w, y, x + w, y + rr);
  c.lineTo(x + w, y + h - rr);
  c.quadraticCurveTo(x + w, y + h, x + w - rr, y + h);
  c.lineTo(x + rr, y + h);
  c.quadraticCurveTo(x, y + h, x, y + h - rr);
  c.lineTo(x, y + rr);
  c.quadraticCurveTo(x, y, x + rr, y);
  c.closePath();
}

function vesselPts(prof: number[][], morph: number, cx: number, top: number,
  bot: number, vw: number): number[] {
  let pts: number[] = [];
  for (let i = 0; i < prof.length; i++) {
    pts.push(cx + halfWidth(prof, i, morph, vw));
    pts.push(top + (bot - top) * prof[i][0]);
  }
  for (let i = prof.length - 1; i >= 0; i--) {
    pts.push(cx - halfWidth(prof, i, morph, vw));
    pts.push(top + (bot - top) * prof[i][0]);
  }
  return pts;
}

function halfWidth(prof: number[][], i: number, morph: number, vw: number): number {
  if (morph >= 0.999) {
    return prof[i][1] * vw;
  }
  let mi = i < MOUND.length ? i : MOUND.length - 1;
  return (prof[i][1] * morph + MOUND[mi][1] * (1 - morph)) * vw;
}

function drawVessel(b: ShotBox, prof: number[][], morph: number, cx: number, top: number,
  bot: number, vw: number, body: string, rim: boolean): number[] {
  let c = b.c;
  let pts = vesselPts(prof, morph, cx, top, bot, vw);
  let maxr = 0;
  for (let i = 0; i < prof.length; i++) {
    let hw = halfWidth(prof, i, morph, vw);
    if (hw > maxr) {
      maxr = hw;
    }
  }
  let g: CanvasGradient = c.createLinearGradient(cx - maxr, 0, cx + maxr, 0);
  g.addColorStop(0, mixHex(body, b.p.deep, 0.34));
  g.addColorStop(0.30, mixHex(body, b.p.paper, 0.12));
  g.addColorStop(0.62, body);
  g.addColorStop(1, mixHex(body, b.p.deep, 0.30));
  smoothClosed(c, pts);
  c.fillStyle = g;
  c.fill();
  c.strokeStyle = b.p.deep;
  c.lineWidth = Math.max(b.w * 0.008, 1.4);
  c.stroke();
  if (rim) {
    let rx = halfWidth(prof, 0, morph, vw);
    c.fillStyle = b.p.deep;
    c.beginPath();
    c.ellipse(cx, top, rx, Math.max(rx * 0.16, 2), 0, 0, Math.PI * 2);
    c.fill();
    c.fillStyle = mixHex(body, b.p.deep, 0.48);
    c.beginPath();
    c.ellipse(cx, top, rx * 0.86, Math.max(rx * 0.13, 1.6), 0, 0, Math.PI * 2);
    c.fill();
    c.strokeStyle = 'rgba(255,252,244,0.42)';
    c.lineWidth = Math.max(b.h * 0.004, 1);
    c.beginPath();
    c.ellipse(cx, top, rx * 0.93, Math.max(rx * 0.145, 1.8), 0, Math.PI * 1.05, Math.PI * 1.95);
    c.stroke();
  }
  return pts;
}

function strokePartial(c: CanvasRenderer, pts: number[], frac: number): number[] {
  let n = pts.length / 2;
  let total = 0;
  for (let i = 0; i < n - 1; i++) {
    let dx = pts[(i + 1) * 2] - pts[i * 2];
    let dy = pts[(i + 1) * 2 + 1] - pts[i * 2 + 1];
    total += Math.sqrt(dx * dx + dy * dy);
  }
  let want = total * clamp01(frac);
  let ex = pts[0];
  let ey = pts[1];
  c.beginPath();
  c.moveTo(ex, ey);
  let acc = 0;
  for (let i = 0; i < n - 1; i++) {
    let dx = pts[(i + 1) * 2] - pts[i * 2];
    let dy = pts[(i + 1) * 2 + 1] - pts[i * 2 + 1];
    let l = Math.sqrt(dx * dx + dy * dy);
    if (acc + l <= want) {
      c.lineTo(pts[(i + 1) * 2], pts[(i + 1) * 2 + 1]);
      ex = pts[(i + 1) * 2];
      ey = pts[(i + 1) * 2 + 1];
      acc += l;
    } else {
      let k = l <= 0 ? 0 : (want - acc) / l;
      ex = pts[i * 2] + dx * k;
      ey = pts[i * 2 + 1] + dy * k;
      c.lineTo(ex, ey);
      break;
    }
  }
  c.stroke();
  return [ex, ey];
}

function tool(b: ShotBox, tip: number[], col: string, thick: number): void {
  let c = b.c;
  let hx = tip[0] + b.w * 0.13;
  let hy = tip[1] - b.h * 0.22;
  let nx = tip[0] + (hx - tip[0]) * 0.24;
  let ny = tip[1] + (hy - tip[1]) * 0.24;
  c.lineCap = 'round';
  c.strokeStyle = '#6B4E39';
  c.lineWidth = Math.max(thick * 0.85, 1.2);
  c.beginPath();
  c.moveTo(hx, hy);
  c.lineTo(nx, ny);
  c.stroke();
  c.strokeStyle = col;
  c.lineWidth = Math.max(thick * 0.55, 1);
  c.beginPath();
  c.moveTo(nx, ny);
  c.lineTo(tip[0], tip[1]);
  c.stroke();
  c.fillStyle = col;
  c.beginPath();
  c.arc(tip[0], tip[1], Math.max(thick * 0.62, 1.6), 0, Math.PI * 2);
  c.fill();
  c.lineCap = 'butt';
}

function hands(b: ShotBox, cx: number, y: number, spread: number, alpha: number): void {
  if (alpha <= 0.01) {
    return;
  }
  let c = b.c;
  let pw = Math.min(b.w * 0.056, b.h * 0.070);
  let ph = pw * 0.70;
  let skin = '#E7C7A3';
  let line = 'rgba(43,38,34,0.42)';
  let lw = Math.max(b.h * 0.005, 1.1);
  let up = y + b.h * 0.06;
  c.save();
  c.globalAlpha = c.globalAlpha * alpha;
  for (let s = -1; s <= 1; s += 2) {
    c.save();
    c.translate(cx + s * spread, y);
    c.rotate(s * 0.30);
    c.beginPath();
    c.moveTo(-pw * 0.78, -ph * 0.45);
    c.quadraticCurveTo(-pw * 0.92, -y * 0.5, -pw * 1.02, -up);
    c.lineTo(pw * 1.02, -up);
    c.quadraticCurveTo(pw * 0.92, -y * 0.5, pw * 0.78, -ph * 0.45);
    c.closePath();
    c.fillStyle = skin;
    c.fill();
    c.strokeStyle = line;
    c.lineWidth = lw;
    c.stroke();
    c.lineCap = 'round';
    for (let k = 0; k < 4; k++) {
      let fx = (k - 1.5) * pw * 0.40;
      for (let p = 0; p < 2; p++) {
        c.strokeStyle = p === 0 ? line : skin;
        c.lineWidth = p === 0 ? pw * 0.30 + lw * 2 : pw * 0.30;
        c.beginPath();
        c.moveTo(fx, ph * 0.15);
        c.quadraticCurveTo(fx + s * pw * 0.06, ph * 0.95, fx + s * pw * 0.28, ph * 1.22);
        c.stroke();
      }
    }
    c.beginPath();
    c.ellipse(0, 0, pw, ph, 0, 0, Math.PI * 2);
    c.fillStyle = skin;
    c.fill();
    c.strokeStyle = line;
    c.lineWidth = lw;
    c.stroke();
    for (let p = 0; p < 2; p++) {
      c.strokeStyle = p === 0 ? line : skin;
      c.lineWidth = p === 0 ? pw * 0.36 + lw * 2 : pw * 0.36;
      c.beginPath();
      c.moveTo(-s * pw * 0.66, -ph * 0.12);
      c.quadraticCurveTo(-s * pw * 1.00, ph * 0.42, -s * pw * 0.56, ph * 0.82);
      c.stroke();
    }
    c.lineCap = 'butt';
    c.restore();
  }
  c.restore();
}

function table(b: ShotBox, y: number, cx: number, rx: number): void {
  let c = b.c;
  c.fillStyle = 'rgba(43,38,34,0.14)';
  c.beginPath();
  c.ellipse(cx, y + b.h * 0.012, rx, b.h * 0.024, 0, 0, Math.PI * 2);
  c.fill();
  c.strokeStyle = 'rgba(43,38,34,0.28)';
  c.lineWidth = Math.max(b.h * 0.005, 1);
  c.beginPath();
  c.moveTo(b.w * 0.07, y + b.h * 0.006 * Math.sin(b.t * 1.3));
  c.lineTo(b.w * 0.93, y - b.h * 0.006 * Math.sin(b.t * 1.3));
  c.stroke();
}

function halo(b: ShotBox, cx: number, cy: number, r: number): void {
  let c = b.c;
  let g: CanvasGradient = c.createRadialGradient(cx, cy, r * 0.10, cx, cy, r);
  g.addColorStop(0, 'rgba(255,252,244,0.80)');
  g.addColorStop(1, 'rgba(255,252,244,0)');
  c.fillStyle = g;
  c.beginPath();
  c.arc(cx, cy, r, 0, Math.PI * 2);
  c.fill();
}

function watermark(b: ShotBox, cx: number, cy: number, r: number, alpha: number): void {
  let c = b.c;
  let y = cy;
  if (y < b.h * 0.40) {
    y = b.h * 0.40;
  }
  c.save();
  c.globalAlpha = alpha * 0.6;
  c.strokeStyle = b.p.deep;
  c.lineWidth = Math.max(b.h * 0.012, 1.2);
  c.beginPath();
  let first = true;
  for (let a = 0; a <= Math.PI * 5.2; a += 0.16) {
    let rr = r * (1 - a / (Math.PI * 5.6));
    let px = cx + rr * Math.cos(a + b.t * 0.05);
    let py = y + rr * Math.sin(a + b.t * 0.05);
    if (first) {
      c.moveTo(px, py);
      first = false;
    } else {
      c.lineTo(px, py);
    }
  }
  c.stroke();
  c.restore();
}

function wisps(b: ShotBox, x0: number, x1: number, yBase: number, dist: number,
  n: number, speed: number, alpha: number, col: string): void {
  let c = b.c;
  c.strokeStyle = col;
  c.lineWidth = Math.max(b.h * 0.007, 1);
  for (let i = 0; i < n; i++) {
    let rise = (b.t * speed + i * 0.31) % 1;
    let yy = yBase - dist * rise;
    let spread = b.h * 0.028 * (1 + rise * 1.6);
    c.save();
    c.globalAlpha = alpha * (1 - rise);
    let mx = x0 + (x1 - x0) * ((i * 0.37 + 0.15) % 1);
    c.beginPath();
    c.moveTo(mx - b.w * 0.06, yy);
    c.quadraticCurveTo(mx - b.w * 0.03, yy - spread, mx, yy);
    c.quadraticCurveTo(mx + b.w * 0.03, yy + spread, mx + b.w * 0.06, yy);
    c.stroke();
    c.restore();
  }
}

function archPath(c: CanvasRenderer, cx: number, baseY: number, rw: number, rh: number): void {
  c.beginPath();
  c.moveTo(cx - rw, baseY);
  c.lineTo(cx - rw, baseY - rh * 0.55);
  c.quadraticCurveTo(cx, baseY - rh * 1.25, cx + rw, baseY - rh * 0.55);
  c.lineTo(cx + rw, baseY);
  c.closePath();
}

function kiln(b: ShotBox, k: number, cx: number, baseY: number, rw: number, rh: number): void {
  let c = b.c;
  if (k <= 0.01) {
    return;
  }
  c.save();
  c.globalAlpha = k;
  archPath(c, cx, baseY, rw, rh);
  c.fillStyle = 'rgba(96,84,72,0.32)';
  c.fill();
  c.strokeStyle = 'rgba(43,38,34,0.55)';
  c.lineWidth = Math.max(b.h * 0.007, 1.4);
  c.stroke();
  c.save();
  archPath(c, cx, baseY, rw, rh);
  c.clip();
  c.strokeStyle = 'rgba(43,38,34,0.20)';
  c.lineWidth = Math.max(b.h * 0.004, 1);
  for (let i = 1; i <= 3; i++) {
    let y = baseY - rh * 0.24 * i;
    c.beginPath();
    c.moveTo(cx - rw, y);
    c.quadraticCurveTo(cx, y - rh * 0.06, cx + rw, y);
    c.stroke();
  }
  c.restore();
  let mw = rw * 0.52;
  let mh = rh * 0.52;
  let pulse = (Math.sin(b.t * 3.2) + 1) / 2;
  c.save();
  archPath(c, cx, baseY, mw, mh);
  c.clip();
  let g: CanvasGradient = c.createLinearGradient(0, baseY, 0, baseY - mh);
  g.addColorStop(0, mixHex('#B8542E', '#F6B24A', 0.35 + 0.45 * pulse * k));
  g.addColorStop(1, 'rgba(166,85,61,0)');
  c.fillStyle = g;
  c.fillRect(cx - mw, baseY - mh, mw * 2, mh);
  c.fillStyle = '#FBEBC4';
  for (let i = -1; i <= 1; i++) {
    let fx = cx + i * mw * 0.5;
    let fl = mh * (0.50 - Math.abs(i) * 0.12) + mh * 0.10 * Math.sin(b.t * 7.1 + i * 1.9);
    c.beginPath();
    c.moveTo(fx - mw * 0.13, baseY);
    c.quadraticCurveTo(fx, baseY - fl * 1.6, fx + mw * 0.13, baseY);
    c.closePath();
    c.fill();
  }
  c.restore();
  c.strokeStyle = 'rgba(43,38,34,0.60)';
  c.lineWidth = Math.max(b.h * 0.006, 1.2);
  archPath(c, cx, baseY, mw, mh);
  c.stroke();
  c.restore();
}

function fishPts(cx: number, cy: number, L: number, H: number): number[] {
  let pts: number[] = [];
  let n = 26;
  for (let i = 0; i <= n; i++) {
    let u = i / n;
    let x = cx - L * 0.5 + L * 0.86 * u;
    let y = cy - H * (0.5 * Math.sin(Math.PI * Math.pow(u, 0.72)));
    pts.push(x);
    pts.push(y);
  }
  let tx = cx - L * 0.5 + L * 0.86;
  pts.push(tx + L * 0.14);
  pts.push(cy - H * 0.42);
  pts.push(tx + L * 0.03);
  pts.push(cy);
  pts.push(tx + L * 0.14);
  pts.push(cy + H * 0.42);
  pts.push(tx);
  pts.push(cy + H * 0.02);
  for (let i = n; i >= 0; i--) {
    let u = i / n;
    let x = cx - L * 0.5 + L * 0.86 * u;
    let y = cy + H * (0.5 * Math.sin(Math.PI * Math.pow(u, 0.72)));
    pts.push(x);
    pts.push(y);
  }
  pts.push(cx - L * 0.5 + L * 0.02);
  pts.push(cy - H * 0.10);
  return pts;
}

function fishOne(b: ShotBox, fx: number, cy: number, L: number, H: number, fill: number,
  sc: number, dot: number, fin: number, ink: string, pale: string): void {
  let c = b.c;
  if (fill > 0.01) {
    c.save();
    smoothClosed(c, fishPts(fx, cy, L, H));
    c.clip();
    c.fillStyle = ink;
    c.fillRect(fx - L * 0.55, cy - H * 0.62, L * 1.1, H * 1.24 * fill);
    if (fill < 0.99) {
      c.fillStyle = 'rgba(255,252,244,0.20)';
      c.fillRect(fx - L * 0.55, cy - H * 0.62 + H * 1.24 * fill, L * 1.1,
        Math.max(H * 0.05, 1.6));
    }
    if (fill > 0.5) {
      c.strokeStyle = pale;
      c.lineWidth = Math.max(H * 0.06, 1);
      c.beginPath();
      c.moveTo(fx - L * 0.18, cy);
      c.lineTo(fx + L * 0.24, cy);
      c.stroke();
      let n = Math.floor(sc * 2.999);
      c.lineWidth = Math.max(H * 0.05, 1);
      for (let i = 0; i < n; i++) {
        let sx = fx - L * 0.04 + i * L * 0.14;
        c.beginPath();
        c.moveTo(sx - L * 0.05, cy - H * 0.15);
        c.lineTo(sx + L * 0.05, cy + H * 0.15);
        c.stroke();
      }
      if (dot > 0.01) {
        c.save();
        c.globalAlpha = c.globalAlpha * dot;
        c.fillStyle = pale;
        for (let i = 0; i < 2; i++) {
          c.beginPath();
          c.arc(fx + L * 0.30, cy + (i === 0 ? -1 : 1) * H * 0.24, Math.max(L * 0.024, 1.2), 0,
            Math.PI * 2);
          c.fill();
        }
        c.beginPath();
        c.arc(fx - L * 0.33, cy - H * 0.05, Math.max(L * 0.048, 1.5), 0, Math.PI * 2);
        c.fill();
        c.restore();
      }
    }
    c.restore();
  }
  if (fin > 0.01) {
    c.fillStyle = ink;
    for (let i = 0; i < 2; i++) {
      let s = i === 0 ? -1 : 1;
      c.save();
      c.translate(fx, cy);
      c.scale(fin, fin);
      c.beginPath();
      c.moveTo(-L * 0.10, s * H * 0.30);
      c.quadraticCurveTo(L * 0.06, s * H * 0.68, L * 0.22, s * H * 0.26);
      c.quadraticCurveTo(L * 0.04, s * H * 0.36, -L * 0.10, s * H * 0.30);
      c.closePath();
      c.fill();
      c.restore();
    }
  }
}

const FISH_N: number = 3;

function fishX(cx: number, vw: number, i: number): number {
  return cx + (i - 1) * vw * 0.30;
}

function c01s1(b: ShotBox): void {
  let c = b.c;
  let cx = b.w * 0.5;
  let ty = b.h * 0.80;
  let knead = seg(b.ph, 0, 0.50);
  let rise = ease(seg(b.ph, 0.52, 0.98));
  let sq = Math.sin(b.t * 4.4) * (1 - rise);
  let vw = b.w * (0.66 + 0.10 * ease(knead));
  let hh = b.h * (0.15 + 0.016 * sq + 0.40 * rise);
  table(b, ty, cx, vw * 0.42);
  halo(b, cx, ty - hh * 0.5, b.h * 0.46);
  let pts = drawVessel(b, profileOf('盆'), rise, cx, ty - hh, ty, vw, b.p.base, rise > 0.7);
  let press = (Math.sin(b.t * 4.4) + 1) / 2;
  hands(b, cx, ty - hh - b.h * (0.005 + 0.03 * press), vw * (0.12 + 0.20 * rise),
    1 - seg(b.ph, 0.86, 1));
  let seam = seg(b.ph, 0.80, 1);
  if (seam > 0.01 && seam < 0.99) {
    let k = Math.floor((1 - seam) * (pts.length / 2 - 1));
    c.fillStyle = 'rgba(255,252,244,0.90)';
    c.beginPath();
    c.arc(pts[k * 2], pts[k * 2 + 1], Math.max(b.w * 0.014, 2), 0, Math.PI * 2);
    c.fill();
  }
  watermark(b, b.w * 0.16, b.h * 0.22, b.h * 0.16, 0.10);
}

function c01s2(b: ShotBox): void {
  let c = b.c;
  let cx = b.w * 0.5;
  let ty = b.h * 0.80;
  let top = b.h * STAGE_TOP;
  let vw = b.w * 0.76;
  table(b, ty, cx, vw * 0.40);
  halo(b, cx, (top + ty) * 0.5, b.h * 0.50);
  let pts = drawVessel(b, profileOf('盆'), 1, cx, top, ty, vw, b.p.base, true);
  c.save();
  smoothClosed(c, pts);
  c.clip();
  let yA = top + (ty - top) * 0.34;
  let yB = top + (ty - top) * 0.62;
  let rx = vw * 0.46;
  c.strokeStyle = 'rgba(43,38,34,0.72)';
  c.lineWidth = Math.max(b.h * 0.008, 1.2);
  let f1 = ease(seg(b.ph, 0.04, 0.34));
  let f2 = ease(seg(b.ph, 0.28, 0.58));
  let t1 = strokePartial(c, [cx - rx, yA, cx - rx * 0.2, yA - b.h * 0.012, cx + rx, yA], f1);
  let t2 = strokePartial(c, [cx - rx, yB, cx - rx * 0.2, yB - b.h * 0.012, cx + rx, yB], f2);
  let f3 = seg(b.ph, 0.58, 0.78);
  if (f3 > 0.01) {
    c.save();
    c.globalAlpha = f3;
    c.strokeStyle = 'rgba(43,38,34,0.55)';
    c.setLineDash([b.h * 0.02, b.h * 0.018]);
    for (let i = 0; i < 2; i++) {
      let x = cx + (i === 0 ? -1 : 1) * rx * 0.66;
      c.beginPath();
      c.moveTo(x, yA + b.h * 0.02);
      c.lineTo(x, yB - b.h * 0.02);
      c.stroke();
    }
    c.setLineDash([]);
    c.restore();
  }
  let f4 = seg(b.ph, 0.76, 1);
  if (f4 > 0.01) {
    c.save();
    c.strokeStyle = b.p.accent;
    c.setLineDash([b.h * 0.016, b.h * 0.016]);
    c.lineWidth = Math.max(b.h * 0.006, 1);
    for (let i = 0; i < FISH_N; i++) {
      c.globalAlpha = 0.42 * clamp01((f4 - i * 0.22) / 0.34);
      if (c.globalAlpha <= 0.01) {
        continue;
      }
      smoothClosed(c, fishPts(fishX(cx, vw, i), (yA + yB) / 2, vw * 0.27, (yB - yA) * 0.60));
      c.stroke();
    }
    c.setLineDash([]);
    c.restore();
  }
  c.restore();
  let tp: number[] = [cx + rx * 0.9, yB];
  if (f1 < 1) {
    tp = t1;
  } else if (f2 < 1) {
    tp = t2;
  }
  tool(b, tp, 'rgba(43,38,34,0.85)', Math.max(b.h * 0.010, 1.4));
  watermark(b, b.w * 0.86, b.h * 0.20, b.h * 0.14, 0.09);
}

function c01s3(b: ShotBox): void {
  let c = b.c;
  let cx = b.w * 0.5;
  let ty = b.h * 0.80;
  let top = b.h * STAGE_TOP;
  let vw = b.w * 0.76;
  table(b, ty, cx, vw * 0.40);
  halo(b, cx, (top + ty) * 0.5, b.h * 0.50);
  let pts = drawVessel(b, profileOf('盆'), 1, cx, top, ty, vw, b.p.base, true);
  c.save();
  smoothClosed(c, pts);
  c.clip();
  let yA = top + (ty - top) * 0.34;
  let yB = top + (ty - top) * 0.62;
  c.strokeStyle = 'rgba(43,38,34,0.60)';
  c.lineWidth = Math.max(b.h * 0.007, 1.2);
  c.beginPath();
  c.moveTo(cx - vw * 0.46, yA);
  c.lineTo(cx + vw * 0.46, yA);
  c.moveTo(cx - vw * 0.46, yB);
  c.lineTo(cx + vw * 0.46, yB);
  c.stroke();
  let cy = (yA + yB) / 2;
  let fh = (yB - yA) * 0.60;
  let fl = vw * 0.27;
  let k = seg(b.ph, 0.05, 0.95);
  c.strokeStyle = b.p.accent;
  c.lineWidth = Math.max(b.h * 0.014, 2);
  let tip: number[] = [cx - vw * 0.42, cy];
  for (let i = 0; i < FISH_N; i++) {
    let frac = clamp01((k - i / FISH_N) * FISH_N);
    if (frac <= 0) {
      break;
    }
    tip = strokePartial(c, fishPts(fishX(cx, vw, i), cy, fl, fh), ease(frac));
  }
  c.restore();
  tool(b, tip, b.p.accent, Math.max(b.h * 0.012, 1.6));
  let dx = b.w * 0.15;
  let dy = b.h * 0.86;
  let dr = b.w * 0.078;
  c.fillStyle = 'rgba(43,38,34,0.16)';
  c.beginPath();
  c.ellipse(dx, dy + b.h * 0.016, dr * 1.04, b.h * 0.013, 0, 0, Math.PI * 2);
  c.fill();
  c.fillStyle = b.p.deep;
  c.beginPath();
  c.ellipse(dx, dy, dr, b.h * 0.024, 0, 0, Math.PI * 2);
  c.fill();
  c.fillStyle = b.p.accent;
  c.beginPath();
  c.ellipse(dx, dy - b.h * 0.004, dr * 0.74, b.h * 0.016, 0, 0, Math.PI * 2);
  c.fill();
  c.strokeStyle = 'rgba(255,252,244,0.34)';
  c.lineWidth = Math.max(b.h * 0.004, 1);
  c.beginPath();
  c.ellipse(dx, dy, dr, b.h * 0.024, 0, Math.PI * 1.05, Math.PI * 1.95);
  c.stroke();
  c.strokeStyle = 'rgba(255,252,244,0.42)';
  c.beginPath();
  c.ellipse(dx, dy - b.h * 0.005, dr * 0.50 * (0.86 + 0.14 * Math.sin(b.t * 1.6)),
    b.h * 0.010, 0, 0, Math.PI * 2);
  c.stroke();
  watermark(b, b.w * 0.88, b.h * 0.16, b.h * 0.13, 0.08);
}

function c01s4(b: ShotBox): void {
  let c = b.c;
  let cx = b.w * 0.5;
  let ty = b.h * 0.80;
  let top = b.h * STAGE_TOP;
  let vw = b.w * 0.76;
  table(b, ty, cx, vw * 0.40);
  halo(b, cx, (top + ty) * 0.5, b.h * 0.50);
  let pts = drawVessel(b, profileOf('盆'), 1, cx, top, ty, vw, b.p.base, true);
  let yA = top + (ty - top) * 0.34;
  let yB = top + (ty - top) * 0.62;
  let cy = (yA + yB) / 2;
  let fl = vw * 0.27;
  let fh = (yB - yA) * 0.60;
  c.save();
  smoothClosed(c, pts);
  c.clip();
  c.strokeStyle = 'rgba(43,38,34,0.60)';
  c.lineWidth = Math.max(b.h * 0.007, 1.2);
  c.beginPath();
  c.moveTo(cx - vw * 0.46, yA);
  c.lineTo(cx + vw * 0.46, yA);
  c.moveTo(cx - vw * 0.46, yB);
  c.lineTo(cx + vw * 0.46, yB);
  c.stroke();
  let k = seg(b.ph, 0.04, 0.96);
  let fr: number[] = [0, 0, 0];
  let cur = 0;
  for (let i = 0; i < FISH_N; i++) {
    fr[i] = clamp01((k - i / FISH_N) * FISH_N);
    if (fr[i] > 0.01) {
      fishOne(b, fishX(cx, vw, i), cy, fl, fh,
        ease(clamp01(fr[i] / 0.55)),
        clamp01((fr[i] - 0.45) / 0.30),
        clamp01((fr[i] - 0.72) / 0.20),
        ease(clamp01((fr[i] - 0.60) / 0.30)), b.p.accent, b.p.paper);
      cur = i;
    }
  }
  c.restore();
  let fx = fishX(cx, vw, cur);
  let af = fr[cur];
  let tp4: number[] = [fx + fl * 0.30, cy + fh * 0.34];
  if (af < 0.55) {
    tp4 = [fx, cy - fh * 0.62 + fh * 1.24 * ease(clamp01(af / 0.55))];
  } else if (af < 0.92) {
    tp4 = [fx + fl * (-0.02 + Math.floor(clamp01((af - 0.45) / 0.30) * 2.999) * 0.15), cy + fh * 0.16];
  }
  tool(b, tp4, b.p.accent, Math.max(b.h * 0.012, 1.6));
  watermark(b, b.w * 0.12, b.h * 0.18, b.h * 0.13, 0.08);
}

function c01s5(b: ShotBox): void {
  let c = b.c;
  let cx = b.w * 0.5;
  let ty = b.h * 0.80;
  let top = b.h * 0.22;
  let vw = b.w * 0.72;
  let load = ease(seg(b.ph, 0.16, 0.58));
  let sc = 1 - 0.12 * load;
  let top2 = ty - (ty - top) * sc;
  let vw2 = vw * sc;
  kiln(b, load, cx, ty + b.h * 0.02, b.w * 0.42, b.h * 0.44);
  table(b, ty, cx, vw2 * 0.40);
  halo(b, cx, (top2 + ty) * 0.5, b.h * 0.44);
  let body = mixHex(b.p.base, b.p.deep, 0.55 * ease(seg(b.ph, 0.34, 0.98)));
  let pts = drawVessel(b, profileOf('盆'), 1, cx, top2, ty, vw2, body, true);
  c.save();
  smoothClosed(c, pts);
  c.clip();
  let yA = top2 + (ty - top2) * 0.34;
  let yB = top2 + (ty - top2) * 0.62;
  let cy = (yA + yB) / 2;
  c.strokeStyle = 'rgba(43,38,34,0.55)';
  c.lineWidth = Math.max(b.h * 0.006, 1);
  c.beginPath();
  c.moveTo(cx - vw2 * 0.46, yA);
  c.lineTo(cx + vw2 * 0.46, yA);
  c.moveTo(cx - vw2 * 0.46, yB);
  c.lineTo(cx + vw2 * 0.46, yB);
  c.stroke();
  let heat = ease(seg(b.ph, 0.40, 0.98));
  let inkFish = mixHex(b.p.accent, b.p.deep, 0.22 * heat);
  let paleFish = mixHex(b.p.paper, body, 0.34 * heat);
  let fl2 = vw2 * 0.27;
  let fh2 = (yB - yA) * 0.60;
  for (let i = 0; i < FISH_N; i++) {
    fishOne(b, fishX(cx, vw2, i), cy, fl2, fh2, 1, 1, 1, 1, inkFish, paleFish);
  }
  c.restore();
  let dry = 1 - seg(b.ph, 0.40, 0.62);
  wisps(b, cx - vw2 * 0.3, cx + vw2 * 0.3, top2 + b.h * 0.02, b.h * 0.13, 3, 0.22,
    0.55 * dry, 'rgba(255,252,244,0.95)');
  if (load > 0.01) {
    c.save();
    c.globalAlpha = load;
    wisps(b, cx - b.w * 0.2, cx + b.w * 0.2, b.h * 0.28, b.h * 0.14, 3, 0.34, 0.55,
      'rgba(43,38,34,0.35)');
    c.restore();
  }
  watermark(b, b.w * 0.88, b.h * 0.14, b.h * 0.12, 0.07);
}

function c02s1(b: ShotBox): void {
  let c = b.c;
  let cx = b.w * 0.5;
  let ty = b.h * 0.80;
  table(b, ty, cx, b.w * 0.34);
  halo(b, cx, ty - b.h * 0.16, b.h * 0.42);
  let fold = seg(b.ph, 0, 0.48);
  let open = ease(seg(b.ph, 0.50, 0.86));
  let sq = Math.sin(b.t * 3.8) * (1 - open);
  let bw = b.w * (0.30 + 0.06 * ease(fold));
  let bh = b.h * (0.20 - 0.03 * ease(fold) + 0.014 * sq);
  if (open < 0.99) {
    c.save();
    c.globalAlpha = 1 - open;
    c.fillStyle = b.p.base;
    roundBar(c, cx - bw, ty - bh, bw * 2, bh, b.h * 0.03);
    c.fill();
    c.strokeStyle = b.p.deep;
    c.lineWidth = Math.max(b.h * 0.008, 1.2);
    c.stroke();
    let creases = 1 + Math.floor(fold * 3);
    for (let i = 0; i < creases; i++) {
      let y = ty - bh * (0.30 + i * 0.22);
      c.beginPath();
      c.moveTo(cx - bw * 0.8, y);
      c.quadraticCurveTo(cx, y - bh * 0.10, cx + bw * 0.8, y);
      c.stroke();
    }
    c.restore();
    hands(b, cx, ty - bh - b.h * 0.018, bw * 0.52, 1 - seg(b.ph, 0.40, 0.55));
  }
  if (open > 0.01) {
    let gap = bw * 0.16 * open;
    for (let s = 0; s < 2; s++) {
      let dir = s === 0 ? -1 : 1;
      c.save();
      c.globalAlpha = open;
      c.fillStyle = b.p.base;
      roundBar(c, cx + dir * gap - (dir < 0 ? bw : 0), ty - bh, bw, bh, b.h * 0.03);
      c.fill();
      c.strokeStyle = b.p.deep;
      c.lineWidth = Math.max(b.h * 0.008, 1.2);
      c.stroke();
      c.strokeStyle = b.p.deep;
      c.lineWidth = Math.max(b.h * 0.004, 1);
      let lines = Math.floor(open * 6);
      for (let i = 0; i < lines; i++) {
        let y = ty - bh * (0.16 + i * 0.13);
        c.beginPath();
        c.moveTo(cx + dir * gap - (dir < 0 ? bw * 0.92 : -bw * 0.08), y);
        c.quadraticCurveTo(cx + dir * gap + dir * bw * 0.4, y - bh * 0.05,
          cx + dir * gap - (dir < 0 ? bw * 0.08 : -bw * 0.92), y + bh * 0.02);
        c.stroke();
      }
      c.restore();
    }
    let flick = seg(b.ph, 0.80, 1);
    let gx = cx + bw * 0.30;
    let gy = ty - bh * 0.45;
    c.fillStyle = b.p.deep;
    c.beginPath();
    c.arc(gx + flick * b.w * 0.22, gy - flick * b.h * 0.20 + flick * flick * b.h * 0.10,
      Math.max(b.w * 0.010, 1.6), 0, Math.PI * 2);
    c.fill();
    if (flick < 0.5) {
      c.strokeStyle = '#A6553D';
      c.lineWidth = Math.max(b.h * 0.006, 1);
      c.beginPath();
      c.arc(gx, gy, b.w * 0.030 * (1 + flick), 0, Math.PI * 2);
      c.stroke();
    }
  }
  watermark(b, b.w * 0.14, b.h * 0.20, b.h * 0.15, 0.10);
}

function wheel(b: ShotBox, cx: number, cy: number, rx: number, speed: number): void {
  let c = b.c;
  let ry = rx * 0.20;
  c.fillStyle = 'rgba(43,38,34,0.26)';
  c.beginPath();
  c.ellipse(cx, cy, rx, ry, 0, 0, Math.PI * 2);
  c.fill();
  c.strokeStyle = b.p.accent;
  c.lineWidth = Math.max(b.h * 0.008, 1.2);
  c.setLineDash([b.h * 0.026, b.h * 0.026]);
  for (let i = 0; i < 2; i++) {
    let a = (b.t * speed + i * 1.7) % 6.283;
    c.beginPath();
    c.ellipse(cx, cy - b.h * 0.004, rx * (0.62 + i * 0.26), ry * (0.62 + i * 0.26),
      0, a, a + Math.PI * 0.85);
    c.stroke();
  }
  c.setLineDash([]);
}

function c02s2(b: ShotBox): void {
  let c = b.c;
  let cx = b.w * 0.5;
  let ty = b.h * 0.78;
  halo(b, cx, ty - b.h * 0.18, b.h * 0.46);
  wheel(b, cx, ty, b.w * 0.34, 3.2);
  let set = ease(seg(b.ph, 0.10, 0.82));
  let wob = (1 - set) * b.w * 0.085 * Math.sin(b.t * 8.5);
  let sq = Math.sin(b.t * 3.6);
  let vw = b.w * (0.62 + 0.03 * sq);
  let hh = b.h * (0.22 + 0.02 * sq - 0.03 * set);
  drawVessel(b, profileOf('盆'), 0.10, cx + wob, ty - hh, ty, vw, b.p.base, false);
  hands(b, cx + wob, ty - hh - b.h * 0.012, vw * 0.11, 0.9);
  let ax = seg(b.ph, 0.62, 0.95);
  if (ax > 0.01) {
    c.save();
    c.globalAlpha = ax;
    c.strokeStyle = '#A6553D';
    c.lineWidth = Math.max(b.h * 0.005, 1);
    c.setLineDash([b.h * 0.022, b.h * 0.020]);
    c.beginPath();
    c.moveTo(cx, b.h * 0.10);
    c.lineTo(cx, ty + b.h * 0.04);
    c.stroke();
    c.setLineDash([]);
    c.restore();
  }
  c.strokeStyle = 'rgba(43,38,34,0.30)';
  c.lineWidth = Math.max(b.h * 0.006, 1);
  for (let i = -1; i <= 1; i += 2) {
    let p = (b.t * 0.9 + (i > 0 ? 0.5 : 0)) % 1;
    c.save();
    c.globalAlpha = 0.5 * (1 - p);
    c.beginPath();
    c.moveTo(cx + i * b.w * (0.30 + p * 0.14), ty - b.h * 0.10);
    c.lineTo(cx + i * b.w * (0.34 + p * 0.14), ty - b.h * 0.02);
    c.stroke();
    c.restore();
  }
  watermark(b, b.w * 0.86, b.h * 0.20, b.h * 0.14, 0.09);
}

function c02s3(b: ShotBox): void {
  let c = b.c;
  let cx = b.w * 0.5;
  let ty = b.h * 0.78;
  halo(b, cx, ty - b.h * 0.26, b.h * 0.50);
  wheel(b, cx, ty, b.w * 0.32, 2.4);
  let up = ease(seg(b.ph, 0.06, 0.96));
  let prof = profileOf('罐');
  let vw = b.w * 0.52;
  let hh = b.h * (0.16 + 0.36 * up);
  let top = ty - hh;
  let wall = b.w * (0.055 - 0.030 * up);
  let outer = vesselPts(prof, 1, cx, top, ty, vw);
  let inner = vesselPts(prof, 1, cx, top + wall * 1.2, ty - wall * 0.6, vw - wall * 2.6);
  smoothClosed(c, outer);
  c.fillStyle = b.p.base;
  c.fill();
  c.strokeStyle = b.p.deep;
  c.lineWidth = Math.max(b.w * 0.008, 1.4);
  c.stroke();
  c.save();
  smoothClosed(c, outer);
  c.clip();
  c.globalAlpha = 0.9;
  smoothClosed(c, inner);
  c.fillStyle = b.p.deep;
  c.fill();
  c.restore();
  let hole = ease(seg(b.ph, 0, 0.34));
  let mrx = Math.max(vw * 0.42 * hole, 1.2);
  let mry = Math.max(vw * 0.11 * hole, 1);
  c.fillStyle = mixHex(b.p.deep, '#141311', 0.45);
  c.beginPath();
  c.ellipse(cx, top, mrx, mry, 0, 0, Math.PI * 2);
  c.fill();
  c.strokeStyle = mixHex(b.p.base, b.p.paper, 0.55);
  c.lineWidth = Math.max(b.h * 0.006, 1.2);
  c.beginPath();
  c.ellipse(cx, top, mrx, mry, 0, Math.PI, Math.PI * 2);
  c.stroke();
  c.save();
  smoothClosed(c, outer);
  c.clip();
  c.strokeStyle = b.p.deep;
  c.lineWidth = Math.max(b.h * 0.005, 1);
  for (let i = 0; i < 5; i++) {
    let k = (i + (b.t * 0.5) % 1) / 6;
    if (k > 1) {
      continue;
    }
    let y = top + (ty - top) * (0.12 + k * 0.8);
    let hw = (vw * 0.34) * (0.7 + 0.3 * Math.sin(k * Math.PI));
    c.beginPath();
    c.moveTo(cx - hw, y);
    c.quadraticCurveTo(cx, y + b.h * 0.012, cx + hw, y);
    c.stroke();
  }
  c.restore();
  hands(b, cx, top + b.h * 0.02, vw * 0.24, 1 - seg(b.ph, 0.88, 1));
  watermark(b, b.w * 0.14, b.h * 0.18, b.h * 0.13, 0.08);
}

function c02s4(b: ShotBox): void {
  let c = b.c;
  let cx = b.w * 0.5;
  let ty = b.h * 0.78;
  let top = b.h * STAGE_TOP;
  let vw = b.w * 0.52;
  halo(b, cx, (top + ty) * 0.5, b.h * 0.50);
  wheel(b, cx, ty, b.w * 0.30, 1.1);
  let prof = profileOf('罐');
  let pts = drawVessel(b, prof, 1, cx, top, ty, vw, b.p.base, true);
  c.save();
  smoothClosed(c, pts);
  c.clip();
  let shine = ease(seg(b.ph, 0.34, 0.86));
  if (shine > 0.01) {
    let y = top + (ty - top) * (0.16 + 0.70 * shine);
    let g: CanvasGradient = c.createLinearGradient(0, y - b.h * 0.042, 0, y + b.h * 0.042);
    g.addColorStop(0, 'rgba(255,252,244,0)');
    g.addColorStop(0.5, 'rgba(255,252,244,0.38)');
    g.addColorStop(1, 'rgba(255,252,244,0)');
    c.fillStyle = g;
    c.fillRect(cx - vw * 0.5, y - b.h * 0.042, vw, b.h * 0.084);
    c.strokeStyle = '#5A4030';
    c.lineWidth = Math.max(b.h * 0.012, 1.4);
    c.beginPath();
    c.moveTo(cx + vw * 0.60, y - b.h * 0.10);
    c.quadraticCurveTo(cx + vw * 0.34, y - b.h * 0.02, cx + vw * 0.26, y);
    c.stroke();
  }
  let mk = ease(seg(b.ph, 0.52, 0.98));
  if (mk > 0.01) {
    let gy = top + (ty - top) * 0.34;
    let gh = (ty - top) * 0.26;
    c.save();
    c.beginPath();
    c.rect(cx - vw * 0.5, gy, vw, gh * mk);
    c.clip();
    grid(c, b.p, cx - vw * 0.5, cx + vw * 0.5, gy, gy + gh, 2);
    c.restore();
  }
  c.restore();
  let cut = seg(b.ph, 0.02, 0.50);
  if (cut > 0.01 && cut < 0.99) {
    let y = top + (ty - top) * (0.30 + 0.40 * ((Math.sin(b.t * 1.9) + 1) / 2));
    c.strokeStyle = '#5A4030';
    c.lineWidth = Math.max(b.h * 0.014, 1.6);
    c.beginPath();
    c.moveTo(cx + vw * 0.62, y - b.h * 0.12);
    c.lineTo(cx + vw * 0.30, y);
    c.stroke();
    c.fillStyle = b.p.deep;
    let chips = Math.floor(cut * 5) + 1;
    for (let i = 0; i < chips; i++) {
      let d = (b.t * 0.8 + i * 0.21) % 1;
      c.beginPath();
      c.ellipse(cx + vw * (0.58 + i * 0.07), y + (ty + b.h * 0.02 - y) * d,
        b.w * 0.016, b.h * 0.010, 0.6 + i * 0.4 + d, 0, Math.PI * 2);
      c.fill();
    }
  }
  watermark(b, b.w * 0.88, b.h * 0.16, b.h * 0.12, 0.08);
}

function c02s5(b: ShotBox): void {
  let c = b.c;
  let cx = b.w * 0.5;
  let ty = b.h * 0.80;
  let top = b.h * 0.30;
  let vw = b.w * 0.48;
  let load = ease(seg(b.ph, 0.10, 0.50));
  let ink = ease(seg(b.ph, 0.30, 0.96));
  kiln(b, load, cx, ty + b.h * 0.02, b.w * 0.40, b.h * 0.42);
  table(b, ty, cx, vw * 0.42);
  halo(b, cx, (top + ty) * 0.5, b.h * 0.44);
  let body = mixHex(b.p.base, '#232220', ink);
  let prof = profileOf('罐');
  let pts = drawVessel(b, prof, 1, cx, top, ty, vw, body, true);
  c.save();
  smoothClosed(c, pts);
  c.clip();
  c.save();
  c.globalAlpha = 0.5;
  let gp: Palette = { base: body, deep: '#1B1A18', accent: '#B9B4A8', ink: '#EDE7DC',
    paper: '#D8D2C6' };
  grid(c, gp, cx - vw * 0.5, cx + vw * 0.5, top + (ty - top) * 0.34,
    top + (ty - top) * 0.60, 2);
  c.restore();
  if (ink > 0.35) {
    let s = (b.t * 0.34) % 1;
    c.save();
    c.globalAlpha = (ink - 0.35) / 0.65;
    c.translate(cx - vw * 0.6 + vw * 1.2 * s, 0);
    c.rotate(-0.26);
    let g: CanvasGradient = c.createLinearGradient(-vw * 0.06, 0, vw * 0.06, 0);
    g.addColorStop(0, 'rgba(255,255,255,0)');
    g.addColorStop(0.5, 'rgba(255,255,255,0.55)');
    g.addColorStop(1, 'rgba(255,255,255,0)');
    c.fillStyle = g;
    c.fillRect(-vw * 0.06, top - b.h * 0.1, vw * 0.12, (ty - top) + b.h * 0.2);
    c.restore();
  }
  c.restore();
  let dry = 1 - seg(b.ph, 0.24, 0.44);
  wisps(b, cx - vw * 0.3, cx + vw * 0.3, top + b.h * 0.02, b.h * 0.12, 3, 0.20,
    0.5 * dry, 'rgba(255,252,244,0.95)');
  if (load > 0.01) {
    c.save();
    c.globalAlpha = load;
    wisps(b, cx - b.w * 0.18, cx + b.w * 0.18, b.h * 0.30, b.h * 0.14, 3, 0.30, 0.6,
      'rgba(43,38,34,0.35)');
    c.fillStyle = 'rgba(246,164,76,0.85)';
    for (let i = 0; i < 4; i++) {
      let up = (b.t * 0.5 + i * 0.25) % 1;
      let side = i % 2 === 0 ? -1 : 1;
      let off = b.w * (i < 2 ? 0.29 : 0.35);
      c.beginPath();
      c.arc(cx + side * off, ty - b.h * 0.06 - b.h * 0.40 * up,
        Math.max(b.w * (0.008 - 0.004 * up), 1.2), 0, Math.PI * 2);
      c.fill();
    }
    c.restore();
  }
  watermark(b, b.w * 0.12, b.h * 0.16, b.h * 0.12, 0.07);
}

export function hasCourseShot(id: string): boolean {
  return id === 'c01' || id === 'c02';
}

const TAGS: Map<string, string[]> = new Map<string, string[]>([
  ['c01', ['练泥', '起稿', '勾线', '填彩', '入窑']],
  ['c02', ['揉泥', '定中', '拉升', '修坯', '渗碳']]
]);

export function courseTag(id: string, shot: number): string {
  let tags = TAGS.get(id);
  if (tags === undefined) {
    return '';
  }
  let i = shot < 0 ? 0 : (shot >= tags.length ? tags.length - 1 : shot);
  return tags[i];
}

export function drawCourseShot(id: string, shot: number, b: ShotBox): void {
  let i = shot < 0 ? 0 : (shot > 4 ? 4 : shot);
  if (id === 'c01') {
    if (i === 0) {
      c01s1(b);
    } else if (i === 1) {
      c01s2(b);
    } else if (i === 2) {
      c01s3(b);
    } else if (i === 3) {
      c01s4(b);
    } else {
      c01s5(b);
    }
    return;
  }
  if (i === 0) {
    c02s1(b);
  } else if (i === 1) {
    c02s2(b);
  } else if (i === 2) {
    c02s3(b);
  } else if (i === 3) {
    c02s4(b);
  } else {
    c02s5(b);
  }
}
