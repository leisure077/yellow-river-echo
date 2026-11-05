import { router, promptAction } from '@kit.ArkUI';
import { Goods, SiteInfo, SpecKV } from '../model/Models';
import { ContentRepo } from '../service/ContentRepo';
import { SiteRepo } from '../service/SiteRepo';
import { StudioStore } from '../service/StudioStore';
import { ArtCover } from '../view/ArtCover';
import { SiteCard } from '../view/SiteCard';
import { fs, INK, SUB, LOESS, CLAY, RIVER, LINE, PAPER, moneyText, likeText } from '../common/Theme';
import { params, goDetail } from '../common/Nav';

const SHAPES: string[] = ['pot', 'jar', 'ding', 'tile', 'stele', 'box', 'coin', 'kiln'];
const ANGLES: string[] = ['正面', '侧面', '细节'];

@Entry
@Component
struct GoodsDetailPage {
  
  @StorageLink('textScale') ts: number = 1;
  @StorageLink('studioRev') @Watch('syncMine') studioRev: number = 0;
  @State g: Goods | undefined = undefined;
  @State mates: SiteInfo[] = [];
  @State myLike: boolean = false;
  @State myCart: boolean = false;

  aboutToAppear(): void {
    let p = params();
    let id = p.goodsId ?? '';
    let good = ContentRepo.get().goodOf(id);
    this.g = good;
    if (good !== undefined) {
      let eras: string[] = [good.era];
      this.mates = SiteRepo.get().query('', eras, [], []).slice(0, 3);
    }
    this.syncMine();
  }

  syncMine(): void {
    if (this.g === undefined) {
      this.myLike = false;
      this.myCart = false;
      return;
    }
    let st = StudioStore.get();
    this.myLike = st.isLiked(this.g.id);
    this.myCart = st.inCart(this.g.id);
  }

  shapeOf(id: string): string {
    let n = 0;
    for (let i = 0; i < id.length; i++) {
      n += id.charCodeAt(i);
    }
    return SHAPES[n % SHAPES.length];
  }

  liked(): boolean {
    return this.myLike;
  }

  inCart(): boolean {
    return this.myCart;
  }

  likeCount(): string {
    if (this.g === undefined) {
      return '0';
    }
    return likeText(this.g.likes + (this.liked() ? 1 : 0));
  }

  @Builder
  shot(i: number) {
    Column() {
      
      ArtCover({ palette: this.g!.palette, shape: this.shapeOf(this.g!.id), seed: i + 1,
        img: this.g!.img,
        label: this.g!.img.length > 0 ? '' : ANGLES[i % ANGLES.length] })
    }
    .width('100%')
    .height(320)
    .backgroundColor(PAPER)
  }

  @Builder
  chip(text: string, on: boolean) {
    Text(text)
      .fontSize(fs(this.ts, 11))
      .fontColor(on ? Color.White : INK)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .borderRadius(11)
      .backgroundColor(on ? CLAY : '#F1E7D5')
  }

  @Builder
  blockTitle(t: string) {
    Text(t)
      .fontSize(fs(this.ts, 15))
      .fontColor(INK)
      .fontWeight(FontWeight.Medium)
      .width('100%')
      .padding({ bottom: 2 })
  }

  build() {
    Column() {
      if (this.g === undefined) {
        Column({ space: 14 }) {
          Text('没找到这件文创').fontSize(fs(this.ts, 15)).fontColor(INK)
          Text('它是从数据包里读出来的，回去再看看').fontSize(fs(this.ts, 12)).fontColor(SUB)
          Text('返回')
            .fontSize(fs(this.ts, 13))
            .fontColor(Color.White)
            .padding({ left: 18, right: 18, top: 8, bottom: 8 })
            .backgroundColor(CLAY)
            .borderRadius(16)
            .onClick((): void => {
              router.back();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
          Swiper() {
            this.shot(0)
            if (this.g!.img.length === 0) {
              this.shot(1)
              this.shot(2)
            }
          }
          .width('100%')
          .height(320)
          .loop(false)
          
          .indicator(this.g!.img.length === 0)

          Text('‹ 返回')
            .fontSize(fs(this.ts, 14))
            .fontColor(Color.White)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .margin({ left: 10, top: 10 })
            .backgroundColor('#66000000')
            .borderRadius(14)
            .onClick((): void => {
              router.back();
            })
        }
        .width('100%')
        .height(320)

        Scroll() {
          Column({ space: 14 }) {
            Column({ space: 6 }) {
              Row() {
                Column({ space: 4 }) {
                  Text(this.g!.name)
                    .fontSize(fs(this.ts, 19))
                    .fontColor(INK)
                    .fontWeight(FontWeight.Bold)
                  Text(this.g!.sub)
                    .fontSize(fs(this.ts, 12))
                    .fontColor(SUB)
                    .lineHeight(fs(this.ts, 19))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Text(`¥${moneyText(this.g!.price)}`)
                  .fontSize(fs(this.ts, 20))
                  .fontColor(CLAY)
                  .fontWeight(FontWeight.Bold)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)

              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.g!.tags, (t: string, i: number): void => {
                  Row() {
                    this.chip(t, false)
                  }
                  .margin({ right: 6, bottom: 6 })
                }, (t: string, i: number): string => `${t}_${i}`)
                Row() {
                  this.chip(this.g!.era, true)
                }
                .margin({ right: 6, bottom: 6 })
              }
              .width('100%')

              Row({ space: 6 }) {
                Text('灵感来源')
                  .fontSize(fs(this.ts, 11))
                  .fontColor(SUB)
                Text(this.g!.origin)
                  .fontSize(fs(this.ts, 11))
                  .fontColor(RIVER)
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ top: 6, bottom: 6 })
              .border({ width: { top: 1, bottom: 1 }, color: LINE })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(14)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(12)

            Row({ space: 10 }) {
              Text(`${this.liked() ? '♥' : '♡'} 点赞 ${this.likeCount()}`)
                .fontSize(fs(this.ts, 12))
                .fontColor(this.liked() ? CLAY : INK)
                .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                .backgroundColor(this.liked() ? '#F4E4DE' : $r('app.color.card_bg'))
                .borderRadius(16)
                .onClick((): void => {
                  StudioStore.get().toggleLike(this.g!.id);
                })

              Text(this.inCart() ? '♥ 已收藏' : '♡ 收藏')
                .fontSize(fs(this.ts, 12))
                .fontColor(this.inCart() ? CLAY : INK)
                .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                .backgroundColor(this.inCart() ? '#F4E4DE' : $r('app.color.card_bg'))
                .borderRadius(16)
                .onClick((): void => {
                  StudioStore.get().toggleCart(this.g!.id);
                })

              Blank()
              Text(`${this.g!.cat}｜${this.g!.era}`)
                .fontSize(fs(this.ts, 11))
                .fontColor(LOESS)
            }
            .width('100%')

            Column({ space: 2 }) {
              this.blockTitle('规格')
              ForEach(this.g!.spec, (s: SpecKV, i: number): void => {
                Column() {
                  Row({ space: 10 }) {
                    Text(s.k)
                      .fontSize(fs(this.ts, 12))
                      .fontColor(SUB)
                      .width(58)
                    Text(s.v)
                      .fontSize(fs(this.ts, 12))
                      .fontColor(INK)
                      .layoutWeight(1)
                  }
                  .width('100%')
                  .padding({ top: 9, bottom: 9 })
                  if (i < this.g!.spec.length - 1) {
                    Divider().strokeWidth(1).color(LINE)
                  }
                }
                .width('100%')
              }, (s: SpecKV, i: number): string => `${s.k}_${i}`)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 14, right: 14 })
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(12)

            Column({ space: 8 }) {
              this.blockTitle('它从哪里来')
              Text(this.g!.story)
                .fontSize(fs(this.ts, 13))
                .fontColor(INK)
                .lineHeight(fs(this.ts, 23))
              Text('资料：' + this.g!.source)
                .fontSize(fs(this.ts, 10))
                .fontColor(SUB)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(14)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(12)

            Column({ space: 8 }) {
              this.blockTitle(`${this.g!.era}的去处`)
              if (this.mates.length === 0) {
                Text('这个年代暂时没有可推荐的遗址').fontSize(fs(this.ts, 11)).fontColor(SUB)
              } else {
                Scroll() {
                  Row({ space: 10 }) {
                    ForEach(this.mates, (s: SiteInfo): void => {
                      Column() {
                        SiteCard({ site: s })
                      }
                      .width(252)
                      .onClick((): void => {
                        goDetail(s.id);
                      })
                    }, (s: SiteInfo): string => s.id)
                  }
                  .padding({ bottom: 4 })
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Off)
                .width('100%')
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 12, bottom: 16 })
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)

        Row({ space: 10 }) {
          Text(`¥${moneyText(this.g!.price)}`)
            .fontSize(fs(this.ts, 18))
            .fontColor(CLAY)
            .fontWeight(FontWeight.Bold)
            .width(78)

          Button(this.inCart() ? '已在清单' : '加入清单')
            .fontSize(fs(this.ts, 14))
            .fontColor(INK)
            .backgroundColor('#EFE2C6')
            .layoutWeight(1)
            .onClick((): void => {
              StudioStore.get().toggleCart(this.g!.id);
            })

          Button('立即购买')
            .fontSize(fs(this.ts, 14))
            .fontColor(Color.White)
            .backgroundColor(CLAY)
            .layoutWeight(1)
            .onClick((): void => {
              promptAction.showToast({ message: '支付通道开通中，可先加入清单' });
            })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.card_bg'))
        .border({ width: { top: 1 }, color: LINE })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
