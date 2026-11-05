
const SPECKS: number[][] = [
  [10, 26, 3, 0.6], [84, 36, 2.5, 1], [32, 55, 2, 0.8],
  [70, 66, 3, 0.5], [18, 78, 2.5, 0.9], [88, 86, 2, 0.7]
];

@Component
export struct PatternBg {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  @State drift: number = 0;
  @State floatY: number = 0;

  aboutToAppear(): void {
    animateTo({
      duration: 15000, curve: Curve.Linear, iterations: -1, playMode: PlayMode.Alternate
    }, (): void => {
      this.drift = 44;
    });
    animateTo({
      duration: 6000, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate
    }, (): void => {
      this.floatY = -16;
    });
  }

  private waves(): void {
    let c = this.ctx;
    let w = c.width;
    let h = c.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    c.clearRect(0, 0, w, h);
    c.lineWidth = 1;
    let R = 30;
    let row = 0;
    for (let y = 0; y < h + R; y += R / 2) {
      let off = (row % 2) * (R / 2);
      for (let x = -R; x < w + R; x += R) {
        let cx = x + off;
        for (let k = 0; k < 3; k++) {
          c.strokeStyle = k === 1 ? 'rgba(200,161,96,0.075)' : 'rgba(166,85,61,0.055)';
          c.beginPath();
          c.arc(cx, y, R - k * 8, Math.PI, 2 * Math.PI);
          c.stroke();
        }
      }
      row++;
    }
  }

  build() {
    Stack() {
      Canvas(this.ctx)
        .width('100%')
        .height('100%')
        .onReady((): void => {
          this.waves();
        })

      Column()
        .width(260)
        .height(260)
        .borderRadius(130)
        .radialGradient({
          center: ['50%', '50%'], radius: 130,
          colors: [['rgba(200,161,96,0.10)', 0], ['rgba(200,161,96,0)', 1]]
        })
        .position({ x: -60, y: 120 })
        .translate({ x: this.drift, y: this.drift * 0.4 })
      Column()
        .width(300)
        .height(300)
        .borderRadius(150)
        .radialGradient({
          center: ['50%', '50%'], radius: 150,
          colors: [['rgba(166,85,61,0.08)', 0], ['rgba(166,85,61,0)', 1]]
        })
        .position({ x: 180, y: 420 })
        .translate({ x: -this.drift * 0.7, y: -this.drift * 0.3 })

      ForEach(SPECKS, (s: number[], i: number): void => {
        Column()
          .width(s[2])
          .height(s[2])
          .borderRadius(s[2] / 2)
          .backgroundColor('rgba(200,161,96,0.38)')
          .position({ x: `${s[0]}%`, y: `${s[1]}%` })
          .translate({ y: this.floatY * s[3] })
      }, (s: number[], i: number): string => 'sp_' + i)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}
