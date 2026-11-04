import { router } from '@kit.ArkUI';
import { ContentRepo } from '../service/ContentRepo';
import { SiteRepo } from '../service/SiteRepo';
import { Course, CourseStep } from '../model/Models';
import { fs, INK, SUB, LINE, CLAY, paletteOf, Palette } from '../common/Theme';
import { hasCourseShot, drawCourseShot, courseTag, ShotBox } from '../common/CourseScenes';
import { drawPaper } from '../common/PotteryArt';
import { params, goPottery, goDetail } from '../common/Nav';

// 一镜的时长与转场时长：打开页面就自己往下播，镜头之间用推入+叠化连起来，
// 播到最后一镜回卷到第一镜，所以看起来是一段连续的影像而不是一张插图。
const SHOT_MS: number = 3400;
const FADE_MS: number = 430;
const TICK_MS: number = 33;

function kindOf(t: string, i: number): string {
  if (t.indexOf('窑') >= 0 || t.indexOf('烧') >= 0 || t.indexOf('浇注') >= 0) {
    return 'fire';
  }
  if (t.indexOf('绘') >= 0 || t.indexOf('纹') >= 0 || t.indexOf('彩') >= 0 || t.indexOf('墨') >= 0
    || t.indexOf('釉') >= 0 || t.indexOf('稿') >= 0 || t.indexOf('画') >= 0 || t.indexOf('刻') >= 0
    || t.indexOf('拓') >= 0 || t.indexOf('点睛') >= 0) {
    return 'paint';
  }
  if (t.indexOf('修') >= 0 || t.indexOf('削') >= 0 || t.indexOf('刮') >= 0 || t.indexOf('磨') >= 0
    || t.indexOf('压光') >= 0 || t.indexOf('范') >= 0 || t.indexOf('凹') >= 0) {
    return 'trim';
  }
  if (t.indexOf('轮') >= 0 || t.indexOf('拉') >= 0 || t.indexOf('叠') >= 0 || t.indexOf('接') >= 0
    || t.indexOf('出跳') >= 0 || t.indexOf('斗') >= 0 || t.indexOf('用材') >= 0) {
    return 'throw';
  }
  if (t.indexOf('泥') >= 0 || t.indexOf('揉') >= 0 || t.indexOf('练') >= 0 || t.indexOf('纸') >= 0
    || t.indexOf('清理') >= 0 || t.indexOf('塑') >= 0) {
    return 'knead';
  }
  let mods: string[] = ['knead', 'throw', 'trim', 'paint', 'fire'];
  return mods[i % mods.length];
}

@Entry
@Component
struct PlayerPage {
  // 字号档位变了要整页重画：不持有这行，切档后这一页还是老字号
  @StorageLink('textScale') ts: number = 1;
  @State course: Course | undefined = undefined;
  @State idx: number = 0;
  @State playing: boolean = false;
  // 换镜时说明卡跟着淡入推一点，跟画面的推入叠化是同一口气
  @State cardIn: number = 1;
  private timer: number = -1;
  // 上一镜的下标，只在叠化那 430ms 里参与成像
  private prev: number = -1;
  // 本镜已走的时间和转场已走的时间：暂停时都不推进，画面就停在当下
  private shotMs: number = 0;
  private fadeMs: number = FADE_MS;
  // 全局时钟（秒），给揉压、转速、火苗这些往复动作当相位
  private clock: number = 0;
  private lastBeat: number = 0;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  // 量身画的那十镜每次都要收 (画布, 配色, 宽高, 本镜进度, 时钟)。
  // 节拍器 33ms 一次，一帧新建一个对象十秒就是三百个，所以这只盒子留一份反复填。
  private box: ShotBox | undefined = undefined;

  aboutToAppear(): void {
    let p = params();
    let id = p.courseId ?? '';
    this.course = ContentRepo.get().courseOf(id);
    // 落地即开播，不用先按一下播放
    if (this.total() > 0) {
      this.playing = true;
    }
    this.startLoop();
  }

  aboutToDisappear(): void {
    this.stopLoop();
  }

  // 从这一页再往下钻（比如再点一条教程）时，本页只是被盖住、不会走 aboutToDisappear，
  // 30fps 的节拍要是继续在后台画就是白烧 CPU，所以藏起来就停、露出来再接上。
  onPageHide(): void {
    this.stopLoop();
  }

  onPageShow(): void {
    if (this.total() > 0) {
      this.startLoop();
    }
  }

  startLoop(): void {
    if (this.timer >= 0) {
      return;
    }
    this.lastBeat = Date.now();
    this.timer = setInterval((): void => {
      this.tick();
    }, TICK_MS);
  }

  stopLoop(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  // 每一拍只做两件事：推进时间、把画面重画一遍。状态位（idx/cardIn）只在换镜那一拍动，
  // 免得 30fps 的节拍把整棵组件树带着重绘。
  tick(): void {
    let now = Date.now();
    let dt = now - this.lastBeat;
    this.lastBeat = now;
    if (dt > 200) {
      dt = 200;
    }
    if (this.fadeMs < FADE_MS) {
      this.fadeMs = Math.min(FADE_MS, this.fadeMs + dt);
    }
    if (this.playing) {
      this.clock = this.clock + dt / 1000;
      this.shotMs = this.shotMs + dt;
      if (this.shotMs >= SHOT_MS) {
        this.advance();
      }
    }
    this.paint();
  }

  steps(): CourseStep[] {
    return this.course?.steps ?? [];
  }

  total(): number {
    return this.steps().length;
  }

  stepIdx(): number {
    let st = this.steps();
    if (st.length === 0) {
      return 0;
    }
    return this.idx < st.length ? this.idx : st.length - 1;
  }

  stepTitle(): string {
    let st = this.steps();
    return st.length === 0 ? '' : st[this.stepIdx()].t;
  }

  stepBody(): string {
    let st = this.steps();
    return st.length === 0 ? '' : st[this.stepIdx()].d;
  }

  coverText(): string {
    let co = this.course;
    return co === undefined ? '课程影像' : co.title;
  }

  srcText(): string {
    let co = this.course;
    return co === undefined ? '' : co.source;
  }

  paletteKey(): string {
    let co = this.course;
    return co === undefined ? 'yangshao' : co.palette;
  }

  // 换镜：记下从哪一镜过来，本镜时间归零让叠化重走一遍，说明卡跟着淡入
  private enter(to: number): void {
    let from = this.stepIdx();
    this.prev = from;
    this.shotMs = 0;
    this.fadeMs = 0;
    this.cardIn = 0;
    animateTo({ duration: 300, curve: Curve.EaseOut }, (): void => {
      this.idx = to;
      this.cardIn = 1;
    });
  }

  advance(): void {
    let n = this.total();
    if (n === 0) {
      return;
    }
    // 走完最后一镜卷回第一镜，演示时这段就是循环放的
    this.enter((this.stepIdx() + 1) % n);
  }

  rewind(): void {
    if (this.stepIdx() > 0) {
      this.enter(this.stepIdx() - 1);
    }
  }

  forward(): void {
    if (this.stepIdx() < this.total() - 1) {
      this.enter(this.stepIdx() + 1);
    }
  }

  jump(i: number): void {
    if (i !== this.stepIdx() && i < this.total()) {
      this.enter(i);
    }
  }

  togglePlay(): void {
    this.playing = !this.playing;
  }

  // —— 画布里的器型与纹样，都是按 ph（本镜进度）和 t（时钟）现算的 ——
  private vessel(c: CanvasRenderingContext2D, p: Palette, cx: number, cy: number,
    rw: number, rh: number): void {
    c.fillStyle = p.base;
    c.strokeStyle = p.deep;
    c.lineWidth = Math.max(rw * 0.06, 1.2);
    c.beginPath();
    c.moveTo(cx - rw * 0.42, cy - rh);
    c.lineTo(cx + rw * 0.42, cy - rh);
    c.bezierCurveTo(cx + rw, cy - rh * 0.5, cx + rw, cy + rh * 0.5, cx + rw * 0.5, cy + rh);
    c.lineTo(cx - rw * 0.5, cy + rh);
    c.bezierCurveTo(cx - rw, cy + rh * 0.5, cx - rw, cy - rh * 0.5, cx - rw * 0.42, cy - rh);
    c.closePath();
    c.fill();
    c.stroke();
  }

  // 漩涡纹：frac 控制画到几分之一圈，镜头进度就是一条条线自己绕出来的过程
  private spiral(c: CanvasRenderingContext2D, p: Palette, sx: number, sy: number, r: number,
    frac: number): void {
    if (frac <= 0.01) {
      return;
    }
    c.strokeStyle = p.accent;
    c.beginPath();
    let max = Math.PI * 4 * frac;
    let first = true;
    for (let a = 0; a <= max; a += 0.18) {
      let rr = r * (1 - a / (Math.PI * 4.4));
      let px = sx + rr * Math.cos(a);
      let py = sy + rr * Math.sin(a);
      if (first) {
        c.moveTo(px, py);
        first = false;
      } else {
        c.lineTo(px, py);
      }
    }
    c.stroke();
    if (!first) {
      let rr = r * (1 - max / (Math.PI * 4.4));
      c.fillStyle = p.accent;
      c.beginPath();
      c.arc(sx + rr * Math.cos(max), sy + rr * Math.sin(max), Math.max(r * 0.10, 1.4), 0, Math.PI * 2);
      c.fill();
    }
  }

  // 揉泥：泥团在掌下一压一回弹，左右两坨跟着节拍轻跳
  private scKnead(c: CanvasRenderingContext2D, p: Palette, w: number, h: number,
    g: number, ph: number, t: number): void {
    let sq = Math.sin(t * 4.2);
    let rx = w * (0.185 + 0.035 * ph) - w * 0.014 * sq;
    let ry = h * (0.115 + 0.02 * ph) + h * 0.014 * sq;
    c.fillStyle = p.deep;
    c.beginPath();
    c.ellipse(w * 0.5, g - ry, rx, ry, 0, 0, Math.PI * 2);
    c.fill();
    for (let i = 0; i < 2; i++) {
      let sx = i === 0 ? w * 0.24 : w * 0.76;
      let hop = Math.abs(Math.sin(t * 2.1 + i * 1.7)) * h * 0.035;
      c.beginPath();
      c.ellipse(sx, g - h * 0.03 - hop, w * 0.065, h * 0.045, 0, 0, Math.PI * 2);
      c.fill();
    }
    // 两只手：按下去时弧线收拢，抬起时摊开
    c.strokeStyle = p.ink;
    c.lineWidth = Math.max(h * 0.012, 1.2);
    let press = (sq + 1) / 2;
    for (let i = -1; i <= 1; i++) {
      let cx = w * 0.5 + i * w * 0.09;
      let cy = g - ry * (1.02 + 0.16 * press);
      let rr = w * (0.052 + 0.016 * (1 - press));
      c.beginPath();
      c.arc(cx, cy, rr, Math.PI * (0.15 + 0.1 * press), Math.PI * (0.85 - 0.1 * press));
      c.stroke();
    }
    // 上方那道肩线随手腕上下带
    c.strokeStyle = 'rgba(43,38,34,0.55)';
    c.beginPath();
    c.moveTo(w * 0.30, h * 0.22 + h * 0.02 * sq);
    c.quadraticCurveTo(w * 0.5, h * 0.10 + h * 0.02 * sq, w * 0.70, h * 0.22 + h * 0.02 * sq);
    c.stroke();
  }

  // 拉坯：转台刻痕一直在转，坯体随镜头进度长高、口沿收窄
  private scThrow(c: CanvasRenderingContext2D, p: Palette, w: number, h: number,
    g: number, ph: number, t: number): void {
    c.fillStyle = 'rgba(43,38,34,0.30)';
    c.beginPath();
    c.ellipse(w * 0.5, g, w * 0.30, h * 0.06, 0, 0, Math.PI * 2);
    c.fill();
    let rh = h * (0.125 + 0.105 * ph);
    let rw = w * (0.205 - 0.035 * ph);
    let vy = g - rh;
    this.vessel(c, p, w * 0.5, vy, rw, rh);
    // 盘面上两道旋转的虚线弧
    c.strokeStyle = p.accent;
    c.lineWidth = Math.max(h * 0.010, 1.2);
    c.setLineDash([h * 0.03, h * 0.03]);
    for (let i = 0; i < 2; i++) {
      let a = t * (2.4 + i * 0.5);
      c.beginPath();
      c.ellipse(w * 0.5, g - h * 0.02, w * (0.26 + i * 0.07), h * (0.07 + i * 0.02),
        0, Math.PI * 1.05 + a % 6.28, Math.PI * 1.95 + a % 6.28);
      c.stroke();
    }
    c.setLineDash([]);
    // 旋纹跟着高度往上爬
    c.strokeStyle = p.deep;
    c.lineWidth = Math.max(h * 0.006, 1);
    for (let i = 0; i < 4; i++) {
      let yy = g - rh * (0.25 + i * 0.22) - h * 0.02 * (t * 0.9 % 1);
      if (yy < vy - rh * 0.9) {
        continue;
      }
      c.beginPath();
      c.moveTo(w * 0.5 - rw * 0.46, yy);
      c.quadraticCurveTo(w * 0.5, yy + h * 0.012, w * 0.5 + rw * 0.46, yy);
      c.stroke();
    }
    // 高光沿器身扫过去，一眼看出它在转
    c.strokeStyle = 'rgba(255,255,255,0.42)';
    c.lineWidth = Math.max(rw * 0.10, 2);
    let hx = w * 0.5 + rw * 0.5 * Math.sin(t * 2.6);
    c.beginPath();
    c.moveTo(hx, vy - rh * 0.82);
    c.lineTo(hx, g - rh * 0.12);
    c.stroke();
    // 两只手贴着最上沿，随坯体一起长高
    c.strokeStyle = 'rgba(43,38,34,0.50)';
    c.lineWidth = Math.max(h * 0.014, 1.4);
    let hy = vy + h * 0.01 * Math.sin(t * 3.1);
    c.beginPath();
    c.arc(w * 0.30, hy, w * 0.09, Math.PI * 1.3, Math.PI * 1.9);
    c.stroke();
    c.beginPath();
    c.arc(w * 0.70, hy, w * 0.09, Math.PI * 1.1, Math.PI * 1.7);
    c.stroke();
  }

  // 修整：刮刀上下走，修出来的弦纹一圈圈补上，泥屑越刮越多
  private scTrim(c: CanvasRenderingContext2D, p: Palette, w: number, h: number,
    g: number, ph: number, t: number): void {
    c.fillStyle = 'rgba(43,38,34,0.22)';
    c.beginPath();
    c.ellipse(w * 0.5, g, w * 0.26, h * 0.05, 0, 0, Math.PI * 2);
    c.fill();
    this.vessel(c, p, w * 0.46, g - h * 0.22, w * 0.19, h * 0.22);
    let lines = 1 + Math.floor(ph * 4);
    c.strokeStyle = p.deep;
    c.lineWidth = Math.max(h * 0.008, 1);
    for (let i = 0; i < lines; i++) {
      let wob = h * 0.006 * Math.sin(t * 2.2 + i);
      let y0 = g - h * (0.34 - i * 0.06) + wob;
      c.beginPath();
      c.moveTo(w * 0.36, y0);
      c.lineTo(w * 0.54, y0 - h * 0.02);
      c.stroke();
    }
    // 刮刀沿器身上下走刀，刀头压到当前那一圈
    let sweep = (Math.sin(t * 1.8) + 1) / 2;
    let ty = g - h * (0.10 + 0.26 * sweep);
    c.strokeStyle = '#5A4030';
    c.lineWidth = Math.max(h * 0.016, 1.6);
    c.beginPath();
    c.moveTo(w * 0.84, ty - h * 0.16);
    c.lineTo(w * 0.56, ty);
    c.stroke();
    c.fillStyle = p.deep;
    c.beginPath();
    c.arc(w * 0.56, ty, Math.max(w * 0.014, 1.6), 0, Math.PI * 2);
    c.fill();
    // 落下来的泥屑：越刮越多，各自歪一点
    let chips = 1 + Math.floor(ph * 5);
    for (let i = 0; i < chips; i++) {
      let drop = (t * 0.7 + i * 0.19) % 1;
      c.beginPath();
      c.ellipse(w * (0.60 + i * 0.05), g - h * (0.05 - 0.04 * drop) + h * 0.02 * drop,
        w * 0.020, h * 0.012, 0.5 + i * 0.3 + drop, 0, Math.PI * 2);
      c.fill();
    }
  }

  // 上彩：两道色带先拉开，再顺着把漩涡纹一笔笔绕出来，笔尖跟着走
  private scPaint(c: CanvasRenderingContext2D, p: Palette, w: number, h: number,
    g: number, ph: number, t: number): void {
    this.vessel(c, p, w * 0.5, g - h * 0.22, w * 0.22, h * 0.24);
    let by = g - h * 0.30;
    let span = 0.12 + 0.24 * Math.min(1, ph * 1.4);
    c.strokeStyle = p.accent;
    c.lineWidth = Math.max(h * 0.012, 1.2);
    c.beginPath();
    c.moveTo(w * (0.5 - span), by - h * 0.06);
    c.lineTo(w * (0.5 + span), by - h * 0.06);
    c.moveTo(w * (0.5 - span), by + h * 0.06);
    c.lineTo(w * (0.5 + span), by + h * 0.06);
    c.stroke();
    let f1 = Math.min(1, Math.max(0, ph * 1.6));
    let f2 = Math.min(1, Math.max(0, ph * 1.6 - 0.55));
    this.spiral(c, p, w * 0.40, by, h * 0.05, f1);
    this.spiral(c, p, w * 0.58, by, h * 0.05, f2);
    // 笔杆：笔尖停在正在画的那一圈端点上，手腕带着轻微抖动
    let tipF = f2 < 1 ? f2 : f1;
    let tipR = h * 0.05 * (1 - tipF * 4 / 4.4);
    let tx = (f2 < 1 ? w * 0.58 : w * 0.40) + tipR;
    let ty = by + tipR * Math.sin(t * 4.4);
    c.strokeStyle = '#5A4030';
    c.lineWidth = Math.max(h * 0.014, 1.4);
    c.beginPath();
    c.moveTo(w * 0.86, ty - h * 0.16);
    c.lineTo(tx, ty);
    c.stroke();
    c.fillStyle = p.accent;
    c.beginPath();
    c.moveTo(tx, ty);
    c.lineTo(tx - w * 0.03, ty + h * 0.01);
    c.lineTo(tx, ty + h * 0.03);
    c.closePath();
    c.fill();
  }

  // 入窑：火苗一柱柱抖，膛光随火候明暗，烟从窑口往上飘
  private scFire(c: CanvasRenderingContext2D, p: Palette, w: number, h: number,
    g: number, ph: number, t: number): void {
    c.fillStyle = p.deep;
    c.beginPath();
    c.moveTo(w * 0.22, g);
    c.lineTo(w * 0.22, h * 0.30);
    c.quadraticCurveTo(w * 0.5, h * 0.10, w * 0.78, h * 0.30);
    c.lineTo(w * 0.78, g);
    c.closePath();
    c.fill();
    let pulse = (Math.sin(t * 3.4) + 1) / 2;
    let mg: CanvasGradient = c.createLinearGradient(0, g, 0, h * 0.42);
    mg.addColorStop(0, '#F2A44C');
    mg.addColorStop(Math.min(0.9, 0.45 + 0.2 * ph + 0.1 * pulse), '#A6553D');
    mg.addColorStop(1, '#8E4530');
    c.fillStyle = mg;
    c.beginPath();
    c.moveTo(w * 0.36, g);
    c.lineTo(w * 0.36, h * 0.56);
    c.quadraticCurveTo(w * 0.5, h * 0.44, w * 0.64, h * 0.56);
    c.lineTo(w * 0.64, g);
    c.closePath();
    c.fill();
    // 三簇火苗各自抖，中间那簇最高
    c.fillStyle = '#F6E1B0';
    for (let i = -1; i <= 1; i++) {
      let fx = w * 0.5 + i * w * 0.09;
      let base = h * (0.16 - Math.abs(i) * 0.04);
      let fl = base + h * 0.030 * Math.sin(t * 7.1 + i * 1.9) + h * 0.02 * ph;
      c.beginPath();
      c.moveTo(fx - w * 0.03, g);
      c.quadraticCurveTo(fx, g - fl * 1.35, fx + w * 0.03, g);
      c.closePath();
      c.fill();
    }
    // 火星从窑口往上冒，走到顶就断，接上再冒
    c.fillStyle = 'rgba(246,164,76,0.85)';
    for (let i = 0; i < 4; i++) {
      let up = (t * 0.55 + i * 0.25) % 1;
      let sx = w * (0.44 + 0.12 * ((i % 3) / 2)) + w * 0.02 * Math.sin(t * 3 + i);
      c.beginPath();
      c.arc(sx, h * 0.44 - h * 0.30 * up, Math.max(w * (0.008 - 0.004 * up), 1.2), 0, Math.PI * 2);
      c.fill();
    }
    // 烟：三道人字往上抬，越往上越散
    c.strokeStyle = 'rgba(43,38,34,0.35)';
    c.lineWidth = Math.max(h * 0.008, 1);
    for (let i = 0; i < 3; i++) {
      let rise = (t * 0.22 + i * 0.18) % 1;
      let yy = h * (0.24 - i * 0.05) - h * 0.16 * rise;
      let spread = h * 0.03 * (1 + rise);
      c.beginPath();
      c.moveTo(w * 0.40, yy);
      c.quadraticCurveTo(w * 0.46, yy - spread, w * 0.52, yy);
      c.quadraticCurveTo(w * 0.58, yy + spread, w * 0.64, yy);
      c.stroke();
    }
  }

  private scene(c: CanvasRenderingContext2D, p: Palette, w: number, h: number, kind: string,
    ph: number, t: number): void {
    let ground = h * 0.78;
    // 地平线跟着时钟轻轻起伏，整幅画不会像贴上去的死图
    c.strokeStyle = 'rgba(43,38,34,0.30)';
    c.lineWidth = Math.max(h * 0.006, 1);
    c.beginPath();
    c.moveTo(w * 0.06, ground + h * 0.006 * Math.sin(t * 1.4));
    c.lineTo(w * 0.94, ground - h * 0.006 * Math.sin(t * 1.4));
    c.stroke();
    if (kind === 'knead') {
      this.scKnead(c, p, w, h, ground, ph, t);
    } else if (kind === 'throw') {
      this.scThrow(c, p, w, h, ground, ph, t);
    } else if (kind === 'trim') {
      this.scTrim(c, p, w, h, ground, ph, t);
    } else if (kind === 'paint') {
      this.scPaint(c, p, w, h, ground, ph, t);
    } else {
      this.scFire(c, p, w, h, ground, ph, t);
    }
  }

  private kindLabel(kind: string): string {
    if (kind === 'knead') {
      return '泥料';
    }
    if (kind === 'throw') {
      return '成型';
    }
    if (kind === 'trim') {
      return '修整';
    }
    if (kind === 'paint') {
      return '纹样';
    }
    return '火候';
  }

  private tag(i: number): string {
    let co = this.course;
    if (co !== undefined && hasCourseShot(co.id)) {
      return courseTag(co.id, i);
    }
    return this.kindLabel(kindOf(this.steps()[i].t, i));
  }

  // 画布顶部的镜号与本镜进度条，底部那一行是分镜总进度
  private drawHud(c: CanvasRenderingContext2D, w: number, h: number): void {
    let st = this.steps();
    let i = this.stepIdx();
    let ph = Math.min(1, this.shotMs / SHOT_MS);
    c.fillStyle = 'rgba(43,38,34,0.62)';
    // 单位写 vp 不写 px：画布坐标是 vp，可 font 里的裸数字 ArkUI 按物理像素吃，
    // 高分屏上差一个屏幕密度（模拟器 3.5 倍），这两行字会缩成看不清的一小坨。
    // 浏览器 harness 不认 vp，.tmp 里那套预览拼 harness 时要连这一处一起换回 px。
    c.font = `${Math.round(h * 0.05)}vp sans-serif`;
    c.textAlign = 'left';
    c.textBaseline = 'top';
    c.fillText(`分镜 ${i + 1} / ${st.length} · ${this.tag(i)}`, w * 0.05, h * 0.045);
    c.font = `${Math.round(h * 0.062)}vp sans-serif`;
    c.fillStyle = 'rgba(43,38,34,0.86)';
    c.fillText(st[i].t, w * 0.05, h * 0.12);
    // 本镜进度：压在最底下的一条，走到头就换镜
    c.fillStyle = 'rgba(43,38,34,0.14)';
    c.fillRect(w * 0.05, h - h * 0.045, w * 0.90, Math.max(h * 0.012, 2));
    c.fillStyle = CLAY;
    c.fillRect(w * 0.05, h - h * 0.045, w * 0.90 * ph, Math.max(h * 0.012, 2));
  }

  // 画第 i 镜：c01 鱼纹盆、c02 蛋壳陶走 CourseScenes 里按这条教程量身画的十镜，
  // 其余课程（讲读、影像、别的手作）还是回落到通用的五类场景。
  // 转场时上一镜和本镜都调这里，所以两条链路共用同一个裁剪/叠化。
  private drawShot(i: number, ph: number, t: number): void {
    let c = this.ctx;
    let w = c.width;
    let h = c.height;
    let co = this.course;
    if (co === undefined) {
      return;
    }
    let p = paletteOf(co.palette);
    if (!hasCourseShot(co.id)) {
      this.scene(c, p, w, h, kindOf(this.steps()[i].t, i), ph, t);
      return;
    }
    let b = this.box;
    if (b === undefined) {
      b = this.makeBox(c, p, w, h, ph, t);
      this.box = b;
    } else {
      b.c = c;
      b.p = p;
      b.w = w;
      b.h = h;
      b.ph = ph;
      b.t = t;
    }
    drawCourseShot(co.id, i, b);
  }

  // 单独一个建盒子的方法：ArkTS 的对象字面量要贴着声明的接口类型写才认，
  // 塞进 ShotBox | undefined 那个联合类型里它会挑刺。
  private makeBox(c: CanvasRenderer, p: Palette, w: number, h: number,
    ph: number, t: number): ShotBox {
    let b: ShotBox = { c: c, p: p, w: w, h: h, ph: ph, t: t };
    return b;
  }

  private paint(): void {
    let c = this.ctx;
    let w = c.width;
    let h = c.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    let co = this.course;
    if (co === undefined) {
      return;
    }
    let st = this.steps();
    if (st.length === 0) {
      return;
    }
    let p = paletteOf(co.palette);
    c.globalAlpha = 1;
    c.clearRect(0, 0, w, h);
    // 纸底走 PotteryArt 那一份：渐变下端掺过 base，器物（就是 base 那一档）才从背景里站出来。
    // 原来这里直接 paper→base 铺满，等于让陶器和它自己的底色同色，下小半截是糊的。
    drawPaper(c, p, co.id.length, w, h);
    let i = this.stepIdx();
    let ph = Math.min(1, this.shotMs / SHOT_MS);
    let t = this.clock;
    let f = Math.min(1, this.fadeMs / FADE_MS);
    // 换镜：量身画的十镜前后是同一只盆、同一张案板，纯叠化会糊出一对轮廓，
    // 所以这两条教程走"推镜"——本镜实打实从右边推进来，上一镜边往左退边淡出；
    // 通用场景是五张互不相干的插图，轻推 + 叠化就够了。
    let slide = hasCourseShot(co.id);
    let push = slide ? w * 0.30 : w * 0.06;
    // 叠化 + 横向推入：上一镜带着透明度退场，本镜从右侧推进来，两镜衔接是连续的
    if (f < 1 && this.prev >= 0 && this.prev !== i) {
      c.save();
      c.globalAlpha = slide ? (1 - f) * 0.9 : 1 - f;
      c.translate(-push * f, 0);
      this.drawShot(this.prev, 1, t);
      c.restore();
      c.save();
      c.globalAlpha = slide ? 1 : f;
      c.translate(push * (1 - f), 0);
      this.drawShot(i, ph, t);
      c.restore();
      c.globalAlpha = 1;
    } else {
      this.drawShot(i, ph, t);
    }
    this.drawHud(c, w, h);
  }

  build() {
    Column() {
      // 页头贴着最顶上：返回 + 居中标题，不留整块空白
      Row({ space: 10 }) {
        Text('‹')
          .fontSize(fs(this.ts, 20))
          .fontColor(INK)
          .width(30)
          .height(30)
          .textAlign(TextAlign.Center)
          .backgroundColor('rgba(255,255,255,0.72)')
          .borderRadius(15)
          .onClick((): void => {
            this.stopLoop();
            router.back();
          })
        Text(this.coverText())
          .fontSize(fs(this.ts, 17))
          .fontColor(INK)
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.course === undefined ? '' : `${this.course.cat}`)
          .fontSize(fs(this.ts, 11))
          .fontColor(CLAY)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 6, bottom: 4 })

      if (this.course === undefined) {
        Column({ space: 12 }) {
          Text('课程不存在').fontSize(fs(this.ts, 16)).fontColor(INK)
          Button('返回')
            .backgroundColor($r('app.color.line')).fontColor(INK)
            .onClick((): void => {
              router.back();
            })
        }
        .width('100%')
        .margin({ top: 80 })
        .alignItems(HorizontalAlign.Center)
      } else {
        Scroll() {
          Column({ space: 10 }) {
            // 画面就是这页的第一块内容，上面不留空档
            Column({ space: 0 }) {
              Canvas(this.ctx)
                .width('100%')
                .height(300)
                .backgroundColor(paletteOf(this.paletteKey()).paper)
                .onReady((): void => {
                  this.startLoop();
                  this.paint();
                })
            }
            .width('100%')
            .borderRadius(14)
            .clip(true)
            .backgroundColor($r('app.color.card_bg'))

            Column({ space: 8 }) {
              Row({ space: 10 }) {
                Text(this.playing ? '▮▮' : '▶')
                  .fontSize(fs(this.ts, 15)).fontColor(Color.White)
                  .width(40).height(34).borderRadius(8)
                  .backgroundColor(CLAY)
                  .textAlign(TextAlign.Center)
                  .onClick((): void => {
                    this.togglePlay();
                  })
                Text('‹ 上一镜')
                  .fontSize(fs(this.ts, 12)).fontColor(INK)
                  .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                  .borderRadius(8)
                  .backgroundColor($r('app.color.line'))
                  .onClick((): void => {
                    this.rewind();
                  })
                Text('下一镜 ›')
                  .fontSize(fs(this.ts, 12)).fontColor(INK)
                  .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                  .borderRadius(8)
                  .backgroundColor($r('app.color.line'))
                  .onClick((): void => {
                    this.forward();
                  })
                Blank()
                Text(this.playing ? '连播中 · 循环' : '已暂停')
                  .fontSize(fs(this.ts, 10)).fontColor(SUB)
              }
              .width('100%')

              Row({ space: 4 }) {
                ForEach(this.steps(), (s: CourseStep, i: number): void => {
                  Column()
                    .layoutWeight(1)
                    .height(6)
                    .borderRadius(3)
                    .backgroundColor(i === this.idx ? CLAY : LINE)
                    .onClick((): void => {
                      this.jump(i);
                    })
                }, (s: CourseStep, i: number): string => 'seg_' + i)
              }
              .width('100%')

              // 说明卡：换镜时淡入推进，跟画面的推入叠化同步
              Column({ space: 6 }) {
                Text(this.stepTitle())
                  .fontSize(fs(this.ts, 19)).fontColor(INK).fontWeight(FontWeight.Bold).width('100%')
                Text(this.stepBody())
                  .fontSize(fs(this.ts, 14)).fontColor(INK).lineHeight(fs(this.ts, 23)).width('100%')
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(12)
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(12)
              .opacity(this.cardIn)
              .translate({ x: (1 - this.cardIn) * 14 })
            }
            .width('100%')

            Column({ space: 2 }) {
              Text('全部分镜').fontSize(fs(this.ts, 13)).fontColor(INK).fontWeight(FontWeight.Medium)
                .width('100%').padding({ bottom: 6 })
              ForEach(this.steps(), (s: CourseStep, i: number): void => {
                Row({ space: 8 }) {
                  Text(`${i + 1}`)
                    .fontSize(fs(this.ts, 11)).fontColor(i === this.idx ? Color.White : SUB)
                    .width(20).height(20).borderRadius(10)
                    .backgroundColor(i === this.idx ? CLAY : $r('app.color.page_bg'))
                    .textAlign(TextAlign.Center)
                  Column({ space: 2 }) {
                    Text(s.t).fontSize(fs(this.ts, 13)).fontColor(INK).width('100%')
                    Text(s.d).fontSize(fs(this.ts, 10)).fontColor(SUB).width('100%').maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')
                .padding({ top: 7, bottom: 7 })
                .onClick((): void => {
                  this.jump(i);
                })
              }, (s: CourseStep, i: number): string => 'row_' + i + '_' + s.t.length)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 12, right: 12, bottom: 6 })
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(12)

            Row({ space: 10 }) {
              Button('跟着做一遍')
                .fontSize(fs(this.ts, 13)).backgroundColor(CLAY).fontColor(Color.White)
                .onClick((): void => {
                  this.stopLoop();
                  goPottery();
                })
              if (this.siteName().length > 0) {
                Button('去遗址看看')
                  .fontSize(fs(this.ts, 13)).backgroundColor($r('app.color.line')).fontColor(INK)
                  .onClick((): void => {
                    let co = this.course;
                    if (co !== undefined) {
                      this.stopLoop();
                      goDetail(co.siteId);
                    }
                  })
              }
              Blank()
            }
            .width('100%')

            Text(`课程线索来源：${this.srcText()}`)
              .fontSize(fs(this.ts, 10)).fontColor(SUB).width('100%')
          }
          .width('100%')
          .padding({ left: 14, right: 14, bottom: 14 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: 2 })
    .backgroundColor($r('app.color.page_bg'))
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }

  private siteName(): string {
    let co = this.course;
    if (co === undefined) {
      return '';
    }
    let s = SiteRepo.get().byId(co.siteId);
    return s === undefined ? '' : s.name;
  }
}
