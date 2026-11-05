import { router } from '@kit.ArkUI';
import { StudioStore } from '../service/StudioStore';
import { HeritageMotion } from '../view/HeritageMotion';
@Entry
@Component
struct GuidePage {
  @State idx: number = 0;
  private ctrl: SwiperController = new SwiperController();
  private leaving: boolean = false;
  finish(): void {
    if (this.leaving) { return; }
    this.leaving = true;
    StudioStore.get().markGuideSeen();
    router.replaceUrl({ url: 'pages/LoginPage' });
  }
  @Builder
  slide(kind: number, art: Resource, place: string, title: string, subtitle: string) {
    Stack({ alignContent: Alignment.Top }) {
      Stack() {
        Image(art).width('100%').height('100%').objectFit(ImageFit.Fill)
        HeritageMotion({ kind: kind, active: this.idx === kind })
      
      }.width('100%').height('100%')
      Column({ space: 12 }) {
        Text(place).fontSize(11).letterSpacing(5).fontColor('#F1D8AC')
        Text(title).fontFamily('serif').fontSize(29).letterSpacing(5).fontColor('#FFF0CE')
        Text(subtitle).fontSize(12).letterSpacing(2).fontColor('#F5DFBF').lineHeight(23).textAlign(TextAlign.Center)
      }.width('100%').position({ x: 0, y: '68%' }).padding({ left: 20, right: 20 })
    }.width('100%').height('100%').clip(true).backgroundColor('#C77F60')
  }
  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Swiper(this.ctrl) {
        this.slide(0, $r('app.media.guide_longmen'), '洛阳 · 龙门石窟', '重走千年古道', '一步入石窟，一眼阅千年')
        this.slide(1, $r('app.media.guide_river'), '黄河 · 山川长卷', '循河读懂山川', '沿一川蜿蜒，寻两岸故事')
        this.slide(2, $r('app.media.guide_sancai'), '河洛 · 唐三彩', '续写文明回响', '循驼铃识古物，以收藏续文脉')
      }.width('100%').height('100%').indicator(false).loop(false)
        .onChange((i: number): void => { this.idx = i; })
      Row() {
        Button('跳过').fontSize(12).fontColor('#FFF0CE').backgroundColor('#365A392D')
          .height(32).width(64).onClick((): void => { this.finish(); })
      }.width('100%').justifyContent(FlexAlign.End).padding({ right: 24 }).position({ x: 0, y: 22 })
      Column({ space: 23 }) {
        Button(this.idx === 2 ? '开启续响' : '循迹而行  →')
          .fontSize(15).fontColor('#9F4E3C').backgroundColor('#F3E4BF').width(164).height(40).borderRadius(20)
          .onClick((): void => { if (this.idx === 2) { this.finish(); } else { this.ctrl.showNext(); } })
        Row({ space: 10 }) {
          ForEach([0, 1, 2], (i: number): void => {
            Column().width(28).height(2).backgroundColor('#F7E9CC').opacity(this.idx === i ? 1 : 0.38)
              .onClick((): void => { this.ctrl.changeIndex(i, true); })
          }, (i: number): string => `${i}`)
        }
      }.padding({ bottom: 35 })
    }.width('100%').height('100%').backgroundColor('#C77F60')
  }
}
