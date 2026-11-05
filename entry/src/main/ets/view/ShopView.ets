import { Goods } from '../model/Models';
import { ContentRepo } from '../service/ContentRepo';
import { StudioStore } from '../service/StudioStore';
import { ArtCover } from './ArtCover';
import { fs, INK, SUB, CLAY, LOESS, LINE, moneyText, likeText } from '../common/Theme';
import { goGoods, goWishlist } from '../common/Nav';

const SHAPES: string[] = ['pot', 'jar', 'ding', 'tile', 'stele', 'box', 'coin', 'kiln'];

@Component
export struct ShopView {
  
  @StorageLink('textScale') ts: number = 1;
  @StorageLink('dataRev') @Watch('reload') dataRev: number = 0;
  @StorageLink('studioRev') @Watch('syncMine') studioRev: number = 0;
  @State kw: string = '';
  @State cat: string = '全部';
  @State hotFirst: boolean = true;
  @State cats: string[] = [];
  @State items: Goods[] = [];
  @State total: number = 0;
  @State liked: string[] = [];
  @State cartIds: string[] = [];

  aboutToAppear(): void {
    this.reload();
    this.syncMine();
  }

  syncMine(): void {
    let st = StudioStore.get();
    this.liked = st.likes.slice();
    this.cartIds = st.cart.slice();
  }

  reload(): void {
    let repo = ContentRepo.get();
    this.cats = ['全部'].concat(repo.goodsCats());
    this.total = repo.goods.length;
    this.apply();
  }

  apply(): void {
    let arr = ContentRepo.get().filterGoods(this.cat, this.kw);
    if (this.hotFirst) {
      arr.sort((a: Goods, b: Goods): number => b.likes - a.likes);
    }
    this.items = arr;
  }

  shapeOf(id: string): string {
    let n = 0;
    for (let i = 0; i < id.length; i++) {
      n += id.charCodeAt(i);
    }
    return SHAPES[n % SHAPES.length];
  }

  search(): void {
    this.apply();
  }

  @Builder
  bar() {
    Row({ space: 8 }) {
      TextInput({ placeholder: '找一件带河土的物件', text: this.kw })
        .height(36)
        .fontSize(fs(this.ts, 13))
        .fontColor(INK)
        .placeholderColor(SUB)
        .placeholderFont({ size: 13 })
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(18)
        .border({ width: 1, color: LINE })
        .enterKeyType(EnterKeyType.Search)
        .layoutWeight(1)
        .onChange((v: string): void => {
          this.kw = v;
          this.apply();
        })
        .onSubmit((key: EnterKeyType): void => {
          this.search();
        })

      Text(this.hotFirst ? '最热' : '上新')
        .fontSize(fs(this.ts, 12))
        .fontColor(CLAY)
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor('#F4E4DE')
        .borderRadius(14)
        .onClick((): void => {
          this.hotFirst = !this.hotFirst;
          this.apply();
        })

      Row({ space: 3 }) {
        Text(`清单 ${this.cartIds.length}`).fontSize(fs(this.ts, 12)).fontColor(INK)
        Text('›').fontSize(fs(this.ts, 12)).fontColor(SUB)
      }
      .padding({ left: 10, right: 8, top: 6, bottom: 6 })
      .backgroundColor($r('app.color.card_bg'))
      .border({ width: 1, color: this.cartIds.length > 0 ? CLAY : LINE })
      .borderRadius(14)
      .onClick((): void => {
        goWishlist();
      })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 8, bottom: 6 })
  }

  @Builder
  chipRow() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.cats, (c: string): void => {
          Text(c)
            .fontSize(fs(this.ts, 12))
            .fontColor(this.cat === c ? Color.White : INK)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .borderRadius(13)
            .backgroundColor(this.cat === c ? CLAY : $r('app.color.card_bg'))
            .onClick((): void => {
              this.cat = c;
              this.apply();
            })
        }, (c: string): string => c)
      }
      .padding({ left: 14, right: 14 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  card(g: Goods, i: number) {
    Column() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          ArtCover({ palette: g.palette, shape: this.shapeOf(g.id), seed: i + 1, img: g.img })
        }
        .width('100%')
        .height(134)

        Row({ space: 6 }) {
          Text(this.cartIds.indexOf(g.id) >= 0 ? '♥ 已在清单' : '♡ 收藏')
            .fontSize(fs(this.ts, 10))
            .fontColor(this.cartIds.indexOf(g.id) >= 0 ? CLAY : INK)
            .padding({ left: 7, right: 7, top: 3, bottom: 3 })
            .borderRadius(10)
            .backgroundColor('rgba(255,255,255,0.80)')
            .onClick((): void => {
              StudioStore.get().toggleCart(g.id);
            })

          Blank()

          Text(`${this.liked.indexOf(g.id) >= 0 ? '♥' : '♡'} ` +
            `${likeText(g.likes + (this.liked.indexOf(g.id) >= 0 ? 1 : 0))}`)
            .fontSize(fs(this.ts, 10))
            .fontColor(this.liked.indexOf(g.id) >= 0 ? CLAY : INK)
            .padding({ left: 7, right: 7, top: 3, bottom: 3 })
            .borderRadius(10)
            .backgroundColor('rgba(255,255,255,0.80)')
            .onClick((): void => {
              StudioStore.get().toggleLike(g.id);
            })
        }
        .width('100%')
        .padding({ left: 8, right: 8, bottom: 8 })
      }
      .width('100%')
      .height(134)
      .borderRadius({ topLeft: 10, topRight: 10 })
      .clip(true)
      .onClick((): void => {
        goGoods(g.id);
      })

      Column({ space: 3 }) {
        Text(g.name)
          .fontSize(fs(this.ts, 13))
          .fontColor(INK)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(g.sub)
          .fontSize(fs(this.ts, 11))
          .fontColor(SUB)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row() {
          Text(`¥${moneyText(g.price)}`)
            .fontSize(fs(this.ts, 14))
            .fontColor(CLAY)
            .fontWeight(FontWeight.Bold)
          Blank()
          Text(g.era)
            .fontSize(fs(this.ts, 10))
            .fontColor(LOESS)
        }
        .width('100%')
        .padding({ top: 2 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(10)
      .onClick((): void => {
        goGoods(g.id);
      })
    }
    .width('100%')
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(10)
  }

  build() {
    Column() {
      this.bar()
      this.chipRow()

      Row() {
        Text(this.total === 0 ? '共 0 件' : `${this.items.length} 件`)
          .fontSize(fs(this.ts, 11))
          .fontColor(SUB)
        Blank()
        Text(this.cat)
          .fontSize(fs(this.ts, 11))
          .fontColor(LOESS)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 8, bottom: 4 })

      if (this.total === 0) {
        Column({ space: 6 }) {
          Text('文创数据包未随包提供').fontSize(fs(this.ts, 14)).fontColor(INK)
          Text('huanghe_goods.json 没有读到，其余功能不受影响').fontSize(fs(this.ts, 11)).fontColor(SUB)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.items.length === 0) {
        Column({ space: 6 }) {
          Text('这一类暂时没铺货').fontSize(fs(this.ts, 14)).fontColor(INK)
          Text('换个关键词，或者点回「全部」').fontSize(fs(this.ts, 11)).fontColor(SUB)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.items, (g: Goods, i: number): void => {
            GridItem() {
              this.card(g, i)
            }
          }, (g: Goods): string => g.id)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(10)
        .rowsGap(12)
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .padding({ left: 14, right: 14, top: 4, bottom: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .alignItems(HorizontalAlign.Start)
  }
}
