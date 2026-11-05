import { router } from '@kit.ArkUI';
import { SiteInfo } from '../model/Models';
import { SiteRepo } from '../service/SiteRepo';
import { StudioStore } from '../service/StudioStore';
import { siteU } from '../common/River';
import { INK, SUB, LOESS, CLAY, LINE, ERAS, CITIES, fs } from '../common/Theme';
import { goDetail } from '../common/Nav';

@Entry
@Component
struct RoutePage {
  
  @StorageLink('textScale') ts: number = 1;
  @StorageLink('studioRev') rev: number = 0;
  @State era: string = '';
  @State city: string = '';
  @State stops: SiteInfo[] = [];

  aboutToAppear(): void {
    this.compute();
  }

  compute(): void {
    let all = SiteRepo.get().sites;
    let hit: SiteInfo[] = [];
    for (let s of all) {
      if (this.era.length > 0 && s.eras.indexOf(this.era) < 0) {
        continue;
      }
      if (this.city.length > 0 && s.city !== this.city) {
        continue;
      }
      hit.push(s);
    }
    hit.sort((a: SiteInfo, b: SiteInfo): number => {
      let d = siteU(a) - siteU(b);
      if (d !== 0) {
        return d;
      }
      return CITIES.indexOf(a.city) - CITIES.indexOf(b.city);
    });
    this.stops = hit;
  }

  checked(id: string): boolean {
    if (this.rev < 0) {
      return false;
    }
    return StudioStore.get().checkedSiteIds().indexOf(id) >= 0;
  }

  lead(): string {
    if (this.stops.length === 0) {
      return '这个组合下暂时没有点位，换个条件试试';
    }
    let a = this.stops[0].eras[0];
    let b = this.stops[this.stops.length - 1].eras[0];
    if (this.city.length > 0 && this.era.length > 0) {
      return `${this.city}的${this.era}一段，顺河 ${this.stops.length} 站`;
    }
    if (this.city.length > 0) {
      return `${this.city}境内，从${a}走到${b}，共 ${this.stops.length} 站`;
    }
    if (this.era.length > 0) {
      return `只走${this.era}这一段，${this.stops.length} 站摊在河上`;
    }
    return `从${a}到${b}，全程 ${this.stops.length} 站顺河走`;
  }

  @Builder
  eraChip(text: string) {
    Text(text)
      .fontSize(fs(this.ts, 12))
      .fontColor(this.eraOn(text) ? Color.White : INK)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(this.eraOn(text) ? CLAY : $r('app.color.card_bg'))
      .border({ width: 1, color: this.eraOn(text) ? CLAY : LINE })
      .onClick((): void => {
        this.era = text === '全部' ? '' : (this.era === text ? '' : text);
        this.compute();
      })
  }

  @Builder
  cityChip(text: string) {
    Text(text)
      .fontSize(fs(this.ts, 12))
      .fontColor(this.cityOn(text) ? Color.White : INK)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(this.cityOn(text) ? CLAY : $r('app.color.card_bg'))
      .border({ width: 1, color: this.cityOn(text) ? CLAY : LINE })
      .onClick((): void => {
        this.city = text === '全部' ? '' : (this.city === text ? '' : text);
        this.compute();
      })
  }

  eraOn(text: string): boolean {
    return text === '全部' ? this.era.length === 0 : this.era === text;
  }

  cityOn(text: string): boolean {
    return text === '全部' ? this.city.length === 0 : this.city === text;
  }

  @Builder
  routeStrip() {
    Stack() {
      Column()
        .width('86%')
        .height(2)
        .backgroundColor(LINE)
      Row() {
        ForEach(this.stops.length > 8 ? this.stops.slice(0, 8) : this.stops, (s: SiteInfo): void => {
          Column()
            .width(11)
            .height(11)
            .borderRadius(6)
            .backgroundColor(this.checked(s.id) ? CLAY : $r('app.color.card_bg'))
            .border({ width: 1.5, color: this.checked(s.id) ? CLAY : LOESS })
        }, (s: SiteInfo): string => 'dot_' + s.id)
      }
      .width('86%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .height(26)
  }

  @Builder
  stopRow(s: SiteInfo, i: number) {
    Row({ space: 10 }) {
      Stack() {
        Column()
          .width(30)
          .height(30)
          .borderRadius(7)
          .backgroundColor(this.checked(s.id) ? CLAY : '#F1E7D5')
          .border({ width: 1, color: this.checked(s.id) ? CLAY : LINE })
        Text(`${i + 1}`)
          .fontSize(fs(this.ts, 13))
          .fontColor(this.checked(s.id) ? Color.White : CLAY)
          .fontWeight(FontWeight.Bold)
      }
      .width(30)
      .height(30)

      Column({ space: 3 }) {
        Row({ space: 6 }) {
          Text(s.name)
            .fontSize(fs(this.ts, 14))
            .fontColor(INK)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.checked(s.id)) {
            Text('已盖章')
              .fontSize(fs(this.ts, 9))
              .fontColor(CLAY)
              .borderRadius(6)
              .border({ width: 1, color: CLAY })
              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          }
        }
        .width('100%')

        Text(`${s.city} · ${s.eras.join('/')} · ${s.types.join('/')}`)
          .fontSize(fs(this.ts, 10))
          .fontColor(SUB)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(s.summary)
          .fontSize(fs(this.ts, 11))
          .fontColor(SUB)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('›')
        .fontSize(fs(this.ts, 15))
        .fontColor(SUB)
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      goDetail(s.id);
    })
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Text('‹ 返回')
          .fontSize(fs(this.ts, 15))
          .fontColor(CLAY)
          .onClick((): void => {
            router.back();
          })
        Text('行程规划')
          .fontSize(fs(this.ts, 18))
          .fontColor(INK)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        Text(`${this.stops.length} 站`)
          .fontSize(fs(this.ts, 14))
          .fontColor(LOESS)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 8 })

      Scroll() {
        Column({ space: 12 }) {
          Column({ space: 8 }) {
            Row({ space: 6 }) {
              Text('年代')
                .fontSize(fs(this.ts, 11))
                .fontColor(SUB)
                .width(30)
              Scroll() {
                Row({ space: 7 }) {
                  this.eraChip('全部')
                  ForEach(ERAS, (e: string): void => {
                    this.eraChip(e)
                  }, (e: string): string => 'era_' + e)
                }
                .padding({ right: 10 })
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .layoutWeight(1)
            }
            .width('100%')

            Row({ space: 6 }) {
              Text('城市')
                .fontSize(fs(this.ts, 11))
                .fontColor(SUB)
                .width(30)
              Scroll() {
                Row({ space: 7 }) {
                  this.cityChip('全部')
                  ForEach(CITIES, (c: string): void => {
                    this.cityChip(c)
                  }, (c: string): string => 'city_' + c)
                }
                .padding({ right: 10 })
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .layoutWeight(1)
            }
            .width('100%')
          }
          .width('100%')
          .padding(14)
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(14)
          .alignItems(HorizontalAlign.Start)

          Column({ space: 8 }) {
            Text(this.lead())
              .fontSize(fs(this.ts, 13))
              .fontColor(INK)
              .fontWeight(FontWeight.Medium)
              .width('100%')
            if (this.stops.length > 0) {
              this.routeStrip()
            }
          }
          .width('100%')
          .padding(14)
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(14)
          .alignItems(HorizontalAlign.Start)

          Column({ space: 8 }) {
            ForEach(this.stops, (s: SiteInfo, i: number): void => {
              this.stopRow(s, i)
            }, (s: SiteInfo): string => 'stop_' + s.id)
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 14, right: 14 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
