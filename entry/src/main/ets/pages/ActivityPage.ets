import { router, promptAction } from '@kit.ArkUI';
import { ContentRepo } from '../service/ContentRepo';
import { StudioStore } from '../service/StudioStore';
import { SiteRepo } from '../service/SiteRepo';
import { EventInfo, Goods } from '../model/Models';
import { fs, INK, SUB, LOESS, CLAY, RIVER, dayText, moneyText } from '../common/Theme';
import { params, goDetail, RouteParam } from '../common/Nav';
import { ArtCover } from '../view/ArtCover';

interface CalCell {
  key: string;
  day: number;
  hasEvent: boolean;
  isToday: boolean;
  isChecked: boolean;
}

const GOALS: string[] = ['黄', '河', '记', '忆'];
const WEEK: string[] = ['一', '二', '三', '四', '五', '六', '日'];

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

@Entry
@Component
struct ActivityPage {
  @StorageLink('textScale') ts: number = 1;
  @StorageLink('studioRev') @Watch('syncMine') studioRev: number = 0;
  @State topId: string = '';
  @State selDay: string = '';
  @State monthOff: number = 0;
  @State box: Goods | undefined = undefined;
  @State dice: number = 1;
  @State signed: boolean = false;
  @State streakN: number = 0;
  @State checkinN: number = 0;
  @State mineChars: string[] = [];

  syncMine(): void {
    let st = StudioStore.get();
    this.signed = st.checkedToday();
    this.streakN = st.streak();
    this.checkinN = st.checkins.length;
    this.mineChars = st.chars.slice();
  }

  aboutToAppear(): void {
    let id: string = '';
    try {
      let p: RouteParam = params();
      if (p.eventId !== undefined) {
        id = p.eventId;
      }
    } catch (e) {
      console.warn('活动页无入参');
    }
    this.topId = id;
    if (id.length > 0) {
      let e = ContentRepo.get().eventOf(id);
      if (e !== undefined) {
        let now = new Date();
        let ey = Number(e.date.substring(0, 4));
        let em = Number(e.date.substring(5, 7));
        this.monthOff = (ey - now.getFullYear()) * 12 + (em - 1 - now.getMonth());
        this.selDay = e.date;
      }
    }
    this.syncMine();
  }

  monthDate(): Date {
    let now = new Date();
    return new Date(now.getFullYear(), now.getMonth() + this.monthOff, 1);
  }

  monthLabel(): string {
    let d = this.monthDate();
    return `${d.getFullYear()}年${d.getMonth() + 1}月`;
  }

  monthPrefix(): string {
    let d = this.monthDate();
    return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}`;
  }

  cells(): CalCell[] {
    let d = this.monthDate();
    let y = d.getFullYear();
    let m = d.getMonth();
    let lead = (d.getDay() + 6) % 7;
    let total = new Date(y, m + 1, 0).getDate();
    let st = StudioStore.get();
    let todayKey = st.today();
    let evs = ContentRepo.get().events;
    let out: CalCell[] = [];
    for (let i = 0; i < lead; i++) {
      let blank: CalCell = { key: `x${i}`, day: 0, hasEvent: false, isToday: false, isChecked: false };
      out.push(blank);
    }
    for (let n = 1; n <= total; n++) {
      let key = `${y}-${pad2(m + 1)}-${pad2(n)}`;
      let hit = evs.filter((e: EventInfo): boolean => e.date === key).length > 0;
      let c: CalCell = {
        key: key,
        day: n,
        hasEvent: hit,
        isToday: key === todayKey,
        isChecked: st.checkins.indexOf(key) >= 0
      };
      out.push(c);
    }
    return out;
  }

  weeks(): CalCell[][] {
    let flat = this.cells();
    let out: CalCell[][] = [];
    for (let i = 0; i < flat.length; i += 7) {
      out.push(flat.slice(i, i + 7));
    }
    return out;
  }

  tapDay(c: CalCell): void {
    if (c.day <= 0) {
      return;
    }
    if (!c.hasEvent) {
      this.selDay = '';
      return;
    }
    this.selDay = this.selDay === c.key ? '' : c.key;
  }

  shownEvents(): EventInfo[] {
    let day = this.selDay;
    let src = ContentRepo.get().events.filter((e: EventInfo): boolean => day.length === 0 || e.date === day);
    if (this.topId.length === 0) {
      return src;
    }
    let out: EventInfo[] = [];
    for (let e of src) {
      if (e.id === this.topId) {
        out.push(e);
      }
    }
    for (let e of src) {
      if (e.id !== this.topId) {
        out.push(e);
      }
    }
    return out;
  }

  doCheckin(): void {
    let st = StudioStore.get();
    if (st.checkedToday()) {
      return;
    }
    if (!st.checkin()) {
      return;
    }
    let got = '';
    for (let c of GOALS) {
      if (st.addChar(c)) {
        got = c;
        break;
      }
    }
    promptAction.showToast({
      message: got.length > 0 ? `签到成功，拿到「${got}」字` : '签到成功，四个字都已集齐'
    });
  }

  drawBox(): void {
    let gs = ContentRepo.get().goods;
    if (gs.length === 0) {
      promptAction.showToast({ message: '文创数据未随包提供' });
      return;
    }
    let i = Math.floor(Math.random() * gs.length);
    this.dice = i + 1;
    this.box = gs[i];
  }

  kindColor(kind: string): string {
    if (kind === '集字') {
      return CLAY;
    }
    if (kind === '研学') {
      return RIVER;
    }
    if (kind === '盲盒') {
      return LOESS;
    }
    return INK;
  }

  owned(): number {
    let n = 0;
    for (let c of GOALS) {
      if (this.mineChars.indexOf(c) >= 0) {
        n = n + 1;
      }
    }
    return n;
  }

  @Builder
  topBar() {
    Row({ space: 10 }) {
      Text('‹ 返回')
        .fontSize(fs(this.ts, 14))
        .fontColor(INK)
        .padding({ left: 10, right: 12, top: 5, bottom: 5 })
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(14)
        .onClick((): void => {
          router.back();
        })
      Text('活动')
        .fontSize(fs(this.ts, 20))
        .fontColor(INK)
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 6 })
  }

  @Builder
  signCard() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text('今天').fontSize(fs(this.ts, 11)).fontColor(SUB)
          Text(dayText(Date.now())).fontSize(fs(this.ts, 17)).fontColor(INK).fontWeight(FontWeight.Bold)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column({ space: 2 }) {
          Text('连续签到').fontSize(fs(this.ts, 11)).fontColor(SUB)
          Text(`${this.streakN} 天`).fontSize(fs(this.ts, 17)).fontColor(CLAY).fontWeight(FontWeight.Bold)
        }
        .alignItems(HorizontalAlign.End)

        Button(this.signed ? '今日已签' : '签到')
          .fontSize(fs(this.ts, 13))
          .fontColor(this.signed ? SUB : Color.White)
          .backgroundColor(this.signed ? '#D9CDB6' : CLAY)
          .enabled(!this.signed)
          .onClick((): void => {
            this.doCheckin();
          })
      }
      .width('100%')

      Text(`累计签到 ${this.checkinN} 次，签到会拿到一个还没集到的字`)
        .fontSize(fs(this.ts, 11))
        .fontColor(SUB)
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
  }

  @Builder
  cellBox(c: CalCell) {
    Column({ space: 2 }) {
      if (c.day > 0) {
        Text(`${c.day}`)
          .fontSize(fs(this.ts, 13))
          .fontColor(c.key === this.selDay ? Color.White : (c.isToday ? CLAY : INK))
          .fontWeight(c.isToday ? FontWeight.Bold : FontWeight.Normal)
        Row({ space: 2 }) {
          if (c.hasEvent) {
            Circle().width(4).height(4).fill(LOESS)
          }
          if (c.isChecked) {
            Circle().width(4).height(4).fill(CLAY)
          }
        }
        .height(6)
      } else {
        Text(' ')
          .fontSize(fs(this.ts, 13))
        Column().height(6)
      }
    }
    .layoutWeight(1)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(8)
    .backgroundColor(c.key === this.selDay ? CLAY : (c.isToday ? '#F3E7D3' : Color.Transparent))
    .onClick((): void => {
      this.tapDay(c);
    })
  }

  @Builder
  calCard() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(this.monthLabel()).fontSize(fs(this.ts, 15)).fontColor(INK).fontWeight(FontWeight.Medium).layoutWeight(1)
        Text('‹ 上月')
          .fontSize(fs(this.ts, 12))
          .fontColor(SUB)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .onClick((): void => {
            this.monthOff = this.monthOff - 1;
            this.selDay = '';
          })
        Text('下月 ›')
          .fontSize(fs(this.ts, 12))
          .fontColor(SUB)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .onClick((): void => {
            this.monthOff = this.monthOff + 1;
            this.selDay = '';
          })
      }
      .width('100%')

      Row({ space: 0 }) {
        ForEach(WEEK, (w: string): void => {
          Column() {
            Text(w).fontSize(fs(this.ts, 11)).fontColor(SUB)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
        }, (w: string): string => w)
      }
      .width('100%')

      ForEach(this.weeks(), (wk: CalCell[], wi: number): void => {
        Row({ space: 0 }) {
          ForEach(wk, (c: CalCell): void => {
            this.cellBox(c)
          }, (c: CalCell): string => `${wk.length}_${c.key}_${this.selDay === c.key}`)
        }
        .width('100%')
      }, (wk: CalCell[], wi: number): string => `${this.monthPrefix()}_w${wi}`)

      Row({ space: 10 }) {
        Circle().width(5).height(5).fill(LOESS)
        Text('有活动').fontSize(fs(this.ts, 10)).fontColor(SUB)
        Circle().width(5).height(5).fill(CLAY)
        Text('已签到').fontSize(fs(this.ts, 10)).fontColor(SUB)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 4 })
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
  }

  @Builder
  charBox(c: string) {
    Column() {
      Text(this.mineChars.indexOf(c) >= 0 ? c : '?')
        .fontSize(fs(this.ts, 22))
        .fontColor(this.mineChars.indexOf(c) >= 0 ? Color.White : SUB)
        .fontWeight(FontWeight.Bold)
    }
    .layoutWeight(1)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(10)
    .backgroundColor(this.mineChars.indexOf(c) >= 0 ? CLAY : Color.Transparent)
    .border({
      width: 1,
      color: this.mineChars.indexOf(c) >= 0 ? CLAY : '#C9B79A',
      style: this.mineChars.indexOf(c) >= 0 ? BorderStyle.Solid : BorderStyle.Dashed
    })
  }

  @Builder
  charCard() {
    Column({ space: 10 }) {
      Text('集字有礼').fontSize(fs(this.ts, 16)).fontColor(INK).fontWeight(FontWeight.Medium)
      Row({ space: 10 }) {
        ForEach(GOALS, (c: string): void => {
          this.charBox(c)
        }, (c: string): string => c)
      }
      .width('100%')

      Text(`已集 ${this.owned()}/4`).fontSize(fs(this.ts, 13)).fontColor(SUB)
      if (this.owned() >= GOALS.length) {
        Text('已集齐，可到「我的」领取纪念卡')
          .fontSize(fs(this.ts, 12))
          .fontColor(CLAY)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
  }

  @Builder
  eventCard(e: EventInfo) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(e.kind)
          .fontSize(fs(this.ts, 10))
          .fontColor(Color.White)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .borderRadius(6)
          .backgroundColor(this.kindColor(e.kind))
        Text(e.title)
          .fontSize(fs(this.ts, 15))
          .fontColor(INK)
          .fontWeight(FontWeight.Medium)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')

      Text(`${e.date} · ${e.place}`).fontSize(fs(this.ts, 12)).fontColor(SUB).width('100%')
      Text(`${e.fee} · ${e.seats}`).fontSize(fs(this.ts, 12)).fontColor(CLAY).width('100%')
      Text(e.brief)
        .fontSize(fs(this.ts, 13))
        .fontColor(INK)
        .lineHeight(fs(this.ts, 21))
        .width('100%')
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (e.chars.length > 0) {
        Text(`本次可集：${e.chars.join(' ')}`).fontSize(fs(this.ts, 11)).fontColor(SUB).width('100%')
      }

      Row({ space: 10 }) {
        Button('报名')
          .fontSize(fs(this.ts, 13))
          .fontColor(Color.White)
          .backgroundColor(CLAY)
          .onClick((): void => {
            promptAction.showToast({ message: '报名已登记，请留意活动提醒' });
          })
        if (SiteRepo.get().byId(e.siteId) !== undefined) {
          Button('去遗址')
            .fontSize(fs(this.ts, 13))
            .fontColor(INK)
            .backgroundColor($r('app.color.line'))
            .onClick((): void => {
              goDetail(e.siteId);
            })
        }
        Blank()
        if (e.id === this.topId) {
          Text('刚选的活动').fontSize(fs(this.ts, 10)).fontColor(SUB)
        }
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
  }

  @Builder
  boxCard() {
    Column({ space: 10 }) {
      Text('盲盒抽一件').fontSize(fs(this.ts, 16)).fontColor(INK).fontWeight(FontWeight.Medium)
      Text('随机从随包文创里取一件').fontSize(fs(this.ts, 12)).fontColor(SUB)
      Button('抽一次')
        .fontSize(fs(this.ts, 14))
        .fontColor(Color.White)
        .backgroundColor(LOESS)
        .onClick((): void => {
          this.drawBox();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
  }

  @Builder
  prizeCard(g: Goods) {
    Column({ space: 10 }) {
      Column() {
        ArtCover({ palette: g.palette, shape: 'box', seed: this.dice, label: g.cat, img: g.img })
      }
      .width('100%')
      .height(150)
      .borderRadius(10)
      .clip(true)

      Text(g.name).fontSize(fs(this.ts, 17)).fontColor(INK).fontWeight(FontWeight.Bold)
      Text(`${g.sub} · ${g.era}`).fontSize(fs(this.ts, 12)).fontColor(SUB)
      Text(`￥${moneyText(g.price)}`).fontSize(fs(this.ts, 16)).fontColor(CLAY)
      Text(`${g.origin} · ${g.tags.join(' ')}`).fontSize(fs(this.ts, 11)).fontColor(SUB)

      Row({ space: 10 }) {
        Button(StudioStore.get().inCart(g.id) ? '已在清单' : '加入清单')
          .fontSize(fs(this.ts, 13))
          .fontColor(StudioStore.get().inCart(g.id) ? SUB : Color.White)
          .backgroundColor(StudioStore.get().inCart(g.id) ? '#D9CDB6' : LOESS)
          .onClick((): void => {
            StudioStore.get().toggleCart(g.id);
          })
        Button('关闭')
          .fontSize(fs(this.ts, 13))
          .fontColor(INK)
          .backgroundColor($r('app.color.line'))
          .onClick((): void => {
            this.box = undefined;
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('78%')
    .padding(16)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(14)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 12 }) {
        this.topBar()

        Scroll() {
          Column({ space: 12 }) {
            this.signCard()
            this.calCard()
            this.charCard()

            Column({ space: 8 }) {
              Row({ space: 8 }) {
                Text('活动安排').fontSize(fs(this.ts, 16)).fontColor(INK).fontWeight(FontWeight.Medium).layoutWeight(1)
                if (this.selDay.length > 0) {
                  Text(`${this.selDay} · ${this.shownEvents().length} 场`).fontSize(fs(this.ts, 11)).fontColor(CLAY)
                  Text('显示全部')
                    .fontSize(fs(this.ts, 12))
                    .fontColor(CLAY)
                    .onClick((): void => {
                      this.selDay = '';
                    })
                }
              }
              .width('100%')

              if (this.shownEvents().length === 0) {
                Text('这个月没有排活动，点有圆点的日期换个月看看')
                  .fontSize(fs(this.ts, 12)).fontColor(SUB).width('100%')
              }

              ForEach(this.shownEvents(), (e: EventInfo): void => {
                this.eventCard(e)
              }, (e: EventInfo): string => `${e.id}_${this.selDay}_${this.topId}`)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            this.boxCard()
          }
          .width('100%')
          .padding({ left: 14, right: 14 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')

      if (this.box !== undefined) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(43,38,34,0.52)')
          .onClick((): void => {
            this.box = undefined;
          })
        this.prizeCard(this.box!)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
