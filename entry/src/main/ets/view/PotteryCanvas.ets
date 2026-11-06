import { paletteOf, Palette } from '../common/Theme';
import {
  V_TOP, V_BOT, profileOf, bandOf, tracePath, drawWord,
  drawPaper, drawBand, drawRimFoot, drawPedestal
} from '../common/PotteryArt';

@Component
export struct PotteryCanvas {
  @Prop @Watch('repaint') shape: string = '罐';
  @Prop @Watch('repaint') motif: string = '鱼纹';
  @Prop @Watch('repaint') glaze: string = 'yangshao';
  @Prop @Watch('repaint') pedestal: string = '素台';
  @Prop @Watch('repaint') word: string = '';
  @Prop @Watch('repaint') seed: number = 0;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  repaint(): void {
    this.paint();
  }

  private feet(c: CanvasRenderingContext2D, p: Palette, w: number, h: number): void {
    if (this.shape !== '鼎式') {
      return;
    }
    let bot = h * V_BOT;
    let top = h * V_TOP;
    c.fillStyle = p.deep;
    let xs: number[] = [w / 2 - w * 0.20, w / 2, w / 2 + w * 0.20];
    for (let i = 0; i < xs.length; i++) {
      let fx = xs[i];
      let fl = (bot - top) * (i === 1 ? 0.14 : 0.20);
      c.beginPath();
      c.moveTo(fx - w * 0.045, bot - (bot - top) * 0.06);
      c.lineTo(fx + w * 0.045, bot - (bot - top) * 0.06);
      c.lineTo(fx + w * 0.03, bot + fl);
      c.lineTo(fx - w * 0.03, bot + fl);
      c.closePath();
      c.fill();
    }
  }

  private drawMotif(c: CanvasRenderingContext2D, p: Palette, w: number, h: number): void {
    let top = h * V_TOP;
    let bot = h * V_BOT;
    let bd = bandOf(this.shape);
    let y0 = top + (bot - top) * bd[0];
    let y1 = top + (bot - top) * bd[1];
    c.save();
    c.beginPath();
    c.rect(0, y0, w, y1 - y0);
    c.clip();
    drawBand(c, p, this.motif, this.seed, 0, w, y0, y1, h);
    c.restore();
  }

  private paint(): void {
    let c = this.ctx;
    let w = c.width;
    let h = c.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    let p = paletteOf(this.glaze);
    let top = h * V_TOP;
    let bot = h * V_BOT;
    c.clearRect(0, 0, w, h);
    drawPaper(c, p, this.seed, w, h);
    this.feet(c, p, w, h);
    drawPedestal(c, p, this.shape, this.pedestal,
      this.shape === '鼎式' ? bot + (bot - top) * 0.20 : bot, w, h);

    tracePath(c, this.shape, w, h);
    let g: CanvasGradient = c.createLinearGradient(0, top, 0, bot);
    g.addColorStop(0, p.base);
    g.addColorStop(0.55, p.base);
    g.addColorStop(1, p.deep);
    c.fillStyle = g;
    c.fill();

    tracePath(c, this.shape, w, h);
    c.save();
    c.clip();
    this.drawMotif(c, p, w, h);
    drawWord(c, p, this.word, this.shape, this.seed, w, h);
    c.fillStyle = 'rgba(43,38,34,0.14)';
    c.fillRect(w * 0.62, top, w * 0.40, bot - top);
    c.restore();

    tracePath(c, this.shape, w, h);
    c.strokeStyle = p.deep;
    c.lineWidth = Math.max(w * 0.008, 1.2);
    c.stroke();

    drawRimFoot(c, p, this.shape, w, h);

    let rx = profileOf(this.shape)[0][1] * w;
    if (this.shape === '鼎式') {
      c.strokeStyle = p.deep;
      c.lineWidth = Math.max(w * 0.022, 2);
      c.beginPath();
      c.arc(w / 2 - rx * 0.86, top - h * 0.01, rx * 0.24, Math.PI, Math.PI * 2);
      c.stroke();
      c.beginPath();
      c.arc(w / 2 + rx * 0.86, top - h * 0.01, rx * 0.24, Math.PI, Math.PI * 2);
      c.stroke();
    } else if (this.shape === '罐' || this.shape === '壶') {
      c.strokeStyle = p.deep;
      c.lineWidth = Math.max(w * 0.012, 1.4);
      c.beginPath();
      c.arc(w / 2 - rx * 1.02, top + (bot - top) * 0.22, rx * 0.26, -Math.PI * 0.5, Math.PI * 0.5);
      c.stroke();
      c.beginPath();
      c.arc(w / 2 + rx * 1.02, top + (bot - top) * 0.22, rx * 0.26, Math.PI * 0.5, Math.PI * 1.5);
      c.stroke();
    }
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .backgroundColor(paletteOf(this.glaze).paper)
      .onReady((): void => {
        this.paint();
      })
  }
}
