import { fs, paletteOf, Palette } from '../common/Theme';

@Component
export struct ArtCover {
  @StorageLink('textScale') ts: number = 1;
  @Prop @Watch('repaint') palette: string = 'yangshao';
  @Prop @Watch('repaint') shape: string = 'pot';
  @Prop @Watch('repaint') seed: number = 0;
  @Prop @Watch('repaint') img: string = '';
  @Prop label: string = '';
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  repaint(): void {
    this.paint();
  }

  private band(c: CanvasRenderingContext2D, p: Palette, w: number, h: number): void {
    c.fillStyle = p.base;
    c.fillRect(0, 0, w, h);
    c.fillStyle = 'rgba(255,255,255,0.10)';
    for (let i = -1; i < 6; i++) {
      c.beginPath();
      c.moveTo(i * (w / 4), 0);
      c.lineTo(i * (w / 4) + h * 0.5, 0);
      c.lineTo(i * (w / 4) + h * 0.5 - h * 0.5, h);
      c.lineTo(i * (w / 4) - h * 0.5, h);
      c.closePath();
      c.fill();
    }
  }

  private motif(c: CanvasRenderingContext2D, p: Palette, cx: number, cy: number, r: number): void {
    c.strokeStyle = p.accent;
    c.lineWidth = Math.max(r * 0.06, 1.2);
    let mode = this.seed % 3;
    if (mode === 0) {
      c.beginPath();
      let n = 7;
      for (let i = 0; i <= n; i++) {
        let x = cx - r + (2 * r) * (i / n);
        let y = cy + (i % 2 === 0 ? -r * 0.18 : r * 0.18);
        if (i === 0) {
          c.moveTo(x, y);
        } else {
          c.lineTo(x, y);
        }
      }
      c.stroke();
    } else if (mode === 1) {
      for (let k = 1; k <= 3; k++) {
        c.beginPath();
        c.arc(cx, cy, r * k / 3.4, 0, Math.PI * 2);
        c.stroke();
      }
    } else {
      for (let k = -2; k <= 2; k++) {
        c.beginPath();
        c.moveTo(cx + k * r * 0.35, cy - r * 0.8);
        c.lineTo(cx + k * r * 0.35, cy + r * 0.8);
        c.stroke();
        c.beginPath();
        c.moveTo(cx - r * 0.8, cy + k * r * 0.35);
        c.lineTo(cx + r * 0.8, cy + k * r * 0.35);
        c.stroke();
      }
    }
  }

  private bodyPath(c: CanvasRenderingContext2D, p: Palette, w: number, h: number): void {
    let cx = w / 2;
    let top = h * 0.22;
    let bot = h * 0.86;
    c.fillStyle = p.deep;
    c.beginPath();
    if (this.shape === 'jar') {
      c.ellipse(cx, h * 0.58, w * 0.26, h * 0.26, 0, 0, Math.PI * 2);
      c.fill();
      c.fillRect(cx - w * 0.10, top, w * 0.20, h * 0.20);
    } else if (this.shape === 'ding') {
      c.ellipse(cx, h * 0.56, w * 0.24, h * 0.20, 0, 0, Math.PI * 2);
      c.fill();
      c.fillRect(cx - w * 0.22, h * 0.70, w * 0.05, h * 0.16);
      c.fillRect(cx + w * 0.17, h * 0.70, w * 0.05, h * 0.16);
      c.fillRect(cx - w * 0.025, h * 0.72, w * 0.05, h * 0.14);
      c.strokeStyle = p.deep;
      c.lineWidth = Math.max(w * 0.03, 2);
      c.beginPath();
      c.arc(cx - w * 0.16, top + h * 0.04, w * 0.06, Math.PI, 0);
      c.stroke();
      c.beginPath();
      c.arc(cx + w * 0.16, top + h * 0.04, w * 0.06, Math.PI, 0);
      c.stroke();
    } else if (this.shape === 'stele') {
      c.moveTo(cx - w * 0.16, bot);
      c.lineTo(cx - w * 0.16, top + h * 0.08);
      c.quadraticCurveTo(cx, top - h * 0.04, cx + w * 0.16, top + h * 0.08);
      c.lineTo(cx + w * 0.16, bot);
      c.closePath();
      c.fill();
    } else if (this.shape === 'tower') {
      for (let i = 0; i < 4; i++) {
        let yy = bot - i * h * 0.16;
        let ww = w * (0.30 - i * 0.05);
        c.fillRect(cx - ww / 2, yy - h * 0.13, ww, h * 0.13);
        c.beginPath();
        c.moveTo(cx - ww * 0.66, yy - h * 0.13);
        c.lineTo(cx + ww * 0.66, yy - h * 0.13);
        c.lineTo(cx + ww * 0.42, yy - h * 0.19);
        c.lineTo(cx - ww * 0.42, yy - h * 0.19);
        c.closePath();
        c.fill();
      }
    } else if (this.shape === 'cave') {
      c.moveTo(cx - w * 0.28, bot);
      c.lineTo(cx - w * 0.28, h * 0.44);
      c.quadraticCurveTo(cx, top - h * 0.06, cx + w * 0.28, h * 0.44);
      c.lineTo(cx + w * 0.28, bot);
      c.closePath();
      c.fill();
      c.fillStyle = p.paper;
      c.beginPath();
      c.arc(cx, h * 0.56, w * 0.11, Math.PI, 0);
      c.rect(cx - w * 0.11, h * 0.56, w * 0.22, h * 0.26);
      c.fill();
    } else if (this.shape === 'scroll') {
      c.fillRect(cx - w * 0.24, h * 0.36, w * 0.48, h * 0.30);
      c.fillStyle = p.accent;
      c.fillRect(cx - w * 0.27, h * 0.33, w * 0.05, h * 0.36);
      c.fillRect(cx + w * 0.22, h * 0.33, w * 0.05, h * 0.36);
    } else if (this.shape === 'coin') {
      c.arc(cx, h * 0.55, w * 0.24, 0, Math.PI * 2);
      c.fill();
      c.fillStyle = p.base;
      c.fillRect(cx - w * 0.07, h * 0.48, w * 0.14, h * 0.14);
    } else if (this.shape === 'box') {
      c.fillRect(cx - w * 0.24, h * 0.42, w * 0.48, h * 0.34);
      c.fillStyle = p.accent;
      c.fillRect(cx - w * 0.24, h * 0.36, w * 0.48, h * 0.08);
    } else if (this.shape === 'bridge') {
      c.strokeStyle = p.deep;
      c.lineWidth = Math.max(h * 0.05, 3);
      c.beginPath();
      c.arc(cx, h * 0.72, w * 0.26, Math.PI, 0);
      c.stroke();
      c.fillStyle = p.deep;
      c.fillRect(cx - w * 0.34, h * 0.70, w * 0.68, h * 0.05);
    } else if (this.shape === 'kiln') {
      c.moveTo(cx - w * 0.26, bot);
      c.quadraticCurveTo(cx - w * 0.20, top + h * 0.06, cx, top + h * 0.02);
      c.quadraticCurveTo(cx + w * 0.20, top + h * 0.06, cx + w * 0.26, bot);
      c.closePath();
      c.fill();
      c.fillStyle = p.paper;
      c.beginPath();
      c.arc(cx, h * 0.70, w * 0.09, Math.PI, 0);
      c.rect(cx - w * 0.09, h * 0.70, w * 0.18, h * 0.16);
      c.fill();
    } else if (this.shape === 'tile') {
      c.fillRect(cx - w * 0.24, h * 0.38, w * 0.48, h * 0.38);
      c.fillStyle = p.paper;
      c.fillRect(cx - w * 0.18, h * 0.44, w * 0.36, h * 0.06);
    } else {
      c.moveTo(cx - w * 0.09, top);
      c.lineTo(cx + w * 0.09, top);
      c.quadraticCurveTo(cx + w * 0.30, h * 0.40, cx + w * 0.20, bot);
      c.lineTo(cx - w * 0.20, bot);
      c.quadraticCurveTo(cx - w * 0.30, h * 0.40, cx - w * 0.09, top);
      c.closePath();
      c.fill();
    }
  }

  private paint(): void {
    let c = this.ctx;
    let w = c.width;
    let h = c.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    let p = paletteOf(this.palette);
    c.clearRect(0, 0, w, h);
    this.band(c, p, w, h);
    this.bodyPath(c, p, w, h);
    this.motif(c, p, w / 2, h * 0.58, Math.min(w, h) * 0.20);
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (this.img.length > 0) {
        Image($rawfile(this.img))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else {
        Canvas(this.ctx)
          .width('100%')
          .height('100%')
          .backgroundColor(paletteOf(this.palette).paper)
          .onReady((): void => {
            this.paint();
          })
      }
      if (this.label.length > 0) {
        Text(this.label)
          .fontSize(fs(this.ts, 10))
          .fontColor(paletteOf(this.palette).ink)
          .padding({ left: 7, right: 7, top: 3, bottom: 3 })
          .backgroundColor('rgba(255,255,255,0.62)')
          .borderRadius(8)
          .margin({ left: 8, bottom: 8 })
      }
    }
    .width('100%')
    .height('100%')
  }
}
