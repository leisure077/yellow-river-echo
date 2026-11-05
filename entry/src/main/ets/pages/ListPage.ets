import { router } from '@kit.ArkUI';
import { SiteRepo } from '../service/SiteRepo';
import { SiteInfo } from '../model/Models';
import { fs, ERAS, CITIES, TYPES, INK, SUB, CLAY, RIVER } from '../common/Theme';
import { params } from '../common/Nav';
import { SiteCard } from '../view/SiteCard';

interface FilterRow {
  title: string;
  which: string;
  options: string[];
}

const ROWS: FilterRow[] = [
  { title: '年代', which: 'era', options: ERAS },
  { title: '城市', which: 'city', options: CITIES },
  { title: '类型', which: 'type', options: TYPES }
];

@Entry
@Component
struct ListPage {
  
  @StorageLink('textScale') ts: number = 1;
  @StorageLink('dataRev') rev: number = 0;
  @State kw: string = '';
  @State eras: string[] = [];
  @State cities: string[] = [];
  @State types: string[] = [];

  aboutToAppear(): void {
    let p = params();
    this.kw = p.kw ?? '';
    if (p.era !== undefined && p.era!.length > 0) {
      this.eras.push(p.era!);
    }
    if (p.city !== undefined && p.city!.length > 0) {
      this.cities.push(p.city!);
    }
    if (p.type !== undefined && p.type!.length > 0) {
      this.types.push(p.type!);
    }
  }

  pickedOf(which: string): string[] {
    if (which === 'era') {
      return this.eras;
    }
    if (which === 'city') {
      return this.cities;
    }
    return this.types;
  }

  has(which: string, opt: string): boolean {
    return this.pickedOf(which).indexOf(opt) >= 0;
  }

  toggle(which: string, opt: string): void {
    let cur = this.pickedOf(which);
    let next: string[] = cur.slice();
    let i = next.indexOf(opt);
    if (i >= 0) {
      next.splice(i, 1);
    } else {
      next.push(opt);
    }
    if (which === 'era') {
      this.eras = next;
    } else if (which === 'city') {
      this.cities = next;
    } else {
      this.types = next;
    }
  }

  pickedCount(): number {
    return this.eras.length + this.cities.length + this.types.length;
  }

  clearAll(): void {
    this.kw = '';
    this.eras = [];
    this.cities = [];
    this.types = [];
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Text('‹ 返回').fontSize(fs(this.ts, 15)).fontColor(CLAY)
          .onClick((): void => {
            router.back();
          })
        Text('沿河检索').fontSize(fs(this.ts, 18)).fontColor(INK).fontWeight(FontWeight.Bold).layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10 })

      Search({ value: this.kw, placeholder: '名称、别名或摘要里的词' })
        .height(38)
        .margin({ left: 14, right: 14, top: 10 })
        .onChange((v: string): void => {
          this.kw = v;
        })

      Column() {
        Row({ space: 8 }) {
          Text('筛选').fontSize(fs(this.ts, 13)).fontColor(INK).fontWeight(FontWeight.Bold)
          Text(`命中 ${this.results().length} 处`).fontSize(fs(this.ts, 11)).fontColor(CLAY)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor('#F4E4DE').borderRadius(10)
          Blank()
          if (this.pickedCount() > 0 || this.kw.trim().length > 0) {
            Text(`已选 ${this.pickedCount()} 项`).fontSize(fs(this.ts, 11)).fontColor(SUB)
            Text('清空').fontSize(fs(this.ts, 12)).fontColor($r('app.color.card_bg'))
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor(CLAY).borderRadius(12)
              .onClick((): void => {
                this.clearAll();
              })
          } else {
            Text('点标签试条件').fontSize(fs(this.ts, 11)).fontColor(SUB)
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 8 })

        ForEach(ROWS, (row: FilterRow): void => {
          Row({ space: 8 }) {
            Text(row.title).fontSize(fs(this.ts, 12)).fontColor(SUB).width(30)
            Scroll() {
              Row({ space: 7 }) {
                ForEach(row.options, (opt: string): void => {
                  
                  Text(opt)
                    .fontSize(fs(this.ts, 12))
                    .fontColor(this.has(row.which, opt) ? Color.White : INK)
                    .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                    .borderRadius(14)
                    .backgroundColor(this.has(row.which, opt) ? CLAY : '#F7F1E6')
                    .border({ width: 1, color: this.has(row.which, opt) ? CLAY : '#E7DCC7' })
                    .onClick((): void => {
                      this.toggle(row.which, opt);
                    })
                }, (opt: string): string => row.which + ':' + opt +
                  (this.has(row.which, opt) ? '#1' : '#0'))
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
        }, (row: FilterRow): string => row.which)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(12)
      .border({ width: 1, color: this.pickedCount() > 0 ? CLAY : '#EFE6D6' })
      .margin({ left: 14, right: 14, top: 10 })
      .padding({ bottom: 6 })

      if (this.pickedCount() > 0) {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(ROWS, (row: FilterRow): void => {
            ForEach(this.pickedOf(row.which), (opt: string): void => {
              Row({ space: 4 }) {
                Text(row.title).fontSize(fs(this.ts, 10)).fontColor(RIVER)
                Text(opt).fontSize(fs(this.ts, 12)).fontColor(INK)
                Text('×').fontSize(fs(this.ts, 13)).fontColor(SUB)
              }
              .padding({ left: 9, right: 8, top: 4, bottom: 4 })
              .margin({ right: 7, bottom: 6 })
              .backgroundColor('#F7F1E6')
              .border({ width: 1, color: '#E7DCC7' })
              .borderRadius(13)
              .onClick((): void => {
                this.toggle(row.which, opt);
              })
            }, (opt: string): string => row.which + '@' + opt)
          }, (row: FilterRow): string => 'p' + row.which)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10 })
      }

      if (this.results().length === 0) {
        Column({ space: 6 }) {
          Text('这一带没有符合条件的').fontSize(fs(this.ts, 14)).fontColor(INK)
          Text('点上面标签里的 × 撤掉一项，或换个关键词').fontSize(fs(this.ts, 12)).fontColor(SUB)
        }
        .width('100%')
        .margin({ top: 50 })
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.results(), (s: SiteInfo): void => {
            ListItem() {
              SiteCard({ site: s })
            }
          }, (s: SiteInfo): string => s.id)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .padding({ left: 14, right: 14, top: 10, bottom: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .alignItems(HorizontalAlign.Start)
  }

  results(): SiteInfo[] {
    return SiteRepo.get().query(this.kw, this.eras, this.cities, this.types);
  }
}
