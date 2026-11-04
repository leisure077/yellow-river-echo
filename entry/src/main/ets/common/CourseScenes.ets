import { Palette } from './Theme';
import { profileOf, grid, mixHex } from './PotteryArt';

/*
 * 课程分镜画面：一条教程的五个镜头画的是同一件器物从头做到尾，
 * 所以每一镜都保留上一镜留下的东西（弦线画完就在，鱼形勾完就在，器形拉起来就在），
 * 换镜时观众能看到"它在往下长"，而不是五张互不相干的插图。
 *
 * 每个形参都从 ShotBox 里取，不读组件状态：PlayerPage 的节拍器每 33ms 调一次，
 * 这里画的东西必须只由 (本镜进度 ph, 全局时钟 t) 决定，才叠得上下推入+叠化的转场。
 *
 * ph 一律用 seg() 切成几段，一段做一件事；t 只给往复动作（揉压、转盘、火苗）当相位。
 */

export interface ShotBox {
  c: CanvasRenderer;
  p: Palette;
  w: number;
  h: number;
  // 本镜进度 0..1
  ph: number;
  // 全局时钟（秒），暂停时不走
  t: number;
}

// 湿泥堆的剖面：[纵向位置, 半宽比例]，点数与 profileOf('盆') 对齐，
// 好让 morph 能在"一堆泥"和"一只盆"之间逐点插值。
// 半宽必须一路往底放大（0.10 → 0.40）：这是一坨墩在案板上的泥，上头收、下头摊。
// 原来中间最宽（0.34）两头窄，morph=0 时画出来是一只浮在半空的橄榄，泥饼不像泥饼。
const MOUND: number[][] = [[0, 0.10], [0.06, 0.16], [0.20, 0.24], [0.38, 0.30],
  [0.56, 0.34], [0.74, 0.37], [0.90, 0.39], [1, 0.40]];

// 画面的上沿：画布顶上 0.045 是分镜号、0.12 是本镜标题（PlayerPage 的 drawHud），
// 器物、窑、水汽一律从 0.23 往下长，谁也不许顶到字里。
const STAGE_TOP: number = 0.23;

function clamp01(x: number): number {
  return x < 0 ? 0 : (x > 1 ? 1 : x);
}

// 把整镜进度切成一段：ph 落在 [a,b] 里的比例
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

// 闭合平滑轮廓：把点列当多边形，用「过相邻中点 + 顶点做控制点」抹圆，
// 八个点直连会看出棱，器物就成了一只纸筒。
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

// 圆角长方形的路径：泥块、指头都是这种形状。
// 没用 ctx.roundRect —— 那是 Canvas2D 较新才补的方法，本机 ArkUI 的 CanvasRenderer
// 上有没有还不一定，自己用四段弧拼一条闭合路径，两边都画得出来。
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

// 器物轮廓点列：右侧自上而下 + 左侧自下而上；morph 把目标器形往湿泥堆回退
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

// MOUND 只有盆那套 8 个点，罐是 9 个：morph 到 1 时泥堆权重为 0，
// 但数组越界取值在 ArkTS 里是真的会炸，所以点数不够就退回最后一档。
function halfWidth(prof: number[][], i: number, morph: number, vw: number): number {
  if (morph >= 0.999) {
    return prof[i][1] * vw;
  }
  let mi = i < MOUND.length ? i : MOUND.length - 1;
  return (prof[i][1] * morph + MOUND[mi][1] * (1 - morph)) * vw;
}

// 画一件器物：胎色 + 描线 + 口沿，返回轮廓点列给调用方做裁剪
//
// 胎不铺平色：左右两压深、偏左一档提亮，一条横向渐变把"圆"读出来。
// 平铺 base 的时候器物颜色和纸底下端同一个色，边缘又只有 1.4px 描线，
// 模拟器上看着像一张剪下来的色纸贴在背景上，不像一件有体积的坯。
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
    // 膛内比器身暗一档：原来填 paper，口上像扣了一只白盘子
    c.fillStyle = mixHex(body, b.p.deep, 0.48);
    c.beginPath();
    c.ellipse(cx, top, rx * 0.86, Math.max(rx * 0.13, 1.6), 0, 0, Math.PI * 2);
    c.fill();
    // 沿口受光：只走上半圈的一道细亮
    c.strokeStyle = 'rgba(255,252,244,0.42)';
    c.lineWidth = Math.max(b.h * 0.004, 1);
    c.beginPath();
    c.ellipse(cx, top, rx * 0.93, Math.max(rx * 0.145, 1.8), 0, Math.PI * 1.05, Math.PI * 1.95);
    c.stroke();
  }
  return pts;
}

// 沿点列画到 frac 处，返回笔尖坐标：勾线、拉弦线这类"一笔走完"的动作都靠它
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

// 一支笔 / 一根炭条：从右上斜伸下来，笔尖落在 tip。
// 杆长压在 0.13w：原来拖到 0.24w，一根杆横过大半只盆，看着像器物上插了根签子。
// 靠尖那一段换成料色再收细，笔尖才有个落点，不然就是一个黑点悬在半空。
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

// 一双手：小臂从画面上沿探进来（伸到框外，看不到断口），掌心按在泥上，
// 四指并拢顺着器壁往下弯，拇指朝内。
// 原来那版是一条又宽又硬的大梯形当手臂，屏幕上就是两根木板；手要像手，
// 得换成浅肤色 + 描边，指头一根根画出来，才压得住"踩揉、定中、带壁"这些动作。
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
    // 小臂
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
    // 四指：先描一圈深色再填肤色，指缝靠后一根压前一根自己叠出来
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
    // 掌心压在泥面上，把指根盖住
    c.beginPath();
    c.ellipse(0, 0, pw, ph, 0, 0, Math.PI * 2);
    c.fillStyle = skin;
    c.fill();
    c.strokeStyle = line;
    c.lineWidth = lw;
    c.stroke();
    // 拇指朝内：左手在右边、右手在左边，正好搭在器口内侧
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

// 台面：一条地平线 + 器物下面那团接触阴影，五镜共用同一个"桌面"
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

// 器物背后一圈柔光：把主体从纸底上托出来，不然五镜都是"平贴"
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

// 背景水印：一件放大的漩涡纹压在纸底上，只留一点点存在感。
// cy 在函数里兜底压到 0.40h 以下：画布顶上那两行字（分镜号、本镜标题）是最后画的，
// 一圈淡淡的螺旋压在字底下会把字吃掉，往下挪就没这个冲突。
function watermark(b: ShotBox, cx: number, cy: number, r: number, alpha: number): void {
  let c = b.c;
  let y = cy;
  if (y < b.h * 0.40) {
    y = b.h * 0.40;
  }
  c.save();
  // 再淡一档：0.09 的螺旋压在器物边上就是脏印子，水印只该在纸底上留个影子
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

// 上升的烟 / 水汽：三条人字往上抬，越往上越散。
// 抬升的距离 dist 由调用方给：画面顶上那一条是分镜号和步骤名，水汽只能走一半就得散掉。
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

// 窑：一道拱门 + 膛内的火光，k 是"进窑程度"
// 一座拱：底边落在 baseY 上，拱顶高 rh。窑身和窑口共用这一条路径。
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
  // 窑身：原来只有一团 0.30 的灰，屏幕上就是一堵墙；勾出拱形描边才像一座窑
  archPath(c, cx, baseY, rw, rh);
  c.fillStyle = 'rgba(96,84,72,0.32)';
  c.fill();
  c.strokeStyle = 'rgba(43,38,34,0.55)';
  c.lineWidth = Math.max(b.h * 0.007, 1.4);
  c.stroke();
  // 窑砖：三道跟着拱走的横缝
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
  // 窑口：火是从口里冒出来的，不是一块贴在窑身上的橙色方块
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
  // 三簇火苗各自抖
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

// —— 仰韶鱼纹盆：泥饼 → 盆形 → 弦线分区 → 一笔勾鱼 → 填黑彩 → 阴干入窑 ——

// 鱼形轮廓（开口折线，够长够密才能"一条弧线走到底"）：
// 从鱼头上沿起，走背到尾叉，叉开两片尾叶，再走腹回来收在嘴边
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
  // 尾叉：上叶 → 凹口 → 下叶
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
  // 鱼头那道弧收口
  pts.push(cx - L * 0.5 + L * 0.02);
  pts.push(cy - H * 0.10);
  return pts;
}

// 三条鱼共用这一份画法：fill 是黑彩填了多少，sc 点鳞、dot 留气眼和鱼眼、fin 挑鳍。
// 一条教程里只画一条鱼太孤单，庙底沟那种鱼纹是一圈挨着排的。
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
      // 湿彩的下沿亮一道，看得出这一笔刚抹过去
      c.fillStyle = 'rgba(255,252,244,0.20)';
      c.fillRect(fx - L * 0.55, cy - H * 0.62 + H * 1.24 * fill, L * 1.1,
        Math.max(H * 0.05, 1.6));
    }
    // 黑彩里留白：一道侧线 + 几枚斜鳞钉，鱼就是鱼，不会读成一张脸
    // 得等这条鱼填得七七八八再点，不然白线是落在没上彩的红胎上的
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
        // 尾根上下各留一颗气眼，离鱼眼远一点
        for (let i = 0; i < 2; i++) {
          c.beginPath();
          c.arc(fx + L * 0.30, cy + (i === 0 ? -1 : 1) * H * 0.24, Math.max(L * 0.024, 1.2), 0,
            Math.PI * 2);
          c.fill();
        }
        // 鱼眼：头在左边
        c.beginPath();
        c.arc(fx - L * 0.33, cy - H * 0.05, Math.max(L * 0.048, 1.5), 0, Math.PI * 2);
        c.fill();
        c.restore();
      }
    }
    c.restore();
  }
  if (fin > 0.01) {
    // 背鳍腹鳍各一道：贴着身子往后挑的月牙，不是插在身上的三角
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

// 纹样带里三条鱼的下标：一条鱼占 0.27 个器宽，间距 0.30，正好排满两道弦线之间
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
  // 两只手：揉压段一压一回弹，围盆之后抬开
  // 掌距跟着器形张开——泥饼顶上只有 0.10 的半宽，手一直摆在 0.30 就成两边各一只手套
  let press = (Math.sin(b.t * 4.4) + 1) / 2;
  hands(b, cx, ty - hh - b.h * (0.005 + 0.03 * press), vw * (0.12 + 0.20 * rise),
    1 - seg(b.ph, 0.86, 1));
  // 接口抹平：一道亮痕沿缝走一圈就淡掉
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
  // 弦线要贴着器腹走，裁进轮廓里才不像是贴在盆上的一张纸
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
  // 首尾相接的位置：两道短竖线先占住，别把带画满
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
  // 鱼形的占位：三条一起落虚影，下一镜才照着勾
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
  // 炭条跟着正在拉的那根线跑：两道弦的起笔时间有重叠，所以先看还没走完的那一道，
  // 两道都收工了才把笔搁在带的右端
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
  // 上一镜的两道弦线还在，笔从肩线起头
  c.strokeStyle = 'rgba(43,38,34,0.60)';
  c.lineWidth = Math.max(b.h * 0.007, 1.2);
  c.beginPath();
  c.moveTo(cx - vw * 0.46, yA);
  c.lineTo(cx + vw * 0.46, yA);
  c.moveTo(cx - vw * 0.46, yB);
  c.lineTo(cx + vw * 0.46, yB);
  c.stroke();
  // 三条鱼一条接一条勾：笔从左往右走，勾完一条马上接着下一条
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
  // 颜料碟：投影 → 陶胎碟身 → 凹下去的颜料面 → 碟沿受光，最后碟心那圈水光一直在缓。
  // 原来只有一坨 accent 椭圆加一道白圈，摆在案板上读起来是地上一个洞，不是盛着颜料的碟子。
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
  // 鱼的大小和位置照搬上一镜勾线的那三条，彩才填得出形状
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
  // 三条鱼一排挨着填，从左到右一条填完才起下一条：
  // 黑彩压满鱼身 → 点鳞 → 挑鳍 → 留气眼鱼眼，四步都在同一条鱼身上走完
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
  // 出器身裁剪：笔和颜料碟摆在案板上，不该被盆本身裁掉
  c.restore();
  // 笔跟着当下正在做的事走：填彩压着湿彩下沿，点鳞移到这颗鳞上，完事才搁到带边
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
  // 装窑这一下放到开场：前一镜也是同一只彩陶盆，窑拱晚来两秒就看不出换镜了
  let load = ease(seg(b.ph, 0.16, 0.58));
  // 进窑后镜头退一点，窑口才装得下
  let sc = 1 - 0.12 * load;
  let top2 = ty - (ty - top) * sc;
  let vw2 = vw * sc;
  // 窑顶拱在 0.27h，正好盖住器口又不会顶到 HUD
  kiln(b, load, cx, ty + b.h * 0.02, b.w * 0.42, b.h * 0.44);
  table(b, ty, cx, vw2 * 0.40);
  halo(b, cx, (top2 + ty) * 0.5, b.h * 0.44);
  // 胎色随窑温压深一档
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
  // 上一镜一颗颗点出来的鳞、留的气眼、鱼眼、挑起来的鳍，进窑得整张带着，
  // 不能在这儿塌成一块黑剪影；只是跟着窑温一起压暗，别亮得像刚画完
  let heat = ease(seg(b.ph, 0.40, 0.98));
  let inkFish = mixHex(b.p.accent, b.p.deep, 0.22 * heat);
  let paleFish = mixHex(b.p.paper, body, 0.34 * heat);
  let fl2 = vw2 * 0.27;
  let fh2 = (yB - yA) * 0.60;
  for (let i = 0; i < FISH_N; i++) {
    fishOne(b, fishX(cx, vw2, i), cy, fl2, fh2, 1, 1, 1, 1, inkFish, paleFish);
  }
  c.restore();
  // 前半段是阴干：水汽慢慢往上走；进窑后换成烟
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

// —— 龙山蛋壳黑陶：踩揉去砂 → 上轮定中 → 开孔拉升 → 修坯压光 → 阴干渗碳 ——

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
  // 前半段：一块泥在台上被反复对折，折痕一道一道加
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
  // 后半段：撕开断面，纹理匀不匀一眼看到；砂粒挑出来扔掉
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
      // 断面上的平行纹理
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
    // 一颗砂粒被圈出来弹走
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

// 转盘：盘面 + 两道随转速走的虚线弧
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
  // 定中：偏心的摆动随进度收敛，最后一格正好压在轴上
  let set = ease(seg(b.ph, 0.10, 0.82));
  let wob = (1 - set) * b.w * 0.085 * Math.sin(b.t * 8.5);
  let sq = Math.sin(b.t * 3.6);
  let vw = b.w * (0.62 + 0.03 * sq);
  let hh = b.h * (0.22 + 0.02 * sq - 0.03 * set);
  drawVessel(b, profileOf('盆'), 0.10, cx + wob, ty - hh, ty, vw, b.p.base, false);
  hands(b, cx + wob, ty - hh - b.h * 0.012, vw * 0.11, 0.9);
  // 中心轴：定住了才画得出来
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
  // 转速线：两道从两侧掠过去
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
  // 壁厚越拉越薄：外轮廓 + 内轮廓之间那一条就是胎
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
  // 内膛必须裁在外轮廓里：内外两条轮廓都是按各自的高度区间铺的剖面，
  // 泥刚压扁的时候内轮廓反而比外轮廓宽，不裁就会看到一坨黑糊到器身外面
  smoothClosed(c, outer);
  c.clip();
  c.globalAlpha = 0.9;
  smoothClosed(c, inner);
  c.fillStyle = b.p.deep;
  c.fill();
  c.restore();
  // 开孔：孔沿从中心裂开，慢慢撑成器口
  let hole = ease(seg(b.ph, 0, 0.34));
  let mrx = Math.max(vw * 0.42 * hole, 1.2);
  let mry = Math.max(vw * 0.11 * hole, 1);
  // 孔里是暗的：填成纸色看着就像器口贴了张白纸
  c.fillStyle = mixHex(b.p.deep, '#141311', 0.45);
  c.beginPath();
  c.ellipse(cx, top, mrx, mry, 0, 0, Math.PI * 2);
  c.fill();
  // 远侧口沿受光，一圈亮边把"这是个开口的器"交代清楚
  c.strokeStyle = mixHex(b.p.base, b.p.paper, 0.55);
  c.lineWidth = Math.max(b.h * 0.006, 1.2);
  c.beginPath();
  c.ellipse(cx, top, mrx, mry, 0, Math.PI, Math.PI * 2);
  c.stroke();
  // 一圈只提一两毫米：旋纹跟着手往上爬（同样裁在器身里，别爬到轮盘上去）
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
  // 骨片压光：一道亮面慢慢往下推，压过的地方才发亮
  let shine = ease(seg(b.ph, 0.34, 0.86));
  if (shine > 0.01) {
    let y = top + (ty - top) * (0.16 + 0.70 * shine);
    // 亮面压得窄一档：0.12h 宽的白带横贯器腹，看着像器身上贴了条胶带
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
  // 网格纹：压光压到哪儿，纹就刻到哪儿——所以跟着亮面一起从上往下长
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
  // 竹刀刮余泥：刀口在器腹上下走，刮下来的泥条落在器外的案板上。
  // 整段都画在器身裁剪之外：刀是握在器前面的，泥条也不会顺着胎面往下淌
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
  // 窑拱一开场就得进来：上一镜（修坯）也是这一只罐子，晚出场两秒就分不出镜了
  let load = ease(seg(b.ph, 0.10, 0.50));
  let ink = ease(seg(b.ph, 0.30, 0.96));
  // 蛋壳陶的器形矮一档，窑拱才兜得住；rh 0.42 → 拱顶落在 0.27h
  kiln(b, load, cx, ty + b.h * 0.02, b.w * 0.40, b.h * 0.42);
  table(b, ty, cx, vw * 0.42);
  halo(b, cx, (top + ty) * 0.5, b.h * 0.44);
  // 还原焰渗碳：胎色从灰褐一路压到近黑，出窑才有那层金属光
  let body = mixHex(b.p.base, '#232220', ink);
  let prof = profileOf('罐');
  let pts = drawVessel(b, prof, 1, cx, top, ty, vw, body, true);
  c.save();
  smoothClosed(c, pts);
  c.clip();
  // 网格纹留着（上一镜刻的），渗碳后换成亮灰：直接拿 b.p 会被近黑的胎吃掉，
  // 所以这里换一套「亮灰纹样」的配色喂给同一份 grid 画法。
  c.save();
  c.globalAlpha = 0.5;
  let gp: Palette = { base: body, deep: '#1B1A18', accent: '#B9B4A8', ink: '#EDE7DC',
    paper: '#D8D2C6' };
  grid(c, gp, cx - vw * 0.5, cx + vw * 0.5, top + (ty - top) * 0.34,
    top + (ty - top) * 0.60, 2);
  c.restore();
  // 金属光：一道斜的高光扫过器身，只在渗碳到位之后出现
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
  // 阴干的水汽 → 装窑的烟 → 窑口的火星
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
      // 火星沿着窑口两侧往上飘，别从器身正中间冒——那看着像胎上长了斑点
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

// HUD 上那个角标：这两条教程的画面是按步骤量身画的，用通用的「泥料/成型」分类
// 会跟画面对不上，直接给每镜一个正在发生的动作名。
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

// 一条教程五个镜头，下标越界一律回落到最后一镜，别让画布空在那儿
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
