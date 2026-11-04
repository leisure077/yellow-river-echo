import { router } from '@kit.ArkUI';
import { INK, SUB, PAPER, CLAY, LINE, fs, coverRes, colorRowOf } from '../common/Theme';
import { goBack, params, goRelic, goSandtable } from '../common/Nav';
import { PatternBg } from '../view/PatternBg';
import { ContentRepo } from '../service/ContentRepo';
import { RelicBrowser } from '../view/RelicBrowser';
import { Course } from '../model/Models';
import { CourseRow } from '../view/CourseRow';

// 「数字文物」独立模块：页顶栏三个页签——观文物 / 创意坊 / 选教程
// 观文物是内嵌的查询面板（搜索 + 分类年代颜色筛选 + 两列结果），
// 创意坊放 3D 文物展台与工坊入口，选教程是分类胶囊 + 教程列表
interface ExhibitRec {
  img: string;
  key: string;
}

// 六件展品：实物示意图 + 对应色键，色键用来取展台下方的色名与说法
const SHOW: ExhibitRec[] = [
  { img: 'relic_caitao', key: 'yangshao' },
  { img: 'relic_heitao', key: 'longshan' },
  { img: 'relic_qingtong', key: 'xiashang' },
  { img: 'relic_bianzhong', key: 'zhou' },
  { img: 'relic_sancai', key: 'hantang' },
  { img: 'relic_tianqing', key: 'song' }
];
const CATS: string[] = ['全部', '手作', '讲读', '影像'];
const TABS: string[] = ['观文物', '创意坊', '选教程'];

@Entry
@Component
export struct StudioPage {
  // 字号档位变了要整页重画，否则切完「大」这一页还是老字号
  @StorageLink('textScale') ts: number = 1;
  @State tab: number = 1;
  @State cur: number = 0;
  @State sway: number = -5;
  @State floatY: number = 0;
  @State cat: string = '全部';

  aboutToAppear(): void {
    let p = params();
    if (p !== undefined && p.tab !== undefined && p.tab >= 0 && p.tab < TABS.length) {
      this.tab = p.tab;
    }
    // 展台缓摆：绕 y 轴 -5°~5° 往复；上下 8px 浮沉，像展柜里被轻托着
    animateTo({
      duration: 6000, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate
    }, (): void => {
      this.sway = 5;
    });
    animateTo({
      duration: 4200, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate
    }, (): void => {
      this.floatY = -8;
    });
  }

  // 展品相对当前选中的偏移：-3..3，只渲染 |rel|<=1（两侧侧身件 + 中央正身件）
  private rel(i: number): number {
    let d = i - this.cur;
    while (d > 3) {
      d -= 6;
    }
    while (d < -3) {
      d += 6;
    }
    return d;
  }

  private pick(i: number): void {
    if (this.rel(i) === 1) {
      this.cur = (this.cur + 1) % 6;
    } else if (this.rel(i) === -1) {
      this.cur = (this.cur + 5) % 6;
    }
  }

  // 选教程当前分类下的课程，与课程影像页取的是同一份数据
  courses(): Course[] {
    return ContentRepo.get().coursesOf(this.cat);
  }

  build() {
    Stack() {
      PatternBg()
      Column() {
      // 页头：返回 + 居中标题
      Row() {
        Text('‹')
          .fontSize(fs(this.ts, 20))
          .fontColor(INK)
          .width(34)
          .height(34)
          .textAlign(TextAlign.Center)
          .backgroundColor('rgba(255,255,255,0.72)')
          .borderRadius(17)
          .onClick(goBack)
        Blank()
        Text('数字文物')
          .fontSize(fs(this.ts, 18))
          .fontWeight(FontWeight.Bold)
          .fontColor(INK)
          .letterSpacing(3)
        Blank()
        Column().width(34).height(34)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 6 })

      // 页顶栏：观文物 / 创意坊 / 选教程
      Row() {
        ForEach(TABS, (t: string, i: number): void => {
          Column({ space: 5 }) {
            Text(t)
              .fontSize(fs(this.ts, 14))
              .fontColor(this.tab === i ? INK : SUB)
              .fontWeight(this.tab === i ? FontWeight.Bold : FontWeight.Regular)
              .letterSpacing(1)
            Column()
              .width(this.tab === i ? 24 : 0)
              .height(3)
              .borderRadius(1.5)
              .backgroundColor(CLAY)
          }
          .padding({ left: 16, right: 16, top: 2, bottom: 4 })
          .onClick((): void => {
            animateTo({ duration: 240, curve: Curve.EaseOut }, (): void => {
              this.tab = i;
            });
          })
        }, (t: string, i: number): string => 'tab_' + i)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      if (this.tab === 0) {
        // 观文物自带滚动，不能再套一层 Scroll，否则内层 layoutWeight 撑不开
        RelicBrowser()
          .layoutWeight(1)
      } else {
        Scroll() {
          Column({ space: 14 }) {
            if (this.tab === 1) {
              this.stage()
              this.works()
            } else {
              this.coursePick()
            }
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        // 课少的时候内容不满一屏，Scroll 默认会把它垂直居中，讲读/影像这种单课分类会掉到屏幕中间
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PAPER)
  }
  }

  // —— 3D 文物展台：中央正身缓摆 + 两侧侧身件 + 地面倒影 + 指示点 ——
  @Builder
  stage() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        // 展台净底：一圈纸色柔光晕开，文物像立在展柜灯下，也盖住背景纹样
        Column()
          .width(330)
          .height(296)
          .borderRadius(148)
          .radialGradient({
            center: ['50%', '46%'], radius: 210,
            colors: [['#F5EFE4', 0], ['#F5EFE4', 0.62], ['rgba(245,239,228,0)', 1]]
          })
        ForEach(SHOW, (e: ExhibitRec, i: number): void => {
          if (Math.abs(this.rel(i)) <= 1) {
            Column() {
              Image(coverRes(e.img))
                .width(216)
                .height(216)
                .objectFit(ImageFit.Contain)
              // 倒影：同一张图取一段翻转压扁，纸色渐变抹淡
              if (this.rel(i) === 0) {
                Stack({ alignContent: Alignment.Top }) {
                  Image(coverRes(e.img))
                    .width(216)
                    .height(64)
                    .objectFit(ImageFit.Cover)
                    .scale({ y: -1 })
                    .opacity(0.16)
                  Column()
                    .width(216)
                    .height(64)
                    .linearGradient({
                      angle: 180,
                      colors: [['rgba(245,239,228,0.25)', 0], ['rgba(245,239,228,1)', 0.85]]
                    })
                }
                .width(216)
                .height(64)
              }
            }
            .rotate({
              x: 0, y: 1, z: 0,
              angle: this.rel(i) === 0 ? this.sway : (this.rel(i) < 0 ? 40 : -40)
            })
            .scale({ x: this.rel(i) === 0 ? 1 : 0.66, y: this.rel(i) === 0 ? 1 : 0.66 })
            .opacity(this.rel(i) === 0 ? 1 : 0.55)
            .translate({ x: this.rel(i) * 148, y: this.rel(i) === 0 ? this.floatY : 12 })
            .zIndex(this.rel(i) === 0 ? 20 : 10)
            .onClick((): void => {
              this.pick(i);
            })
          }
        }, (e: ExhibitRec, i: number): string => 'stage_' + e.img + '_' + this.cur)
        // 左右切换箭头
        Row() {
          Text('‹')
            .fontSize(fs(this.ts, 22))
            .fontColor(SUB)
            .padding(10)
            .onClick((): void => {
              this.cur = (this.cur + 5) % 6;
            })
          Blank()
          Text('›')
            .fontSize(fs(this.ts, 22))
            .fontColor(SUB)
            .padding(10)
            .onClick((): void => {
              this.cur = (this.cur + 1) % 6;
            })
        }
        .width('100%')
        .height(60)
        .padding({ left: 4, right: 4 })
        .zIndex(30)
      }
      .width('100%')
      .height(300)

      // 展品名 + 指示点
      Text(colorRowOf(SHOW[this.cur].key).name)
        .fontSize(fs(this.ts, 15))
        .fontWeight(FontWeight.Bold)
        .fontColor(INK)
        .letterSpacing(2)
      Row({ space: 6 }) {
        ForEach(SHOW, (e: ExhibitRec, i: number): void => {
          Column()
            .width(i === this.cur ? 14 : 5)
            .height(5)
            .borderRadius(2.5)
            .backgroundColor(i === this.cur ? CLAY : LINE)
            .onClick((): void => {
              this.cur = i;
            })
        }, (e: ExhibitRec, i: number): string => 'dot_' + e.img)
      }

      Text(colorRowOf(SHOW[this.cur].key).saying)
        .fontSize(fs(this.ts, 10))
        .fontColor(SUB)
        .width('80%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 6 })
  }

  // 卡片标题一律逐字排到四字宽、两端对齐：「3D工坊」开头是半角，整块排会短一截对不齐
  @Builder
  workTitle(t: string) {
    Row() {
      ForEach(t.split(''), (ch: string, i: number): void => {
        Text(ch)
          .fontSize(fs(this.ts, 15))
          .fontWeight(FontWeight.Bold)
          .fontColor(INK)
      }, (ch: string, i: number): string => t + '_' + i)
    }
    .width(4 * fs(this.ts, 15) + 6)
    .justifyContent(FlexAlign.SpaceBetween)
  }

  // —— 工坊入口：彩陶工坊 / 3D工坊 / 黄河沙盘，各带一句玩法说明 ——
  @Builder
  works() {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 6 }) {
          this.workTitle('彩陶工坊')
          Text('拉坯 · 上彩 · 入窑，做一件自己的彩陶')
            .fontSize(fs(this.ts, 10))
            .fontColor(SUB)
          Row({ space: 4 }) {
            Text('进工坊')
              .fontSize(fs(this.ts, 10))
              .fontColor(CLAY)
            Text('›')
              .fontSize(fs(this.ts, 11))
              .fontColor(CLAY)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .padding(12)
        .backgroundColor('rgba(255,255,255,0.72)')
        .borderRadius(12)
        .border({ width: 1, color: LINE })
        .onClick((): void => {
          router.pushUrl({ url: 'pages/PotteryPage' });
        })
      }
      .width('100%')

      Row() {
        Column({ space: 6 }) {
          this.workTitle('3D工坊')
          Text('转一转 · 看黄河流域器物的釉色与纹样')
            .fontSize(fs(this.ts, 10))
            .fontColor(SUB)
          Row({ space: 4 }) {
            Text('看文物')
              .fontSize(fs(this.ts, 10))
              .fontColor(CLAY)
            Text('›')
              .fontSize(fs(this.ts, 11))
              .fontColor(CLAY)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .padding(12)
        .backgroundColor('rgba(255,255,255,0.72)')
        .borderRadius(12)
        .border({ width: 1, color: LINE })
        .onClick((): void => {
          goRelic(0);
        })
      }
      .width('100%')

      Row() {
        Column({ space: 6 }) {
          this.workTitle('黄河沙盘')
          Text('拖时间轴推演四段河史：治水 · 漕运 · 改道 · 安澜')
            .fontSize(fs(this.ts, 10))
            .fontColor(SUB)
          Row({ space: 4 }) {
            Text('进沙盘')
              .fontSize(fs(this.ts, 10))
              .fontColor(CLAY)
            Text('›')
              .fontSize(fs(this.ts, 11))
              .fontColor(CLAY)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .padding(12)
        .backgroundColor('rgba(255,255,255,0.72)')
        .borderRadius(12)
        .border({ width: 1, color: LINE })
        .onClick((): void => {
          goSandtable();
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 14, right: 14 })
  }

  // —— 选教程：分类胶囊 + 教程列表，行样式与课程影像页同一段代码 ——
  @Builder
  coursePick() {
    Column({ space: 10 }) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(CATS, (c: string): void => {
            Text(c)
              .fontSize(fs(this.ts, 12))
              .fontColor(c === this.cat ? Color.White : INK)
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .borderRadius(14)
              .backgroundColor(c === this.cat ? CLAY : $r('app.color.card_bg'))
              .onClick((): void => {
                this.cat = c;
              })
          }, (c: string): string => 'cat_' + c)
        }
        .padding({ left: 14, right: 14 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      if (ContentRepo.get().courses.length === 0) {
        Column({ space: 6 }) {
          Text('课程数据包未随包提供').fontSize(fs(this.ts, 14)).fontColor(INK)
          Text('遗址档案与彩陶工坊不受影响').fontSize(fs(this.ts, 11)).fontColor(SUB)
        }
        .width('100%')
        .padding({ left: 14, right: 14 })
        .margin({ top: 40 })
      } else if (this.courses().length === 0) {
        Text('这一类暂时没有课程').fontSize(fs(this.ts, 13)).fontColor(SUB)
          .width('100%')
          .padding({ left: 14, right: 14 })
          .margin({ top: 40 })
      } else {
        Column({ space: 8 }) {
          ForEach(this.courses(), (c: Course, i: number): void => {
            CourseRow({ course: c, seed: i + 1 })
          }, (c: Course): string => 'row_' + c.id)
        }
        .width('100%')
        .padding({ left: 14, right: 14 })
      }
    }
    .width('100%')
    .padding({ top: 6 })
  }
}
