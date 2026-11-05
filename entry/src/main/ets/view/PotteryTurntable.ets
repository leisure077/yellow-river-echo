import { image } from '@kit.ImageKit';
import { LengthMetricsUnit } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fs, paletteOf, Palette, withAlpha, hexLum, SUB } from '../common/Theme';
import { drawBand, drawPaper, drawPedestal, drawWord, tracePath } from '../common/PotteryArt';
import { ShapeMeta, TurntableFrames, TurntableIndex } from '../service/TurntableFrames';
import { PotteryCanvas } from './PotteryCanvas';

const SLABS: number = 8;
const SPIN_MS: number = 120;
const RESUME_MS: number = 2500;

const STRIP_SS: number = 3;

const FRAME_LUM: number = 179;
const TINT_TOL: number = 22;
const TINT_MIN: number = 0.62;
const TINT_MAX: number = 0.94;

@Component
export struct PotteryTurntable {
  @Prop @Watch('onParam') shape: string = '罐';
  @Prop @Watch('onParam') motif: string = '鱼纹';
  @Prop @Watch('onParam') glaze: string = 'yangshao';
  @Prop @Watch('onParam') pedestal: string = '素台';
  @Prop @Watch('onParam') word: string = '';
  @Prop @Watch('onParam') seed: number = 0;
  
  @StorageLink('textScale') ts: number = 1;
  
  @State ready: boolean = false;
  @State hint: boolean = true;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private c2d: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private idx: TurntableIndex | null = null;
  private meta: ShapeMeta | null = null;
  private cur: image.PixelMap | null = null;
  private fw: number = 512;
  private fh: number = 640;
  private degStep: number = 15;
  private angle: number = 0;
  private fitScale: number = 0;
  private seq: number = 0;
  private lastKey: string = '';
  private dragging: boolean = false;
  private dragBase: number = 0;
  private idleAt: number = 0;
  private spin: number = -1;
  
  private strip: image.PixelMap | null = null;
  private stripKey: string = '';
  
  private bandCtx: OffscreenCanvasRenderingContext2D | null = null;
  private bandW: number = 0;
  private bandH: number = 0;
  private bandPm: image.PixelMap | null = null;

  aboutToAppear(): void {
    let svc = TurntableFrames.get();
    this.idx = svc.loadIndex(getContext(this) as common.UIAbilityContext);
    this.meta = svc.metaOf(this.shape);
    let m = this.meta;
    if (this.idx !== null && m !== null) {
      this.fw = this.idx.canvas[0];
      this.fh = this.idx.canvas[1];
      this.degStep = this.idx.degStep > 0 ? this.idx.degStep : 15;
      this.showFrame();
      
      svc.preloadFrom(m.key, this.frameIdx(), this.frameCount());
    }
    this.ensureSpin();
  }

  aboutToDisappear(): void {
    if (this.spin >= 0) {
      clearInterval(this.spin);
      this.spin = -1;
    }
    this.cur = null;
    
    let s = this.strip;
    this.strip = null;
    this.stripKey = '';
    if (s !== null) {
      s.release().then((): void => {});
    }
    let bp = this.bandPm;
    this.bandPm = null;
    this.bandCtx = null;
    if (bp !== null) {
      bp.release().then((): void => {});
    }
    TurntableFrames.get().releaseAll();
  }

  onParam(): void {
    let svc = TurntableFrames.get();
    let m = svc.metaOf(this.shape);
    this.meta = m;
    if (m === null || this.idx === null) {
      
      this.cur = null;
      this.ready = false;
      return;
    }
    this.fw = this.idx.canvas[0];
    this.fh = this.idx.canvas[1];
    
    if (m.key !== this.lastKey) {
      this.cur = null;
      this.ready = false;
      
      svc.keepOnly(m.key);
      this.showFrame();
      svc.preloadFrom(m.key, this.frameIdx(), this.frameCount());
      return;
    }
    this.showFrame();
  }

  frameCount(): number {
    let m = this.meta;
    return m !== null && m.frames > 0 ? m.frames : Math.round(360 / this.degStep);
  }

  frameIdx(): number {
    let n = this.frameCount();
    let step = 360 / n;
    let k = Math.round(this.angle / step);
    return ((k % n) + n) % n;
  }

  showFrame(): void {
    let m = this.meta;
    let svc = TurntableFrames.get();
    if (m === null) {
      return;
    }
    let n = this.frameCount();
    let f = this.frameIdx();
    
    let key = m.key;
    let hit = svc.peek(key, f);
    if (hit !== null) {
      this.cur = hit;
      this.lastKey = key;
      this.ready = true;
      this.paint();
    } else {
      let my = this.seq + 1;
      this.seq = my;
      svc.frame(key, f).then((pm: image.PixelMap | null): void => {
        
        if (my !== this.seq) {
          return;
        }
        if (pm === null) {
          
          this.meta = null;
          this.ready = false;
          return;
        }
        this.cur = pm;
        this.lastKey = key;
        this.ready = true;
        this.paint();
      });
    }
    svc.prefetch(key, (f + 1) % n);
    svc.prefetch(key, (f + n - 1) % n);
  }

  ensureSpin(): void {
    if (this.spin >= 0) {
      return;
    }
    this.spin = setInterval((): void => {
      if (this.dragging || Date.now() - this.idleAt < RESUME_MS) {
        return;
      }
      if (this.meta === null) {
        return;
      }
      this.angle += this.degStep;
      this.showFrame();
    }, SPIN_MS);
  }

  onDrag(dx: number): void {
    let m = this.meta;
    if (m === null || this.fitScale <= 0) {
      return;
    }
    let rVp = m.maxHalfPx * this.fitScale;
    if (rVp <= 0) {
      return;
    }
    this.angle = this.dragBase + dx * (180 / (Math.PI * rVp));
    this.showFrame();
  }

  paint(): void {
    let c = this.c2d;
    let w = c.width;
    let h = c.height;
    let m = this.meta;
    let cur = this.cur;
    if (w <= 0 || h <= 0 || m === null || cur === null) {
      return;
    }
    let p = paletteOf(this.glaze);
    let s = Math.min(w / this.fw, h / this.fh);
    this.fitScale = s;
    let ox = (w - this.fw * s) / 2;
    let oy = (h - this.fh * s) / 2;
    c.clearRect(0, 0, w, h);

    c.save();
    c.setTransform(s, 0, 0, s, ox, oy);
    c.globalCompositeOperation = 'source-over';
    c.drawImage(cur, 0, 0, this.fw, this.fh);
    this.tint(c, p, m);
    this.wrap(c, p, m);
    
    this.shade(c, m);
    
    c.globalCompositeOperation = 'destination-over';
    
    let contact = this.shape === '鼎式' ? this.fh * 0.895 : m.botPx;
    drawPedestal(c, p, this.shape, this.pedestal, contact, this.fw, this.fh);
    c.restore();

    c.globalCompositeOperation = 'destination-over';
    drawPaper(c, p, this.seed, w, h);
    c.globalCompositeOperation = 'source-over';
  }

  private tint(c: CanvasRenderingContext2D, p: Palette, m: ShapeMeta): void {
    
    let d = FRAME_LUM - hexLum(p.base);
    let a = d <= TINT_TOL ? TINT_MIN : Math.max(TINT_MIN, Math.min(TINT_MAX, 1 - TINT_TOL / d));
    let g: CanvasGradient = c.createLinearGradient(0, m.topPx, 0, m.botPx);
    
    g.addColorStop(0, withAlpha(p.base, a));
    g.addColorStop(0.55, withAlpha(p.base, a));
    g.addColorStop(1, withAlpha(p.deep, Math.min(TINT_MAX, a + 0.08)));
    c.globalCompositeOperation = 'source-atop';
    c.fillStyle = g;
    c.fillRect(0, 0, this.fw, this.fh);
  }

  private shade(c: CanvasRenderingContext2D, m: ShapeMeta): void {
    let r = m.maxHalfPx;
    if (r <= 0) {
      return;
    }
    let g: CanvasGradient = c.createLinearGradient(this.fw / 2 - r, 0, this.fw / 2 + r, 0);
    g.addColorStop(0, 'rgba(43,38,34,0.26)');
    g.addColorStop(0.30, 'rgba(43,38,34,0.02)');
    g.addColorStop(0.46, 'rgba(255,255,255,0)');
    g.addColorStop(0.64, 'rgba(255,255,255,0.15)');
    g.addColorStop(0.80, 'rgba(255,255,255,0.03)');
    g.addColorStop(1, 'rgba(43,38,34,0.30)');
    c.globalCompositeOperation = 'source-atop';
    c.fillStyle = g;
    c.fillRect(0, 0, this.fw, this.fh);
  }

  private ensureStrip(p: Palette, m: ShapeMeta, y0: number, y1: number): boolean {
    let r = m.maxHalfPx;
    if (r <= 0 || y1 <= y0) {
      return false;
    }
    let per = Math.PI * r;
    let key = this.shape + '|' + this.motif + '|' + this.glaze + '|' + this.seed + '|'
      + Math.round(per) + '|' + Math.round(y0) + '|' + Math.round(y1);
    if (this.strip !== null && key === this.stripKey) {
      return true;
    }
    let old = this.strip;
    this.strip = null;
    this.stripKey = '';
    try {
      let wPx = Math.ceil(per * STRIP_SS);
      let hPx = Math.ceil((y1 - y0) * STRIP_SS);
      let off = new OffscreenCanvas(wPx, hPx, LengthMetricsUnit.PX);
      let o = off.getContext('2d', new RenderingContextSettings(true));
      
      o.scale(STRIP_SS, STRIP_SS);
      o.translate(0, -y0);
      
      for (let j = -1; j <= 1; j++) {
        drawBand(o, p, this.motif, this.seed, j * per, (j + 1) * per, y0, y1, this.fh);
      }
      this.strip = o.getPixelMap(0, 0, wPx, hPx);
      this.stripKey = key;
    } catch (e) {
      console.warn('band strip unavailable: keep vector wrap');
      if (this.strip !== null) {
        this.strip.release().then((): void => {});
        this.strip = null;
        this.stripKey = '';
      }
    }
    if (old !== null) {
      old.release().then((): void => {});
    }
    return this.strip !== null;
  }

  private blitSlabs(o: CanvasRenderer, bmp: image.PixelMap, per: number, sw: number, y0: number,
    bh: number, xL: number[], xR: number[], sL: number[], sq: number[]): void {
    for (let k = 0; k < SLABS; k++) {
      
      let u = sL[k] - per * Math.floor(sL[k] / per);
      let wide = per * sq[k];
      let x0 = xL[k] - u * sq[k];
      o.save();
      o.beginPath();
      
      o.rect(xL[k], y0, xR[k] - xL[k], bh);
      o.clip();
      o.drawImage(bmp, x0, y0, wide, bh);
      
      if (u + sw > per) {
        o.drawImage(bmp, x0 + wide, y0, wide, bh);
      }
      o.restore();
    }
  }

  private composeBand(bmp: image.PixelMap, r: number, y0: number, y1: number, per: number,
    sw: number, xL: number[], xR: number[], sL: number[], sq: number[]): image.PixelMap | null {
    let bwPx = Math.ceil(2 * r * STRIP_SS);
    let bhPx = Math.ceil((y1 - y0) * STRIP_SS);
    if (this.bandCtx === null || this.bandW !== bwPx || this.bandH !== bhPx) {
      try {
        let off = new OffscreenCanvas(bwPx, bhPx, LengthMetricsUnit.PX);
        this.bandCtx = off.getContext('2d', new RenderingContextSettings(true));
        this.bandW = bwPx;
        this.bandH = bhPx;
      } catch (e) {
        this.bandCtx = null;
        return null;
      }
    }
    let o = this.bandCtx;
    if (o === null) {
      return null;
    }
    try {
      o.setTransform(1, 0, 0, 1, 0, 0);
      o.clearRect(0, 0, bwPx, bhPx);
      
      o.setTransform(STRIP_SS, 0, 0, STRIP_SS,
        -(this.fw / 2 - r) * STRIP_SS, -y0 * STRIP_SS);
      o.globalCompositeOperation = 'source-over';
      this.blitSlabs(o, bmp, per, sw, y0, y1 - y0, xL, xR, sL, sq);
      let pm = o.getPixelMap(0, 0, bwPx, bhPx);
      let old = this.bandPm;
      this.bandPm = pm;
      if (old !== null) {
        old.release().then((): void => {});
      }
      return pm;
    } catch (e) {
      console.warn('band offscreen unavailable: blit slabs onto the canvas');
      this.bandCtx = null;
      return null;
    }
  }

  private wrap(c: CanvasRenderingContext2D, p: Palette, m: ShapeMeta): void {
    let r = m.maxHalfPx;
    let per = Math.PI * r;
    let y0 = m.topPx + (m.botPx - m.topPx) * m.band[0];
    let y1 = m.topPx + (m.botPx - m.topPx) * m.band[1];
    
    let phi = -this.angle * Math.PI / 180;
    let da = Math.PI / SLABS;
    
    let wordW = 2 * r / 0.92;
    let wordLo = per / 2 - wordW / 2;
    let wordHi = per / 2 + wordW / 2;
    
    let xL: number[] = [];
    let xR: number[] = [];
    let sL: number[] = [];
    let sR: number[] = [];
    let sq: number[] = [];
    for (let k = 0; k < SLABS; k++) {
      let a0 = -Math.PI / 2 + k * da;
      let a1 = a0 + da;
      let x0 = this.fw / 2 + r * Math.sin(a0);
      let x1 = this.fw / 2 + r * Math.sin(a1);
      let s0 = per / 2 + r * (a0 + phi);
      let s1 = per / 2 + r * (a1 + phi);
      xL.push(x0);
      xR.push(x1);
      sL.push(s0);
      sR.push(s1);
      sq.push((x1 - x0) / (s1 - s0));
    }
    
    let blitted = false;
    if (this.ensureStrip(p, m, y0, y1)) {
      let bmp = this.strip;
      if (bmp !== null) {
        blitted = true;
        let bh = y1 - y0;
        let sw = r * da;
        
        let band = this.composeBand(bmp, r, y0, y1, per, sw, xL, xR, sL, sq);
        c.globalCompositeOperation = 'source-atop';
        if (band !== null) {
          c.drawImage(band, this.fw / 2 - r, y0, 2 * r, bh);
        } else {
          
          this.blitSlabs(c, bmp, per, sw, y0, bh, xL, xR, sL, sq);
        }
      }
    }
    if (!blitted) {
      
      c.globalCompositeOperation = 'source-atop';
      for (let k = 0; k < SLABS; k++) {
        c.save();
        c.beginPath();
        c.rect(xL[k], 0, xR[k] - xL[k], this.fh);
        c.clip();
        c.translate(xL[k], 0);
        c.scale(sq[k], 1);
        c.translate(-sL[k], 0);
        let j0 = Math.floor(sL[k] / per);
        let j1 = Math.floor(sR[k] / per);
        for (let j = j0; j <= j1; j++) {
          drawBand(c, p, this.motif, this.seed, j * per, (j + 1) * per, y0, y1, this.fh);
        }
        c.restore();
      }
    }
    
    if (this.word.length > 0) {
      c.save();
      tracePath(c, this.shape, this.fw, this.fh);
      c.clip();
      c.globalCompositeOperation = 'source-over';
      let nBase = Math.round(r * phi / (2 * per));
      for (let k = 0; k < SLABS; k++) {
        c.save();
        c.beginPath();
        c.rect(xL[k], 0, xR[k] - xL[k], this.fh);
        c.clip();
        c.translate(xL[k], 0);
        c.scale(sq[k], 1);
        c.translate(-sL[k], 0);
        for (let n = nBase - 1; n <= nBase + 1; n++) {
          let wLo = wordLo + 2 * n * per;
          let wHi = wordHi + 2 * n * per;
          if (sR[k] > wLo && sL[k] < wHi) {
            c.save();
            c.translate(wLo, 0);
            drawWord(c, p, this.word, this.shape, this.seed, wordW, this.fh);
            c.restore();
          }
        }
        c.restore();
      }
      c.restore();
      c.globalCompositeOperation = 'source-atop';
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.ready && this.meta !== null) {
        Canvas(this.c2d)
          .width('100%')
          .height('100%')
          
          .backgroundColor(paletteOf(this.glaze).paper)
          .onReady((): void => {
            this.paint();
          })
      } else {
        PotteryCanvas({
          shape: this.shape,
          motif: this.motif,
          glaze: this.glaze,
          pedestal: this.pedestal,
          word: this.word,
          seed: this.seed
        })
      }

      if (this.ready && this.hint) {
        Text('‹ 左右拖动转台 ›')
          .fontSize(fs(this.ts, 10))
          .fontColor(SUB)
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
          .borderRadius(9)
          .backgroundColor('rgba(255,255,255,0.72)')
          .margin({ bottom: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 1 })
      .onActionStart((e: GestureEvent): void => {
        this.dragging = true;
        this.dragBase = this.angle;
        this.hint = false;
      })
      .onActionUpdate((e: GestureEvent): void => {
        this.onDrag(e.offsetX);
      })
      .onActionEnd((): void => {
        this.dragging = false;
        this.idleAt = Date.now();
      })
      .onActionCancel((): void => {
        this.dragging = false;
        this.idleAt = Date.now();
      }))
  }
}
