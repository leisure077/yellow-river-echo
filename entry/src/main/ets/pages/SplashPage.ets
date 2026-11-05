import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Boot } from '../service/Boot';

const RIVER_PTS: number[][] = [
  [0.10, 0.16], [0.28, 0.12], [0.50, 0.19], [0.62, 0.31],
  [0.50, 0.41], [0.32, 0.48], [0.30, 0.62], [0.46, 0.72],
  [0.68, 0.74], [0.86, 0.66]
];

@Entry
@Component
struct SplashPage {
  @StorageLink('textScale') ts: number = 1;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  @State draw: number = 0;
  @State titleIn: number = 0;
  private timer: number = -1;
  private step: number = 0;
  private leaving: boolean = false;
  private bootReady: boolean = false;
  @State bootFailed: boolean = false;

  aboutToAppear(): void {
    let ctx = getContext(this) as common.UIAbilityContext;
    let started = Date.now();
    Boot.run(ctx).then((): void => { this.bootReady = true; }).catch((e: Error): void => {
      console.error('boot: ' + e.message);
      this.bootFailed = true;
    });
    this.timer = setInterval((): void => {
      this.step += 1;
      this.draw = Math.min(this.step / 45, 1);
      this.titleIn = Math.min(this.step / 18, 1);
      this.paint();
      if (this.bootReady && this.step >= 60 && Date.now() - started > 3500 && !this.leaving) {
        this.leaving = true;
        clearInterval(this.timer);
        this.go();
      }
    }, 60);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
    }
  }

  go(): void {
    router.replaceUrl({ url: 'pages/GuidePage' });
  }

  private paint(): void {
    let c = this.ctx;
    let w = c.width;
    let h = c.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    c.clearRect(0, 0, w, h);

    c.fillStyle = 'rgba(122,110,98,0.10)';
    c.beginPath();
    c.moveTo(0, h * 0.30);
    c.quadraticCurveTo(w * 0.22, h * 0.18, w * 0.44, h * 0.29);
    c.quadraticCurveTo(w * 0.68, h * 0.40, w, h * 0.26);
    c.lineTo(w, h);
    c.lineTo(0, h);
    c.closePath();
    c.fill();
    c.fillStyle = 'rgba(74,123,140,0.10)';
    c.beginPath();
    c.moveTo(0, h * 0.44);
    c.quadraticCurveTo(w * 0.30, h * 0.34, w * 0.58, h * 0.46);
    c.quadraticCurveTo(w * 0.80, h * 0.55, w, h * 0.48);
    c.lineTo(w, h);
    c.lineTo(0, h);
    c.closePath();
    c.fill();

    let n = RIVER_PTS.length;
    let reach = this.draw * (n - 1);
    c.lineCap = 'round';
    c.lineJoin = 'round';
    c.strokeStyle = 'rgba(242,216,157,0.75)';
    c.lineWidth = Math.max(w * 0.055, 10);
    c.beginPath();
    c.moveTo(RIVER_PTS[0][0] * w, RIVER_PTS[0][1] * h);
    for (let i = 1; i < n; i++) {
      if (i - 1 >= reach) {
        break;
      }
      let p = RIVER_PTS[i];
      let prev = RIVER_PTS[i - 1];
      let frac = Math.min(reach - (i - 1), 1);
      let x = prev[0] * w + (p[0] * w - prev[0] * w) * frac;
      let y = prev[1] * h + (p[1] * h - prev[1] * h) * frac;
      let mx = (prev[0] * w + x) / 2;
      c.quadraticCurveTo(prev[0] * w + (mx - prev[0] * w) * 0.9, prev[1] * h, x, y);
    }
    c.stroke();
    c.strokeStyle = 'rgba(255,252,246,0.55)';
    c.lineWidth = Math.max(w * 0.012, 2);
    c.stroke();

    c.fillStyle = 'rgba(166,85,61,0.75)';
    c.beginPath();
    c.arc(w * 0.80, h * 0.14, w * 0.035 * Math.min(this.draw * 1.6, 1), 0, Math.PI * 2);
    c.fill();

    if (this.draw > 0.5) {
      c.strokeStyle = 'rgba(43,38,34,0.45)';
      c.lineWidth = 1.6;
      let birds: number[][] = [[0.62, 0.10], [0.70, 0.075], [0.76, 0.115]];
      for (let b of birds) {
        let bx = b[0] * w;
        let by = b[1] * h;
        let r = w * 0.018;
        c.beginPath();
        c.moveTo(bx - r, by);
        c.quadraticCurveTo(bx - r * 0.4, by - r * 0.7, bx, by - r * 0.1);
        c.quadraticCurveTo(bx + r * 0.4, by - r * 0.7, bx + r, by);
        c.stroke();
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Image($r('app.media.splash_scroll')).width('100%').height('100%').objectFit(ImageFit.Cover)
      Canvas(this.ctx).width('100%').height('48%').position({ x: 0, y: '34%' })
        .opacity(0.65).onReady((): void => { this.paint(); })
      Column({ space: 24 }) {
        Image($r('app.media.river_emblem')).width(96).height(96)
        Text('黄\n河\n续\n响').fontFamily('serif').fontSize(26).fontColor('#F8E8BF')
          .lineHeight(33).textAlign(TextAlign.Center)
        Text('一河千年 · 生生不息').fontSize(10).letterSpacing(4).fontColor('#F6DCB1')
      }.width('100%').margin({ top: 66 }).opacity(this.titleIn)
      if (this.bootFailed) {
        Button('加载未完成，点击重试').fontSize(12).fontColor('#754B37').backgroundColor('#F3E4BF')
          .position({ x: '20%', y: '88%' }).width('60%')
          .onClick((): void => {
            this.bootFailed = false;
            Boot.run(getContext(this) as common.UIAbilityContext).then((): void => {
              this.bootReady = true;
            }).catch((): void => { this.bootFailed = true; });
          })
      }
    }.width('100%').height('100%').backgroundColor('#C77F60')
  }
}
