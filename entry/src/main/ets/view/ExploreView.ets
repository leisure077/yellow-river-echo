import { SiteRepo } from '../service/SiteRepo';
import { MemoryStore } from '../service/MemoryStore';
import { SiteInfo, Suggestion } from '../model/Models';
import { fs, ERAS, CITIES, ERA_WORD, coverRes, coverOf, INK, SUB, LOESS, CLAY } from '../common/Theme';
import { goDetail, goList } from '../common/Nav';
import { SiteCard } from './SiteCard';

@Component
export struct ExploreView {
  @StorageLink('textScale') ts: number = 1;
  @StorageLink('dataRev') @Watch('reload') rev: number = 0;
  @State kw: string = '';
  @State recs: Suggestion[] = [];
  @State recent: SiteInfo[] = [];

  aboutToAppear(): void {
    this.reload();
  }

  reload(): void {
    let mem = MemoryStore.get();
    this.recs = SiteRepo.get().recommend(mem.favIds(), mem.views, 4, '');
    this.recent = this.recentSites();
  }

  recentSites(): SiteInfo[] {
    let out: SiteInfo[] = [];
    for (let v of MemoryStore.get().views) {
      let s = SiteRepo.get().byId(v.siteId);
      if (s !== undefined) {
        out.push(s);
      }
      if (out.length >= 8) {
        break;
      }
    }
    return out;
  }

  @Builder
  secTitle(title: string, sub: string) {
    Row({ space: 8 }) {
      Divider().vertical(true).height(14).strokeWidth(3).color(LOESS)
      Text(title).fontSize(fs(this.ts, 17)).fontColor(INK).fontWeight(FontWeight.Medium)
      Text(sub).fontSize(fs(this.ts, 11)).fontColor(SUB).layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 14 })
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Stack({ alignContent: Alignment.BottomStart }) {
          Image(coverRes('hero_river'))
            .width('100%')
            .height(180)
            .objectFit(ImageFit.Cover)
          Column({ space: 2 }) {
            Text('黄河续响平台').fontSize(fs(this.ts, 24)).fontColor(Color.White).fontWeight(FontWeight.Bold)
            Text('河南段沿线文化遗址 · 随身数字档案')
              .fontSize(fs(this.ts, 12)).fontColor('#E8E0D2')
          }
          .alignItems(HorizontalAlign.Start)
          .padding(14)
        }
        .width('100%')
        .height(180)
        .borderRadius({ bottomLeft: 14, bottomRight: 14 })
        .clip(true)

        Search({ value: this.kw, placeholder: '搜遗址、年代或类型，比如「彩陶」' })
          .height(40)
          .margin({ left: 14, right: 14 })
          .backgroundColor($r('app.color.card_bg'))
          .onChange((v: string): void => {
            this.kw = v;
          })
          .onSubmit((): void => {
            goList(this.kw, '', '', '');
          })

        this.secTitle('沿河看年代', '从仰韶到宋，六段河史')
        Scroll() {
          Row({ space: 10 }) {
            ForEach(ERAS, (era: string): void => {
              Column({ space: 3 }) {
                Image(coverRes(coverOf(era)))
                  .width(108)
                  .height(64)
                  .borderRadius(8)
                  .objectFit(ImageFit.Cover)
                Text(era).fontSize(fs(this.ts, 14)).fontColor(INK).fontWeight(FontWeight.Medium)
                Text(`${ERA_WORD.get(era)} · ${SiteRepo.get().countByEra(era)} 处`)
                  .fontSize(fs(this.ts, 11)).fontColor(SUB)
              }
              .width(108)
              .alignItems(HorizontalAlign.Start)
              .onClick((): void => {
                goList('', era, '', '');
              })
            }, (era: string): string => era)
          }
          .padding({ left: 14, right: 14 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')

        this.secTitle('五座城', '同一条河，五种性格')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(CITIES, (city: string): void => {
            Text(`${city} · ${SiteRepo.get().countByCity(city)}`)
              .fontSize(fs(this.ts, 13))
              .fontColor(CLAY)
              .margin({ left: 14, top: 4, bottom: 4 })
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(14)
              .border({ width: 1, color: '#D9C9A8' })
              .onClick((): void => {
                goList('', '', city, '');
              })
          }, (city: string): string => city)
        }
        .padding({ right: 14 })

        this.secTitle('走了这么远', '按你的收藏顺线推荐')
        Column({ space: 8 }) {
          ForEach(this.recs,
            (sg: Suggestion): void => {
              SiteCard({ site: sg.site, note: sg.reason })
                .margin({ left: 14, right: 14 })
            }, (sg: Suggestion): string => sg.site.id + '_' + this.rev)
        }

        if (this.recent.length > 0) {
          this.secTitle('最近在读', '')
          Scroll() {
            Row({ space: 10 }) {
              ForEach(this.recent, (site: SiteInfo): void => {
                Column({ space: 3 }) {
                  Image(coverRes(site.cover))
                    .width(86)
                    .height(52)
                    .borderRadius(6)
                    .objectFit(ImageFit.Cover)
                  Text(site.name)
                    .fontSize(fs(this.ts, 11))
                    .fontColor(INK)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width(86)
                .alignItems(HorizontalAlign.Start)
                .onClick((): void => {
                  goDetail(site.id);
                })
              }, (site: SiteInfo): string => site.id)
            }
            .padding({ left: 14, right: 14 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }

        Blank().height(20)
      }
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }
}
