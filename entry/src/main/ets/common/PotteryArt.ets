import { Palette } from './Theme';

/*
 * 彩陶器型的矢量画法：轮廓、纹样带、六种纹样、题字。
 *
 * 这份代码原来长在 view/PotteryCanvas.ets 里，现在抽出来给两处共用：
 *   1) view/PotteryCanvas.ets —— 纯二维现画（也是序列帧加载失败时的兜底）
 *   2) view/PotteryTurntable.ets —— 把同一套纹样按弧度罩到 3D 灰模序列帧上
 * 抽出来的目的不是省字，是「降级前后纹样必须一模一样」：两条链路各写一遍，
 * 改了一种纹样就会只在一边生效，而这种差异只有对着两台设备比才看得出来。
 *
 * 所以这里的函数一律把 shape / motif / seed 当参数收进来，不读组件状态。
 * 形参类型统一用 CanvasRenderer（CanvasRenderingContext2D 的父类）而不是子类型：
 * 转台为了不再每帧重画十几遍整条纹样带，会把带子先烘到 OffscreenCanvas 上，
 * 而 OffscreenCanvasRenderingContext2D 跟 CanvasRenderingContext2D 是兄弟不是父子，
 * 只认父类才一处画法两边都能喂（ArkTS 不做结构化兼容，写成子类型直接编译不过）。
 * * 轮廓数据与 rawfile/pottery/geometry.js 镜像，改一处要改两处
 * （改完跑 node tools/bake_pottery_frames.mjs --check 会校验帧与映射表是否同步）。
 */

export const V_TOP: number = 0.12;
export const V_BOT: number = 0.76;

export function profileOf(shape: string): number[][] {
  if (shape === '盆') {
    return [[0, 0.46], [0.06, 0.45], [0.20, 0.42], [0.38, 0.36],
      [0.56, 0.29], [0.74, 0.20], [0.90, 0.12], [1, 0.09]];
  }
  if (shape === '壶') {
    return [[0, 0.15], [0.04, 0.18], [0.12, 0.13], [0.24, 0.12], [0.36, 0.20],
      [0.48, 0.33], [0.60, 0.38], [0.74, 0.34], [0.86, 0.25], [0.94, 0.17], [1, 0.19]];
  }
  if (shape === '瓶') {
    return [[0, 0.11], [0.04, 0.14], [0.16, 0.10], [0.34, 0.12], [0.46, 0.25],
      [0.58, 0.31], [0.84, 0.31], [0.95, 0.28], [1, 0.27]];
  }
  if (shape === '鼎式') {
    return [[0, 0.30], [0.05, 0.33], [0.14, 0.34], [0.32, 0.32],
      [0.50, 0.26], [0.68, 0.18], [0.86, 0.13], [1, 0.12]];
  }
  return [[0, 0.20], [0.05, 0.26], [0.16, 0.37], [0.32, 0.45], [0.48, 0.46],
    [0.64, 0.42], [0.82, 0.30], [0.94, 0.21], [1, 0.19]];
}

export function halfWidthAt(shape: string, t: number, w: number): number {
  let prof = profileOf(shape);
  let lo = prof[0];
  let hi = prof[prof.length - 1];
  for (let i = 0; i < prof.length - 1; i++) {
    if (t >= prof[i][0] && t <= prof[i + 1][0]) {
      lo = prof[i];
      hi = prof[i + 1];
      break;
    }
  }
  let span = hi[0] - lo[0];
  let f = span <= 0 ? 0 : (t - lo[0]) / span;
  return (lo[1] + (hi[1] - lo[1]) * f) * w;
}

export function bandOf(shape: string): number[] {
  if (shape === '鼎式') {
    return [0.16, 0.44];
  }
  if (shape === '瓶') {
    return [0.48, 0.76];
  }
  if (shape === '壶') {
    return [0.42, 0.70];
  }
  return [0.32, 0.60];
}

// 器身轮廓闭合路径（只建路径，不填不描，由调用方决定怎么用）
export function tracePath(c: CanvasRenderer, shape: string,
  w: number, h: number): void {
  let prof = profileOf(shape);
  let cx = w / 2;
  let top = h * V_TOP;
  let bot = h * V_BOT;
  let right: number[][] = [];
  for (let i = 0; i < prof.length; i++) {
    right.push([cx + prof[i][1] * w, top + (bot - top) * prof[i][0]]);
  }
  c.beginPath();
  c.moveTo(right[0][0], right[0][1]);
  for (let i = 1; i < right.length - 1; i++) {
    c.quadraticCurveTo(right[i][0], right[i][1],
      (right[i][0] + right[i + 1][0]) / 2, (right[i][1] + right[i + 1][1]) / 2);
  }
  c.lineTo(right[right.length - 1][0], right[right.length - 1][1]);
  for (let i = right.length - 1; i > 0; i--) {
    let mx = (2 * cx - right[i][0] + 2 * cx - right[i - 1][0]) / 2;
    let my = (right[i][1] + right[i - 1][1]) / 2;
    c.quadraticCurveTo(2 * cx - right[i][0], right[i][1], mx, my);
  }
  c.lineTo(2 * cx - right[0][0], right[0][1]);
  c.closePath();
}

export function fish(c: CanvasRenderer, p: Palette, x0: number, x1: number,
  y0: number, y1: number, seed: number): void {
  let cy = (y0 + y1) / 2;
  let n = 3;
  let cw = (x1 - x0) / n;
  let bh = y1 - y0;
  for (let i = 0; i < n; i++) {
    let bx = x0 + i * cw + cw * 0.10 + (seed % 3) * cw * 0.03;
    c.fillStyle = p.accent;
    c.beginPath();
    c.moveTo(bx, cy);
    c.lineTo(bx + cw * 0.40, cy - bh * 0.27);
    c.lineTo(bx + cw * 0.40, cy + bh * 0.27);
    c.closePath();
    c.fill();
    c.strokeStyle = p.accent;
    c.lineWidth = Math.max(bh * 0.05, 1);
    c.beginPath();
    c.moveTo(bx + cw * 0.40, cy);
    c.lineTo(bx + cw * 0.58, cy - bh * 0.26);
    c.moveTo(bx + cw * 0.40, cy);
    c.lineTo(bx + cw * 0.58, cy + bh * 0.26);
    c.stroke();
    c.fillStyle = p.paper;
    c.beginPath();
    c.arc(bx + cw * 0.12, cy, Math.max(bh * 0.045, 1), 0, Math.PI * 2);
    c.fill();
    for (let k = 0; k < 3; k++) {
      for (let j = -1; j <= 1; j++) {
        c.fillStyle = p.paper;
        c.beginPath();
        c.arc(bx + cw * (0.22 + k * 0.07), cy + j * bh * 0.12,
          Math.max(bh * 0.028, 0.8), 0, Math.PI * 2);
        c.fill();
      }
    }
  }
}

export function bird(c: CanvasRenderer, p: Palette, x0: number, x1: number,
  y0: number, y1: number, seed: number): void {
  let cy = (y0 + y1) / 2 + (y1 - y0) * 0.10;
  let n = 3;
  let cw = (x1 - x0) / n;
  let bh = y1 - y0;
  c.strokeStyle = p.accent;
  c.fillStyle = p.accent;
  c.lineWidth = Math.max(bh * 0.07, 1.2);
  for (let i = 0; i < n; i++) {
    let bx = x0 + i * cw + cw * 0.34;
    c.beginPath();
    c.ellipse(bx, cy, cw * 0.20, bh * 0.17, -0.35, 0, Math.PI * 2);
    c.fill();
    let hx = bx + cw * 0.26;
    let hy = cy - bh * 0.40;
    c.beginPath();
    c.moveTo(bx + cw * 0.12, cy - bh * 0.10);
    c.quadraticCurveTo(hx, cy - bh * 0.16, hx, hy);
    c.stroke();
    c.beginPath();
    c.arc(hx, hy, Math.max(cw * 0.055, 1.5), 0, Math.PI * 2);
    c.fill();
    c.beginPath();
    c.moveTo(hx + cw * 0.05, hy);
    c.lineTo(hx + cw * 0.16, hy + bh * 0.06);
    c.stroke();
    c.beginPath();
    for (let k = -1; k <= 1; k++) {
      c.moveTo(bx - cw * 0.16, cy);
      c.lineTo(bx - cw * 0.36, cy + k * bh * 0.20 - bh * 0.06);
    }
    c.stroke();
    c.beginPath();
    c.moveTo(bx - cw * 0.02, cy + bh * 0.15);
    c.lineTo(bx - cw * 0.04, cy + bh * 0.32);
    c.moveTo(bx + cw * 0.08, cy + bh * 0.14);
    c.lineTo(bx + cw * 0.10, cy + bh * 0.31);
    c.stroke();
  }
}

export function swirl(c: CanvasRenderer, p: Palette, x0: number, x1: number,
  y0: number, y1: number, seed: number): void {
  let cy = (y0 + y1) / 2;
  let n = 3;
  let cw = (x1 - x0) / n;
  let r = Math.min(cw * 0.34, (y1 - y0) * 0.44);
  c.strokeStyle = p.accent;
  c.lineWidth = Math.max((y1 - y0) * 0.055, 1.2);
  for (let i = 0; i < n; i++) {
    let sx = x0 + i * cw + cw * 0.5;
    c.beginPath();
    let first = true;
    for (let a = 0; a <= Math.PI * 4.2; a += 0.16) {
      let rr = r * (1 - a / (Math.PI * 4.6));
      let px = sx + rr * Math.cos(a + (seed % 4));
      let py = cy + rr * Math.sin(a + (seed % 4)) * 0.9;
      if (first) {
        c.moveTo(px, py);
        first = false;
      } else {
        c.lineTo(px, py);
      }
    }
    c.stroke();
    c.beginPath();
    c.moveTo(sx + r * 1.18, cy);
    c.lineTo(sx + cw * 0.48, cy);
    c.stroke();
  }
}

export function grid(c: CanvasRenderer, p: Palette, x0: number, x1: number,
  y0: number, y1: number, seed: number): void {
  c.strokeStyle = p.accent;
  c.lineWidth = Math.max((y1 - y0) * 0.035, 1);
  let step = (y1 - y0) * 0.46;
  let span = (x1 - x0) + (y1 - y0);
  for (let d = 0; d < span; d += step) {
    let x = x0 - (y1 - y0) + d;
    c.beginPath();
    c.moveTo(x, y0);
    c.lineTo(x + (y1 - y0), y1);
    c.stroke();
    c.beginPath();
    c.moveTo(x + (y1 - y0), y0);
    c.lineTo(x, y1);
    c.stroke();
  }
}

export function sawtooth(c: CanvasRenderer, p: Palette, x0: number, x1: number,
  y0: number, y1: number, seed: number): void {
  c.fillStyle = p.accent;
  c.strokeStyle = p.accent;
  c.lineWidth = Math.max((y1 - y0) * 0.04, 1);
  let n = 9;
  let cw = (x1 - x0) / n;
  let h1 = y1 - (y1 - y0) * 0.44;
  for (let i = 0; i < n; i++) {
    c.beginPath();
    c.moveTo(x0 + i * cw, h1);
    c.lineTo(x0 + i * cw + cw / 2, y1);
    c.lineTo(x0 + (i + 1) * cw, h1);
    c.closePath();
    c.fill();
  }
  c.beginPath();
  let z = n * 2;
  let zw = (x1 - x0) / z;
  for (let i = 0; i <= z; i++) {
    let yy = i % 2 === 0 ? y0 + (y1 - y0) * 0.10 : y0 + (y1 - y0) * 0.32;
    if (i === 0) {
      c.moveTo(x0, yy);
    } else {
      c.lineTo(x0 + i * zw, yy);
    }
  }
  c.stroke();
}

export function petal(c: CanvasRenderer, p: Palette, x0: number, x1: number,
  y0: number, y1: number, seed: number): void {
  let cy = (y0 + y1) / 2;
  let n = 3;
  let cw = (x1 - x0) / n;
  let r = Math.min(cw * 0.30, (y1 - y0) * 0.40);
  for (let i = 0; i < n; i++) {
    let sx = x0 + i * cw + cw * 0.5;
    for (let k = 0; k < 6; k++) {
      c.save();
      c.translate(sx, cy);
      c.rotate(k * Math.PI / 3 + (seed % 3) * 0.2);
      c.fillStyle = k % 2 === 0 ? p.accent : 'rgba(255,255,255,0.55)';
      c.beginPath();
      c.ellipse(0, -r * 0.62, r * 0.30, r * 0.55, 0, 0, Math.PI * 2);
      c.fill();
      c.strokeStyle = p.accent;
      c.lineWidth = Math.max(r * 0.06, 1);
      c.stroke();
      c.restore();
    }
    c.fillStyle = p.accent;
    c.beginPath();
    c.arc(sx, cy, r * 0.22, 0, Math.PI * 2);
    c.fill();
  }
}

export type MotifPainter = (c: CanvasRenderer, p: Palette, x0: number,
  x1: number, y0: number, y1: number, seed: number) => void;

// 六种纹样的统一入口：二维版整幅画一次，转台版按弧度切成 8 段各画一次
export function motifPainter(motif: string): MotifPainter {
  if (motif === '鸟纹') {
    return bird;
  }
  if (motif === '漩涡纹') {
    return swirl;
  }
  if (motif === '网格纹') {
    return grid;
  }
  if (motif === '锯齿纹') {
    return sawtooth;
  }
  if (motif === '花瓣纹') {
    return petal;
  }
  return fish;
}

export function drawWord(c: CanvasRenderer, p: Palette, word: string,
  shape: string, seed: number, w: number, h: number): void {
  if (word.length === 0) {
    return;
  }
  let top = h * V_TOP;
  let bot = h * V_BOT;
  let bd = bandOf(shape);
  let wt = Math.min(bd[1] + 0.15, 0.88);
  let wy = top + (bot - top) * wt;
  let cs = word.split('');
  let hw = halfWidthAt(shape, wt, w);
  let size = w * 0.085;
  let fit = hw * 1.7 / (cs.length * 1.18);
  if (fit < size) {
    size = fit;
  }
  if (size < 6) {
    return;
  }
  c.fillStyle = p.accent;
  // 单位必须写 vp：ArkUI 的画布坐标是 vp，可 font 里的裸数字它按「物理像素」吃。
  // 模拟器实测（同一处画两笔只差单位）—— '40px' 落 16 设备像素、'40vp' 落 58，
  // 正好差一个屏幕密度 3.5。写 px 就等于把题字缩小 3.5 倍：罐肚上那颗「河」
  // 只有 10 帧像素高（本该 44），而且十次里有六次干脆一个字都不落。
  // 浏览器不认 vp，所以 .tmp/pot_preview/preview.mjs 拼 harness 时会把这一处换回 px
  // （CSS px 就是画布单位，语义与 ArkUI 的 vp 一致），换不掉会有断言报错。
  c.font = `${Math.round(size)}vp sans-serif`;
  c.textAlign = 'center';
  c.textBaseline = 'middle';
  let total = cs.length * size * 1.18;
  for (let i = 0; i < cs.length; i++) {
    c.fillText(cs[i], w / 2 - total / 2 + size * 0.59 + i * size * 1.18, wy);
  }
}

// #RRGGBB 线性掺色：b 的权重 k，结果还是不透明的 #RRGGBB。
// 除了纸底，课程分镜里“渗碳由灰变黑”“窑温把胎色压深”也要靠它渐变，所以导出。
// 不用 toString(16) 是免得 ArkTS 又在 Number 的动态方法上挑刺，直接查表。
// 收到非法颜色就原样返回，宁可不掺也别画出一个 #000000。
const HEXD: string[] = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
  'A', 'B', 'C', 'D', 'E', 'F'];

function hx2(n: number): string {
  let v = Math.round(n < 0 ? 0 : (n > 255 ? 255 : n));
  return HEXD[Math.floor(v / 16)] + HEXD[v % 16];
}

export function mixHex(a: string, b: string, k: number): string {
  if (a.length !== 7 || b.length !== 7 || !a.startsWith('#') || !b.startsWith('#')) {
    return a;
  }
  let ar = parseInt(a.substring(1, 3), 16);
  let ag = parseInt(a.substring(3, 5), 16);
  let ab = parseInt(a.substring(5, 7), 16);
  let br = parseInt(b.substring(1, 3), 16);
  let bg = parseInt(b.substring(3, 5), 16);
  let bb = parseInt(b.substring(5, 7), 16);
  return '#' + hx2(ar + (br - ar) * k) + hx2(ag + (bg - ag) * k) + hx2(ab + (bb - ab) * k);
}

// 纸底：竖向渐变 + 五道横向水波纹。转台把它压到器物后面（destination-over），
// 二维版还是老样子先铺底再画器，两种顺序画出来的纸底是同一张。
//
// 下端那一笔原来是 p.base —— 也就是器物本体那层釉色。器身和纸底用同一个颜色的结果是
// 「陶器和背景分不开」：纸底渐变的取样行（器腹以下、底足以上，t≈0.72~0.86）龙山黑只有 134，
// 仰韶红 191；对着同一行的器缘算下来，六套釉色的 ΔL 全在 57~68 这一带。
// 现在按 0.30 的权重先把 base 掺进 paper，掺完仍是**不透明色**：同一行龙山黑纸底 188、
// 仰韶红 213，六套釉色的 ΔL 抬到 85~113，土味的色相留着，明度让开。
// 为什么不能用 rgba(base, 0.30) 让画布自己去叠：转台底下垫的是不透明的 .backgroundColor，
// 二维版和浏览器 harness 底下是透明画布，同一句 alpha 在三处叠出三种颜色，量都量不准
// （harness 里读出来直接和改之前一模一样，就是这个坑暴露的）。掺成实色后三条链路同一个数。
export function drawPaper(c: CanvasRenderer, p: Palette, seed: number,
  w: number, h: number): void {
  let g: CanvasGradient = c.createLinearGradient(0, 0, 0, h);
  g.addColorStop(0, p.paper);
  g.addColorStop(1, mixHex(p.paper, p.base, 0.30));
  c.fillStyle = g;
  c.fillRect(0, 0, w, h);
  c.fillStyle = 'rgba(255,255,255,0.22)';
  for (let i = 0; i < 5; i++) {
    let yy = h * (0.10 + i * 0.19) + (seed % 5) * h * 0.01;
    c.beginPath();
    c.moveTo(0, yy);
    c.quadraticCurveTo(w * 0.5, yy - h * 0.04, w, yy + h * 0.02);
    c.lineTo(w, yy + h * 0.03);
    c.quadraticCurveTo(w * 0.5, yy - h * 0.01, 0, yy + h * 0.03);
    c.closePath();
    c.fill();
  }
}

// 纹样带的一层：底光 + 纹样本体 + 上下两道边线。
// 二维版整幅调一次（x0=0, x1=w）；转台按弧度切成若干竖条，每条调一到两次，
// 所以这里不能读组件状态，也不能假设 x0 一定是 0。
export function drawBand(c: CanvasRenderer, p: Palette, motif: string,
  seed: number, x0: number, x1: number, y0: number, y1: number, h: number): void {
  c.fillStyle = 'rgba(255,255,255,0.16)';
  c.fillRect(x0, y0, x1 - x0, y1 - y0);
  motifPainter(motif)(c, p, x0, x1, y0, y1, seed);
  c.strokeStyle = p.accent;
  c.lineWidth = Math.max(h * 0.006, 1);
  c.beginPath();
  c.moveTo(x0, y0 + (y1 - y0) * 0.03);
  c.lineTo(x1, y0 + (y1 - y0) * 0.03);
  c.moveTo(x0, y1 - (y1 - y0) * 0.03);
  c.lineTo(x1, y1 - (y1 - y0) * 0.03);
  c.stroke();
}

// 口沿的双椭圆和底足的椭圆。
// 特意不含器耳：二维版靠这两段弧线描出耳来，转台的耳已经烘进 3D 灰模帧里了，
// 再描一遍会变成图上长出一对扁平的纸耳朵。
export function drawRimFoot(c: CanvasRenderer, p: Palette, shape: string,
  w: number, h: number): void {
  let top = h * V_TOP;
  let bot = h * V_BOT;
  let prof = profileOf(shape);
  let rx = prof[0][1] * w;
  c.fillStyle = p.deep;
  c.beginPath();
  c.ellipse(w / 2, top, rx, Math.max(rx * 0.22, 2), 0, 0, Math.PI * 2);
  c.fill();
  c.fillStyle = p.ink;
  c.beginPath();
  c.ellipse(w / 2, top, rx * 0.74, Math.max(rx * 0.15, 1.4), 0, 0, Math.PI * 2);
  c.fill();
  let fr = prof[prof.length - 1][1] * w;
  c.strokeStyle = p.deep;
  c.lineWidth = Math.max(w * 0.006, 1);
  c.beginPath();
  c.ellipse(w / 2, bot, fr, Math.max(fr * 0.16, 1.6), 0, 0, Math.PI * 2);
  c.stroke();
}

// 展示座。bot 传器物底边的 y：二维版是 h * V_BOT，转台是帧映射到画布后的底边，
// 两者都落在同一处（帧的 topPx/botPx 就是按 0.12/0.76 烘的）。
// 座面贴着器底：原来座面在 bot + (h-bot)*0.42，器和座之间悬着一段空，
// 素台又是一只描边空心方框，远看像浮在器物下面的选中框，跟器身完全割裂。
// 现在座面椭圆的中心只比底足线低一点，底足正好落在座面里；素台改成
// 「座面椭圆 + 圆柱座身」的实心底座，只留填充不描边框。
// 遮挡关系靠调用方的绘制顺序保证：二维版在器身之前画座（器身盖住座面当中），
// 转台在器身之后用 destination-over 画座（座只落在透明区，等于器身遮住座面后沿）。
export function drawPedestal(c: CanvasRenderer, p: Palette, shape: string,
  pedestal: string, bot: number, w: number, h: number): void {
  let base = bot + h * 0.012;
  if (pedestal === '无') {
    // 不垫座也贴一枚接触阴影在足下，器物不悬空
    c.fillStyle = 'rgba(43,38,34,0.16)';
    c.beginPath();
    c.ellipse(w / 2, base + h * 0.012, w * 0.26, h * 0.026, 0, 0, Math.PI * 2);
    c.fill();
    return;
  }
  // 座身落地的阴影
  c.fillStyle = 'rgba(43,38,34,0.12)';
  c.beginPath();
  c.ellipse(w / 2, base + h * 0.085, w * 0.36, h * 0.032, 0, 0, Math.PI * 2);
  c.fill();
  if (pedestal === '木座') {
    c.fillStyle = '#5A4030';
    c.beginPath();
    c.moveTo(w * 0.26, base);
    c.lineTo(w * 0.74, base);
    c.lineTo(w * 0.69, base + h * 0.05);
    c.lineTo(w * 0.31, base + h * 0.05);
    c.closePath();
    c.fill();
    c.fillRect(w * 0.32, base + h * 0.05, w * 0.05, h * 0.04);
    c.fillRect(w * 0.63, base + h * 0.05, w * 0.05, h * 0.04);
    // 座面：比座身亮一档的木色，底足坐在这一圈上
    c.fillStyle = '#7A5843';
    c.beginPath();
    c.ellipse(w / 2, base, w * 0.24, h * 0.02, 0, 0, Math.PI * 2);
    c.fill();
  } else if (pedestal === '圆几') {
    // 圆几和素台同一套立体语言：几面有厚度（面椭圆亮一档、前沿暗一档），
    // 三足是带宽度的填充而不是描线，原来的「椭圆圈+火柴棍腿」是平面图。
    let rx = w * 0.30;
    let ry = h * 0.024;
    // 先画腿：上端被几面前沿压住，接榫才看不出缝；中间一腿正对、两侧外撇
    c.fillStyle = 'rgba(255,255,255,0.60)';
    for (let i = -1; i <= 1; i++) {
      let lx = w / 2 + i * rx * 0.62;
      let fx = w / 2 + i * rx * 0.84;
      c.beginPath();
      c.moveTo(lx - w * 0.014, base + ry * 0.5);
      c.lineTo(lx + w * 0.014, base + ry * 0.5);
      c.lineTo(fx + w * 0.011, base + h * 0.085);
      c.lineTo(fx - w * 0.011, base + h * 0.085);
      c.closePath();
      c.fill();
    }
    // 几面厚度：座身矩形 + 下椭圆，和素台座身同一档颜色
    c.fillStyle = 'rgba(255,255,255,0.45)';
    c.fillRect(w / 2 - rx, base, rx * 2, h * 0.018);
    c.beginPath();
    c.ellipse(w / 2, base + h * 0.018, rx, ry, 0, 0, Math.PI * 2);
    c.fill();
    // 几面：亮一档的椭圆盖住上沿
    c.fillStyle = 'rgba(255,255,255,0.78)';
    c.beginPath();
    c.ellipse(w / 2, base, rx, ry, 0, 0, Math.PI * 2);
    c.fill();
  } else {
    // 素台：实心底座 = 座身矩形 + 底椭圆 + 亮一档的座面椭圆，一律填充不描边
    let rx = w * 0.28;
    let bh = h * 0.06;
    c.fillStyle = 'rgba(255,255,255,0.45)';
    c.fillRect(w / 2 - rx, base, rx * 2, bh);
    c.beginPath();
    c.ellipse(w / 2, base + bh, rx, h * 0.024, 0, 0, Math.PI * 2);
    c.fill();
    c.fillStyle = 'rgba(255,255,255,0.78)';
    c.beginPath();
    c.ellipse(w / 2, base, rx, h * 0.024, 0, 0, Math.PI * 2);
    c.fill();
  }
}

