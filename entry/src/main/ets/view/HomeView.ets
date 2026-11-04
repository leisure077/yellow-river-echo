import { promptAction } from '@kit.ArkUI';
import { Goods, EventInfo, Suggestion, SiteInfo } from '../model/Models';
import { SiteRepo } from '../service/SiteRepo';
import { ContentRepo } from '../service/ContentRepo';
import { StudioStore } from '../service/StudioStore';
import { MemoryStore } from '../service/MemoryStore';
import { ArtCover } from './ArtCover';
import { PatternBg } from './PatternBg';
import { Verse, verseOf, verseSiteName } from '../common/Verses';
import { siteU } from '../common/River';
import {
  INK, SUB, LOESS, CLAY, RIVER, LINE, PAPER,
  coverRes, coverOf, moneyText, fs
} from '../common/Theme';
import {
  openDrawer, switchTab, goList, goDetail, goArchive, goPottery,
  goActivity, goCheckin, goRoute, goQuiz,
  goTopic, goStudio, goExperience, openAssistantSheet
} from '../common/Nav';

const SHAPES: string[] = ['pot', 'jar', 'ding', 'tile', 'stele', 'box', 'coin', 'kiln'];

interface TileRec {
  kind: string;
  title: string;
  act: () => void;
}

// 宫格印章的画法：全部用基础形叠出来，不引图片资源。
// 每一枚都是"纸底 + 双线框 + 一件小器物"，按下会缩一下再弹回来。
@Builder
function artOf(kind: string, scale: number) {
  if (kind === 'scroll') {
    Column() {
      Column().width(32).height(5).borderRadius(2.5).backgroundColor(CLAY)
      Column({ space: 3 }) {
        Column().width(16).height(1.5).backgroundColor('#6B5B4A')
        Column().width(16).height(1.5).backgroundColor('#6B5B4A')
        Column().width(11).height(1.5).backgroundColor('#6B5B4A')
      }
      .width(24).height(18).backgroundColor(PAPER).border({ width: 1, color: LINE })
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Start).padding({ left: 4 })
      Column().width(32).height(5).borderRadius(2.5).backgroundColor(CLAY)
    }
  } else if (kind === 'seal') {
    Column({ space: 1 }) {
      Column().width(12).height(7).borderRadius({ topLeft: 3, topRight: 3 }).backgroundColor('#8A4531')
      Stack() {
        Column().width(26).height(24).borderRadius(4).backgroundColor(CLAY)
        Column({ space: 2 }) {
          Row({ space: 2 }) {
            Column().width(8).height(8).borderRadius(1).backgroundColor('rgba(246,226,206,0.92)')
            Column().width(8).height(8).borderRadius(1).backgroundColor('rgba(246,226,206,0.92)')
          }
          Row({ space: 2 }) {
            Column().width(8).height(8).borderRadius(1).backgroundColor('rgba(246,226,206,0.92)')
            Column().width(8).height(8).borderRadius(1).backgroundColor('rgba(246,226,206,0.92)')
          }
        }
      }
      .width(26).height(24)
    }
  } else if (kind === 'route') {
    Stack() {
      Column().width(34).height(2).backgroundColor('#D9C9A8')
      Row() {
        Column().width(8).height(8).borderRadius(4).backgroundColor(CLAY)
        Blank()
        Column().width(8).height(8).borderRadius(4).backgroundColor(PAPER).border({ width: 1.5, color: LOESS })
        Blank()
        Column().width(8).height(8).borderRadius(4).backgroundColor(PAPER).border({ width: 1.5, color: CLAY })
      }
      .width(34)
    }
    .width(36).height(12)
  } else if (kind === 'lantern') {
    Column() {
      Column().width(10).height(3).borderRadius(1.5).backgroundColor(LOESS)
      Stack() {
        Column().width(24).height(19).borderRadius(9).backgroundColor(CLAY)
        Row({ space: 4 }) {
          Column().width(1).height(13).backgroundColor('rgba(246,226,206,0.55)')
          Column().width(1).height(13).backgroundColor('rgba(246,226,206,0.55)')
        }
      }
      .width(24).height(19)
      Column().width(10).height(3).borderRadius(1.5).backgroundColor(LOESS)
      Column().width(2).height(5).backgroundColor(LOESS)
    }
  } else if (kind === 'pot') {
    Column() {
      Column().width(12).height(3).borderRadius(1.5).backgroundColor(CLAY)
      Column().width(7).height(4).backgroundColor(CLAY)
      Stack({ alignContent: Alignment.Top }) {
        Column().width(24).height(16)
          .borderRadius({ bottomLeft: 11, bottomRight: 11, topLeft: 6, topRight: 6 })
          .backgroundColor(CLAY)
        Column().width(24).height(3).backgroundColor('rgba(246,226,206,0.5)').margin({ top: 6 })
      }
      .width(24).height(16)
    }
  } else if (kind === 'swatch') {
    Row() {
      Column().width(18).height(18).borderRadius(9).backgroundColor(CLAY).border({ width: 1.5, color: PAPER })
      Column().width(18).height(18).borderRadius(9).backgroundColor(RIVER).border({ width: 1.5, color: PAPER })
        .margin({ left: -6 })
      Column().width(18).height(18).borderRadius(9).backgroundColor(LOESS).border({ width: 1.5, color: PAPER })
        .margin({ left: -6 })
    }
  } else if (kind === 'film') {
    Column({ space: 2 }) {
      Row({ space: 3 }) {
        Column().width(3).height(3).backgroundColor('#B9A88F')
        Column().width(3).height(3).backgroundColor('#B9A88F')
        Column().width(3).height(3).backgroundColor('#B9A88F')
      }
      Stack() {
        Column().width(28).height(17).borderRadius(3).backgroundColor(INK)
        Text('▶').fontSize(fs(scale, 8)).fontColor(PAPER)
      }
      .width(28).height(17)
      Row({ space: 3 }) {
        Column().width(3).height(3).backgroundColor('#B9A88F')
        Column().width(3).height(3).backgroundColor('#B9A88F')
        Column().width(3).height(3).backgroundColor('#B9A88F')
      }
    }
  } else if (kind === 'slips') {
    Row({ space: 2 }) {
      Stack({ alignContent: Alignment.Top }) {
        Column().width(5).height(24).borderRadius(2).backgroundColor(LOESS)
        Column().width(5).height(2).backgroundColor(CLAY).margin({ top: 6 })
      }.width(5).height(24)
      Stack({ alignContent: Alignment.Top }) {
        Column().width(5).height(26).borderRadius(2).backgroundColor('#C8A160')
        Column().width(5).height(2).backgroundColor(CLAY).margin({ top: 7 })
      }.width(5).height(26)
      Stack({ alignContent: Alignment.Top }) {
        Column().width(5).height(23).borderRadius(2).backgroundColor(LOESS)
        Column().width(5).height(2).backgroundColor(CLAY).margin({ top: 5 })
      }.width(5).height(23)
      Stack({ alignContent: Alignment.Top }) {
        Column().width(5).height(25).borderRadius(2).backgroundColor('#C8A160')
        Column().width(5).height(2).backgroundColor(CLAY).margin({ top: 8 })
      }.width(5).height(25)
    }
  } else if (kind === 'net') {
    Stack() {
      Column().width(30).height(1.5).backgroundColor('#D9C9A8').rotate({ angle: 45 })
      Column().width(30).height(1.5).backgroundColor('#D9C9A8').rotate({ angle: -45 })
      Column().width(5).height(5).borderRadius(2.5).backgroundColor(LOESS).offset({ x: -11, y: -11 })
      Column().width(5).height(5).borderRadius(2.5).backgroundColor(LOESS).offset({ x: 11, y: -11 })
      Column().width(5).height(5).borderRadius(2.5).backgroundColor(LOESS).offset({ x: -11, y: 11 })
      Column().width(5).height(5).borderRadius(2.5).backgroundColor(LOESS).offset({ x: 11, y: 11 })
      Column().width(9).height(9).borderRadius(4.5).backgroundColor(CLAY)
    }
    .width(32).height(32)
  } else {
    Column() {
      Column().width(6).height(4).borderRadius(1).backgroundColor(INK)
      Column().width(5).height(15).backgroundColor('#6B4A32')
      Column().width(5).height(8).borderRadius({ bottomLeft: 3, bottomRight: 3 }).backgroundColor(INK)
    }
    .rotate({ angle: 32 })
  }
}

// 宫格按钮：无框写实风——器物直接立在纸面上，脚下一道柔和落影托住，
// 不描边、不加底板，像参考图那样"图 + 名"两截干净地浮着。按下沉一点再弹回。
@Component
struct RelicTile {
  // 字号档位变了要整页重画：不持有这行，切档后这一页还是老字号
  @StorageLink('textScale') ts: number = 1;
  @Prop kind: string = '';
  @Prop title: string = '';
  act: () => void = (): void => {};
  @State sc: number = 1;

  press(): void {
    animateTo({
      duration: 90, curve: Curve.EaseOut, onFinish: (): void => {
        animateTo({ duration: 160, curve: Curve.EaseIn }, (): void => {
          this.sc = 1;
        });
      }
    }, (): void => {
      this.sc = 0.9;
    });
    this.act();
  }

  build() {
    Column({ space: 5 }) {
      Stack({ alignContent: Alignment.Bottom }) {
        // 落影：一枚压扁的径向渐变椭圆，让器物像放在台面上而非贴纸
        Column()
          .width(34)
          .height(9)
          .radialGradient({
            center: ['50%', '50%'], radius: 17,
            colors: [['rgba(43,38,34,0.18)', 0], ['rgba(43,38,34,0)', 1]]
          })
        Column() {
          artOf(this.kind, this.ts)
        }
        .width(50)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .margin({ bottom: 5 })
      }
      .width(52)
      .height(50)

      Text(this.title)
        .fontSize(fs(this.ts, 11))
        .fontColor(INK)
        .maxLines(1)
    }
    .width('25%')
    .padding({ top: 6, bottom: 6 })
    .scale({ x: this.sc, y: this.sc })
    .onClick((): void => {
      this.press();
    })
  }
}

// 首页照故宫式排布：通栏海报 → 「黄河续响平台」大卡（实景打卡 / 数字文物双卡 + 我的档案行）
// → 八枚功能印章宫格（两排，一排四枚）→ 为你推荐 → 文创市集。被四段版收掉的入口（测验、课程、
// 知识网络）全部在宫格里回来，另加行程与颜色两个新工坊。河工、同步两枚已撤出首页，
// 侧栏里仍然进得去。
@Component
export struct HomeView {
  @StorageLink('dataRev') @Watch('reload') dataRev: number = 0;
  @StorageLink('studioRev') studioRev: number = 0;
  @StorageLink('textScale') ts: number = 1;
  @State kw: string = '';
  @State verse: Verse | undefined = undefined;
  @State reco: Suggestion[] = [];
  @State hot: Goods[] = [];
  @State events: EventInfo[] = [];
  @State heroIdx: number = 0;
  @State routeStops: SiteInfo[] = [];
  @State favN: number = 0;
  @State noteN: number = 0;
  @State wSway: number = -7;
  @State mapFloat: boolean = false;
  // 「问」按钮的红点：没用过助手才挂，用过永久收掉
  @StorageLink('assistantSeen') askSeen: boolean = false;
  // 给右下角悬浮河小导发滚动信号：滚起来先收进边里，别压着内容
  private fabSignalAt: number = 0;

  aboutToAppear(): void {
    this.reload();
    // 数字文物卡里的中央文物缓摆，暗示进去是个能转的 3D 展台
    animateTo({
      duration: 5200, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate
    }, (): void => {
      this.wSway = 7;
    });
    // 地图窗里的红标轻轻浮，像导览图上正在定位的那一下
    animateTo({
      duration: 3000, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate
    }, (): void => {
      this.mapFloat = true;
    });
  }

  reload(): void {
    this.verse = verseOf(Date.now());
    this.reco = SiteRepo.get().recommend(MemoryStore.get().favIds(), MemoryStore.get().views, 4, '');
    this.hot = ContentRepo.get().hotGoods(4);
    this.events = ContentRepo.get().upcomingEvents(2);
    let all = SiteRepo.get().sites.slice();
    all.sort((a: SiteInfo, b: SiteInfo): number => siteU(a) - siteU(b));
    this.routeStops = all.slice(0, 3);
    this.favN = MemoryStore.get().favsActive().length;
    this.noteN = MemoryStore.get().notesActive().length;
  }

  shapeOf(id: string): string {
    let n = 0;
    for (let i = 0; i < id.length; i++) {
      n += id.charCodeAt(i);
    }
    return SHAPES[n % SHAPES.length];
  }

  firstEventId(): string {
    return this.events.length > 0 ? this.events[0].id : '';
  }

  eventLead(): string {
    if (this.events.length === 0) {
      return '沿河馆舍的排期正在整理';
    }
    return `${this.events[0].date}｜${this.events[0].title}`;
  }

  firstStopName(): string {
    return this.routeStops.length > 0 ? this.routeStops[0].name : '沿河遗存';
  }

  // 今日一句那一帧的底图：用诗句所属遗址的配图，换个日期换张图
  verseCover(): string {
    let v = this.verse;
    if (v === undefined) {
      return 'hero_river';
    }
    let s = SiteRepo.get().byId(v.siteId);
    if (s === undefined) {
      return coverOf('仰韶');
    }
    return s.cover.length > 0 ? s.cover : coverOf(s.eras[0]);
  }

  unread(): number {
    return StudioStore.get().unread(ContentRepo.get().feed().length);
  }

  // 点开邮件图标就当这一屏动态都看过了，角标跟着收掉
  readFeed(): void {
    let ids: string[] = [];
    for (let p of ContentRepo.get().feed()) {
      ids.push(p.id);
    }
    StudioStore.get().markFeedRead(ids);
  }

  doSearch(): void {
    goList(this.kw, '', '', '');
  }

  openFirstEvent(): void {
    let id = this.firstEventId();
    if (id.length === 0) {
      promptAction.showToast({ message: '暂时没有排期' });
      return;
    }
    goActivity(id);
  }

  tiles(): TileRec[] {
    return [
      { kind: 'scroll', title: '遗址档案', act: (): void => { goArchive(0); } },
      { kind: 'seal', title: '河图洛书', act: (): void => { goCheckin(); } },
      { kind: 'route', title: '行程规划', act: (): void => { goRoute(); } },
      { kind: 'lantern', title: '沿河活动', act: (): void => { this.openFirstEvent(); } },
      { kind: 'pot', title: '数字文物', act: (): void => { goStudio(1); } },
      { kind: 'slips', title: '趣味自测', act: (): void => { goQuiz('home'); } },
      { kind: 'net', title: '知识网络', act: (): void => { goTopic(); } },
      { kind: 'brush', title: '收藏笔记', act: (): void => { goArchive(1); } }
    ];
  }

  // 顶栏叠在海报上：半透明圆片托住白色符号，海报的色彩能透上来
  @Builder
  topBar() {
    Row({ space: 8 }) {
      Text('☰')
        .fontSize(fs(this.ts, 17))
        .fontColor(Color.White)
        .width(32)
        .height(32)
        .borderRadius(16)
        .backgroundColor('rgba(43,38,34,0.38)')
        .textAlign(TextAlign.Center)
        .onClick((): void => {
          openDrawer();
        })

      TextInput({ placeholder: '搜遗址、器物或纹样', text: this.kw })
        .height(34)
        .fontSize(fs(this.ts, 13))
        .fontColor(INK)
        .placeholderColor(SUB)
        .placeholderFont({ size: fs(this.ts, 13) })
        .backgroundColor('rgba(245,239,228,0.92)')
        .borderRadius(17)
        .border({ width: 1, color: 'rgba(229,218,198,0.9)' })
        .enterKeyType(EnterKeyType.Search)
        .layoutWeight(1)
        .onChange((v: string): void => {
          this.kw = v;
        })
        .onSubmit((key: EnterKeyType): void => {
          this.doSearch();
        })

      Stack({ alignContent: Alignment.TopEnd }) {
        Text('问')
          .fontSize(fs(this.ts, 13))
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium)
          .width(32)
          .height(32)
          .borderRadius(16)
          .backgroundColor(CLAY)
          .textAlign(TextAlign.Center)
        // 右上角这颗和右下角的球是同一个开关：assistantSheet 一置真，弹的都是同一个 FloatingAssistant
          .onClick((): void => {
            openAssistantSheet();
          })
        if (!this.askSeen) {
          // 还没用过助手时挂个红点，用过一次就永久收掉（askSeen 落在 preferences）
          Circle()
            .width(9)
            .height(9)
            .fill('#E2483B')
            .stroke(PAPER)
            .strokeWidth(1.5)
            .offset({ x: 3, y: -2 })
        }
      }
      .width(32)
      .height(32)

      Stack({ alignContent: Alignment.TopEnd }) {
        Text('✉')
          .fontSize(fs(this.ts, 16))
          .fontColor(Color.White)
          .width(32)
          .height(32)
          .borderRadius(16)
          .backgroundColor('rgba(43,38,34,0.38)')
          .textAlign(TextAlign.Center)
        if (this.unread() > 0) {
          Text(`${this.unread()}`)
            .fontSize(fs(this.ts, 9))
            .fontColor(Color.White)
            .backgroundColor(CLAY)
            .borderRadius(7)
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
        }
      }
      .width(32)
      .height(32)
      .onClick((): void => {
        this.readFeed();
        switchTab(2);
      })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 6 })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  // 海报上压一层由透到暗的渐变：白字直接压在示意图上会糊，垫一层才立得住
  @Builder
  scrim() {
    Column()
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 180,
        colors: [['rgba(43,38,34,0.16)', 0], ['rgba(43,38,34,0)', 0.34],
          ['rgba(43,38,34,0.34)', 0.66], ['rgba(43,38,34,0.72)', 1]]
      })
      .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  promo(title: string, lead: string, img: string, act: () => void) {
    Stack({ alignContent: Alignment.BottomStart }) {
      Image(coverRes(img))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
      this.scrim()
      Column({ space: 3 }) {
        Text(title)
          .fontSize(fs(this.ts, 19))
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
          .letterSpacing(2)
        Text(lead)
          .fontSize(fs(this.ts, 11))
          .fontColor('#EFE6D6')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 16, right: 60, top: 14, bottom: 42 })
    }
    .width('100%')
    .height('100%')
    .onClick(act)
  }

  // 今日一句收进海报第二帧：首页少一张卡，诗句反而更醒目
  @Builder
  verseFrame() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Image(coverRes(this.verseCover()))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
      this.scrim()
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Text('今日一句')
            .fontSize(fs(this.ts, 9))
            .fontColor('#3A2A1E')
            .backgroundColor(LOESS)
            .borderRadius(7)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          Text(this.verse!.real ? '库内收录' : '拟咏')
            .fontSize(fs(this.ts, 9))
            .fontColor('#F0E7D8')
            .borderRadius(7)
            .border({ width: 1, color: 'rgba(240,231,216,0.6)' })
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
        }
        Text(this.verse!.text)
          .fontSize(fs(this.ts, 16))
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium)
          .lineHeight(fs(this.ts, 24))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 6 }) {
          Text(this.verse!.from).fontSize(fs(this.ts, 10)).fontColor('#E3D8C6')
          Blank()
          Text(verseSiteName(this.verse!) + ' ›').fontSize(fs(this.ts, 10)).fontColor('#F4E9D8')
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 16, right: 60, top: 14, bottom: 42 })
    }
    .width('100%')
    .height('100%')
    .onClick((): void => {
      goDetail(this.verse!.siteId);
    })
  }

  // 通栏海报：四帧轮播，右下角一枚 n/4 的页码片，照参考图那个位置
  @Builder
  hero() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Swiper() {
        this.promo('黄河续响平台', '把这条河装进口袋 · 20 处沿河遗存', 'hero_river', (): void => {
          goArchive(0);
        })
        if (this.verse !== undefined) {
          this.verseFrame()
        }
        this.promo('彩陶工坊', '挑一件器形，描一组纹样', 'era_yangshao', (): void => {
          goPottery();
        })
        this.promo('沿河排期', this.eventLead(), 'era_hantang', (): void => {
          this.openFirstEvent();
        })
      }
      .width('100%')
      .height('100%')
      .autoPlay(true)
      .interval(4600)
      .loop(true)
      .cachedCount(2)
      .onChange((i: number): void => {
        this.heroIdx = i;
      })

      Text(`${this.heroIdx + 1}/4`)
        .fontSize(fs(this.ts, 10))
        .fontColor('#F0E7D8')
        .backgroundColor('rgba(43,38,34,0.55)')
        .borderRadius(10)
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .margin({ right: 14, bottom: 40 })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height(286)
    .clip(true)
  }

  // 大卡右上角的视觉锚点：一束简牍＋一道编绳＋一枚陶印
  @Builder
  archiveArt() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Stack({ alignContent: Alignment.Center }) {
        Row({ space: 4 }) {
          Column().width(6).height(30).borderRadius(3).backgroundColor('#D9C9A8')
          Column().width(6).height(30).borderRadius(3).backgroundColor('#CBB488')
          Column().width(6).height(30).borderRadius(3).backgroundColor('#D9C9A8')
          Column().width(6).height(30).borderRadius(3).backgroundColor('#CBB488')
        }
        Column().width(38).height(3).borderRadius(1.5).backgroundColor(CLAY)
      }
      .width(40).height(32)
      Column().width(15).height(15).borderRadius(4).backgroundColor(CLAY)
    }
    .width(44).height(36)
    .opacity(0.92)
  }

  // 地图导览子卡：卡里开一扇「地图窗」，露一段手绘导览图 + 一枚浮动的红标，
  // 点整卡进 ArkWeb 手绘地图（发现/建筑/展览/打卡/餐饮/文创/卫生间/游客服务全在里头）
  @Builder
  mapCard() {
    Column({ space: 7 }) {
      Text('地图导览')
        .fontSize(fs(this.ts, 15))
        .fontColor(Color.White)
        .fontWeight(FontWeight.Bold)
        .letterSpacing(1)
      Text('八类地点 · 手绘导览')
        .fontSize(fs(this.ts, 9))
        .fontColor('rgba(233,242,240,0.85)')
      Stack({ alignContent: Alignment.Center }) {
        Image($rawfile('experience/atlas.png'))
          .width('100%')
          .height(52)
          .objectFit(ImageFit.Cover)
          .borderRadius(8)
          .translate({ y: this.mapFloat ? -3 : 3 })
        Text('●')
          .fontSize(fs(this.ts, 15))
          .fontColor('#A93135')
          .translate({ x: 26, y: this.mapFloat ? -16 : -8 })
      }
      .width('100%')
      .height(52)
      .clip(true)
      .border({ width: 1, color: 'rgba(255,255,255,0.35)' })

      Text('打开导览 ›')
        .fontSize(fs(this.ts, 10))
        .fontColor('#E9F2F0')
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(12)
    .borderRadius(12)
    .linearGradient({ angle: 160, colors: [['#4E7E86', 0], ['#2F5A63', 1]] })
    .onClick((): void => {
      goExperience('map');
    })
  }

  // 数字文物入口卡：整卡一个入口，卡里三件文物做微缩 3D 展台（中央件缓摆），
  // 底色调成纸色让文物边缘自然融进卡面，点整卡进展台页
  @Builder
  workshopCard() {
    Column({ space: 6 }) {
      Text('数字文物')
        .fontSize(fs(this.ts, 15))
        .fontColor(INK)
        .fontWeight(FontWeight.Bold)
        .letterSpacing(1)
      Text('3D 展台 · 彩陶 · 教程')
        .fontSize(fs(this.ts, 9))
        .fontColor(SUB)
      Stack({ alignContent: Alignment.Center }) {
        // 展台净底：与文物图烘进去的纸色同值，边缘才融得干净
        Column()
          .width('100%')
          .height(58)
          .borderRadius(8)
          .backgroundColor('#F5EFE4')
        Image(coverRes('relic_qingtong'))
          .width(30).height(36).objectFit(ImageFit.Contain)
          .opacity(0.72).rotate({ x: 0, y: 1, z: 0, angle: 38 }).translate({ x: -25 })
        Image(coverRes('relic_sancai'))
          .width(30).height(36).objectFit(ImageFit.Contain)
          .opacity(0.72).rotate({ x: 0, y: 1, z: 0, angle: -38 }).translate({ x: 25 })
        Image(coverRes('relic_caitao'))
          .width(48).height(52).objectFit(ImageFit.Contain)
          .rotate({ x: 0, y: 1, z: 0, angle: this.wSway })
          .zIndex(5)
      }
      .width('100%')
      .height(58)
      Row({ space: 4 }) {
        Text('进展台').fontSize(fs(this.ts, 10)).fontColor(CLAY)
        Text('›').fontSize(fs(this.ts, 11)).fontColor(CLAY)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1.12)
    .padding(12)
    .borderRadius(12)
    .linearGradient({ angle: 160, colors: [['#F8F1E3', 0], ['#EDE0C8', 1]] })
    .border({ width: 1, color: '#E0D2B8' })
    .onClick((): void => {
      goStudio(1);
    })
  }

  // 档案大卡：标题「黄河续响平台」，双卡 + 我的档案行，卡顶压住海报下沿
  @Builder
  todayCard() {
    Column({ space: 11 }) {
      Row() {
        Column({ space: 2 }) {
          Text('黄河续响平台')
            .fontSize(fs(this.ts, 19))
            .fontColor(INK)
            .fontWeight(FontWeight.Bold)
            .letterSpacing(2)
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        this.archiveArt()
      }
      .width('100%')

      Row({ space: 10 }) {
        this.mapCard()
        this.workshopCard()
      }
      .width('100%')

      Row({ space: 8 }) {
        Stack({ alignContent: Alignment.Center }) {
          Column().width(14).height(14).borderRadius(4).backgroundColor(CLAY)
          Column().width(6).height(6).borderRadius(1.5).backgroundColor(PAPER)
        }
        .width(16).height(16)
        Text('我的档案 · 收藏与笔记')
          .fontSize(fs(this.ts, 12))
          .fontColor(INK)
          .fontWeight(FontWeight.Medium)
        Blank()
        Text(`${this.favN} 藏 · ${this.noteN} 笔 ›`)
          .fontSize(fs(this.ts, 11))
          .fontColor(SUB)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 9, bottom: 9 })
      .borderRadius(10)
      .backgroundColor('#EFE6D5')
      .onClick((): void => {
        goArchive(1);
      })
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(16)
    .margin({ top: -26 })
    .shadow({ radius: 14, color: 'rgba(43,38,34,0.14)', offsetY: -4 })
  }

  @Builder
  tileGrid() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.tiles(), (t: TileRec): void => {
        RelicTile({ kind: t.kind, title: t.title, act: t.act })
      }, (t: TileRec): string => t.kind)
    }
    .width('100%')
    .padding({ top: 6, bottom: 2 })
  }

  @Builder
  head(title: string, hint: string, act: () => void) {
    Row() {
      Text(title)
        .fontSize(fs(this.ts, 16))
        .fontColor(INK)
        .fontWeight(FontWeight.Medium)
      Blank()
      if (hint.length > 0) {
        Text(hint)
          .fontSize(fs(this.ts, 11))
          .fontColor(SUB)
        Text(' ›')
          .fontSize(fs(this.ts, 13))
          .fontColor(SUB)
      }
    }
    .width('100%')
    .padding({ top: 4, bottom: 2 })
    .onClick(act)
  }

  // 为你推荐：两列图卡，每张都写清为什么推给你
  @Builder
  recoCard(sg: Suggestion, i: number) {
    Column({ space: 5 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Image(coverRes(sg.site.cover.length > 0 ? sg.site.cover : coverOf(sg.site.eras[0])))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
        Text(sg.site.eras[0])
          .fontSize(fs(this.ts, 9))
          .fontColor('#F0E7D8')
          .backgroundColor('rgba(43,38,34,0.42)')
          .borderRadius(7)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .margin(8)
      }
      .width('100%')
      .height(104)
      .borderRadius(10)
      .clip(true)

      Text(sg.site.name)
        .fontSize(fs(this.ts, 13))
        .fontColor(INK)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(`${sg.site.city} · ${sg.site.types.join('/')}`)
        .fontSize(fs(this.ts, 10))
        .fontColor(SUB)
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      // 有偏好才写"为什么推给你"；冷启动四张卡理由是同一句，写出来像 bug，不如放摘要
      if (sg.score > 0) {
        Text(sg.reason)
          .fontSize(fs(this.ts, 10))
          .fontColor(CLAY)
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      } else {
        Text(sg.site.summary)
          .fontSize(fs(this.ts, 10))
          .fontColor(SUB)
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('48%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 8, left: 8, right: 8, bottom: 10 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
    .margin({ right: i % 2 === 0 ? '4%' : 0, bottom: 10 })
    .onClick((): void => {
      goDetail(sg.site.id);
    })
  }

  @Builder
  recoGrid() {
    Column({ space: 8 }) {
      this.head('为你推荐', '',
        (): void => {
          goList('', '', '', '');
        })
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.reco, (sg: Suggestion, i: number): void => {
          this.recoCard(sg, i)
        }, (sg: Suggestion): string => sg.site.id)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 文创市集：商品有实拍图就贴图，没图的才让 ArtCover 现画
  @Builder
  shopCard(g: Goods, i: number) {
    Column({ space: 5 }) {
      Column() {
        ArtCover({ palette: g.palette, shape: this.shapeOf(g.id), seed: i + 2, label: g.cat, img: g.img })
      }
      .width('100%')
      .height(104)
      .borderRadius(10)
      .clip(true)

      Text(g.name)
        .fontSize(fs(this.ts, 13))
        .fontColor(INK)
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row({ space: 6 }) {
        Text('¥' + moneyText(g.price))
          .fontSize(fs(this.ts, 12))
          .fontColor(CLAY)
          .fontWeight(FontWeight.Medium)
        // 出土地那串字给不了固定宽度就会顶出格子，压进剩余空间里省略
        Text(g.origin)
          .fontSize(fs(this.ts, 10))
          .fontColor(RIVER)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      }
      .width('100%')
    }
    .width('48%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 8, left: 8, right: 8, bottom: 10 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
    .margin({ right: i % 2 === 0 ? '4%' : 0, bottom: 10 })
    .onClick((): void => {
      switchTab(1);
    })
  }

  @Builder
  shopGrid() {
    Column({ space: 8 }) {
      this.head('文创市集', `${ContentRepo.get().goods.length} 件`, (): void => {
        switchTab(1);
      })
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.hot, (g: Goods, i: number): void => {
          this.shopCard(g, i)
        }, (g: Goods): string => g.id)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PatternBg()
      Column() {
        Scroll() {
          Column() {
            this.hero()

            Column({ space: 14 }) {
              this.todayCard()
              this.tileGrid()
              this.recoGrid()
              this.shopGrid()
            }
            .width('100%')
            // 留出右下角悬浮河小导的位置，滚到底时页脚不会被它压住
            .padding({ left: 14, right: 14, bottom: 92 })
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .onDidScroll((xOffset: number, yOffset: number, scrollState: ScrollState): void => {
          if (yOffset === 0) {
            return;
          }
          // 每帧都写 AppStorage 没必要，80ms 一次足够让悬浮球判定"还在滚"
          let now = Date.now();
          if (now - this.fabSignalAt < 80) {
            return;
          }
          this.fabSignalAt = now;
          AppStorage.setOrCreate('fabScrollAt', now);
        })
      }
      .width('100%')
      .height('100%')

      this.topBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
