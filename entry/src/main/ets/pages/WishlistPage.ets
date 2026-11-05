import { router, promptAction } from '@kit.ArkUI';
import { Goods, SpecKV } from '../model/Models';
import { ContentRepo } from '../service/ContentRepo';
import { StudioStore } from '../service/StudioStore';
import { ArtCover } from '../view/ArtCover';
import { fs, INK, SUB, CLAY, LOESS, LINE, moneyText } from '../common/Theme';
import { goGoods, switchTab } from '../common/Nav';

interface Group {
  cat: string;
  items: Goods[];
}

@Entry
@Component
struct WishlistPage {
  @StorageLink('textScale') ts: number = 1;
  @StorageLink('studioRev') @Watch('reload') rev: number = 0;
  @State tab: number = 0;
  @State manage: boolean = false;
  @State groups: Group[] = [];
  @State liked: Goods[] = [];
  @State cartN: number = 0;
  @State checked: string[] = [];
  @State openSpec: string = '';

  aboutToAppear(): void {
    this.reload();
  }

  allIds(): string[] {
    let out: string[] = [];
    for (let g of this.groups) {
      for (let it of g.items) {
        out.push(it.id);
      }
    }
    return out;
  }

  reload(): void {
    let st = StudioStore.get();
    let repo = ContentRepo.get();
    let byCat: Group[] = [];
    for (let id of st.cart) {
      let found = repo.goodOf(id);
      if (found === undefined) {
        continue;
      }
      let g: Goods = found;
      let grp = byCat.find((x: Group): boolean => x.cat === g.cat);
      if (grp === undefined) {
        grp = { cat: g.cat, items: [] };
        byCat.push(grp);
      }
      grp.items.push(g);
    }
    this.groups = byCat;
    this.cartN = st.cart.length;
    let liked: Goods[] = [];
    for (let id of st.likes) {
      let g = repo.goodOf(id);
      if (g !== undefined) {
        liked.push(g);
      }
    }
    this.liked = liked;
    let ids = this.allIds();
    let next = this.checked.filter((x: string): boolean => ids.indexOf(x) >= 0);
    for (let id of ids) {
      if (next.indexOf(id) < 0) {
        next.push(id);
      }
    }
    this.checked = next;
  }

  isOn(id: string): boolean {
    return this.checked.indexOf(id) >= 0;
  }

  toggleOne(id: string): void {
    let next = this.checked.slice();
    let i = next.indexOf(id);
    if (i >= 0) {
      next.splice(i, 1);
    } else {
      next.push(id);
    }
    this.checked = next;
  }

  toggleMany(ids: string[], on: boolean): void {
    let next = this.checked.slice();
    for (let id of ids) {
      let i = next.indexOf(id);
      if (on && i < 0) {
        next.push(id);
      } else if (!on && i >= 0) {
        next.splice(i, 1);
      }
    }
    this.checked = next;
  }

  groupIds(g: Group): string[] {
    return g.items.map((x: Goods): string => x.id);
  }

  groupAllOn(g: Group): boolean {
    let ids = this.groupIds(g);
    if (ids.length === 0) {
      return false;
    }
    for (let id of ids) {
      if (!this.isOn(id)) {
        return false;
      }
    }
    return true;
  }

  toggleGroup(g: Group): void {
    let on = !this.groupAllOn(g);
    this.toggleMany(this.groupIds(g), on);
  }

  grpKey(g: Group): string {
    let st = StudioStore.get();
    let s = g.cat;
    for (let it of g.items) {
      s += it.id + st.qtyOf(it.id) + (this.isOn(it.id) ? '1' : '0');
    }
    return s;
  }

  allChecked(): boolean {
    let ids = this.allIds();
    return ids.length > 0 && this.checked.length === ids.length;
  }

  sum(): number {
    let repo = ContentRepo.get();
    let st = StudioStore.get();
    let n = 0;
    for (let id of this.checked) {
      let g = repo.goodOf(id);
      if (g !== undefined) {
        n += g.price * st.qtyOf(id);
      }
    }
    return Math.round(n * 100) / 100;
  }

  checkedN(): number {
    return this.checked.length;
  }

  askSettle(): void {
    let n = this.checkedN();
    if (n === 0) {
      promptAction.showToast({ message: '先勾几件，再结算' });
      return;
    }
    AlertDialog.show({
      title: '这一单还没接支付',
      message: `勾了 ${n} 件 · 合计 ¥${moneyText(this.sum())}。` +
        '清单只负责把想要的东西收到一起，随时回来接着挑。',
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
      primaryButton: {
        value: '知道了',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '继续挑',
        fontColor: CLAY,
        action: (): void => {
          router.back();
          switchTab(1);
        }
      }
    });
  }

  dropChecked(): void {
    let n = this.checkedN();
    if (n === 0) {
      promptAction.showToast({ message: '先勾上要删的' });
      return;
    }
    AlertDialog.show({
      title: `从清单里删掉 ${n} 件？`,
      message: '只是移出清单，点赞还在，想要再点一下就能加回来。',
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
      primaryButton: {
        value: '删掉',
        fontColor: CLAY,
        action: (): void => {
          StudioStore.get().dropCart(this.checked.slice());
          this.checked = [];
          promptAction.showToast({ message: `已删掉 ${n} 件` });
        }
      },
      secondaryButton: {
        value: '先不删',
        action: (): void => {
        }
      }
    });
  }

  @Builder
  head() {
    Row({ space: 10 }) {
      Text('‹ 返回').fontSize(fs(this.ts, 15)).fontColor(CLAY)
        .onClick((): void => {
          router.back();
        })
      Text('喜欢清单').fontSize(fs(this.ts, 18)).fontColor(INK).fontWeight(FontWeight.Bold).layoutWeight(1)
      Text(this.manage ? '完成' : '管理').fontSize(fs(this.ts, 13)).fontColor(INK)
        .padding({ left: 12, right: 12, top: 5, bottom: 5 })
        .border({ width: 1, color: LINE }).borderRadius(14)
        .onClick((): void => {
          this.manage = !this.manage;
        })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 4 })
  }

  nOf(idx: number): number {
    return idx === 0 ? this.cartN : this.liked.length;
  }

  @Builder
  tabCell(idx: number, title: string) {
    Column({ space: 4 }) {
      Row({ space: 4 }) {
        Text(title).fontSize(fs(this.ts, 15))
          .fontColor(this.tab === idx ? INK : SUB)
          .fontWeight(this.tab === idx ? FontWeight.Bold : FontWeight.Normal)
        Text(`${this.nOf(idx)}`).fontSize(fs(this.ts, 11)).fontColor(this.tab === idx ? CLAY : SUB)
      }
      Column().width(22).height(3).borderRadius(2)
        .backgroundColor(this.tab === idx ? CLAY : Color.Transparent)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 6, bottom: 6 })
    .onClick((): void => {
      this.tab = idx;
    })
  }

  @Builder
  stepper(id: string) {
    Row() {
      Text('−').fontSize(fs(this.ts, 15)).fontColor(INK).width(28).textAlign(TextAlign.Center)
        .onClick((): void => {
          let st = StudioStore.get();
          st.setQty(id, st.qtyOf(id) - 1);
        })
      Text(`${StudioStore.get().qtyOf(id)}`).fontSize(fs(this.ts, 13)).fontColor(INK)
        .width(30).textAlign(TextAlign.Center)
      Text('+').fontSize(fs(this.ts, 15)).fontColor(CLAY).width(28).textAlign(TextAlign.Center)
        .onClick((): void => {
          let st = StudioStore.get();
          st.setQty(id, st.qtyOf(id) + 1);
        })
    }
    .height(26)
    .border({ width: 1, color: LINE }).borderRadius(13)
  }

  @Builder
  specLine(g: Goods) {
    Column({ space: 3 }) {
      Row({ space: 5 }) {
        Text(g.spec.length > 0 ? `${g.spec[0].k} ${g.spec[0].v}` : g.era)
          .fontSize(fs(this.ts, 10)).fontColor(SUB)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.openSpec === g.id ? '收起 ▴' : '规格 ▾').fontSize(fs(this.ts, 10)).fontColor(LOESS)
      }
      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
      .backgroundColor('#F7F1E6').borderRadius(9)
      .onClick((): void => {
        this.openSpec = this.openSpec === g.id ? '' : g.id;
      })

      if (this.openSpec === g.id) {
        ForEach(g.spec, (kv: SpecKV): void => {
          Row({ space: 6 }) {
            Text(kv.k).fontSize(fs(this.ts, 10)).fontColor(SUB).width(38)
            Text(kv.v).fontSize(fs(this.ts, 10)).fontColor(INK).layoutWeight(1)
          }
          .width('100%')
        }, (kv: SpecKV): string => g.id + kv.k)
        Text(`出自 ${g.origin}`).fontSize(fs(this.ts, 10)).fontColor(SUB)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  cartRow(g: Goods) {
    Row({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Column().width(20).height(20).borderRadius(10)
          .backgroundColor(this.isOn(g.id) ? CLAY : Color.Transparent)
          .border({ width: 1.5, color: this.isOn(g.id) ? CLAY : '#C9BCA6' })
        if (this.isOn(g.id)) {
          Text('✓').fontSize(fs(this.ts, 12)).fontColor(Color.White)
        }
      }
      .width(26).height(26)
      .onClick((): void => {
        this.toggleOne(g.id);
      })
      Stack() {
        ArtCover({ palette: g.palette, shape: 'box', seed: 1, img: g.img })
      }
      .width(68).height(68).borderRadius(9).clip(true)
      .onClick((): void => {
        goGoods(g.id);
      })

      Column({ space: 5 }) {
        Text(g.name).fontSize(fs(this.ts, 14)).fontColor(INK).fontWeight(FontWeight.Medium)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(g.sub).fontSize(fs(this.ts, 11)).fontColor(SUB)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        this.specLine(g)
        Row() {
          Text(`¥${moneyText(g.price)}`).fontSize(fs(this.ts, 15)).fontColor(CLAY).fontWeight(FontWeight.Bold)
          Blank()
          if (this.manage) {
            Text('移出清单').fontSize(fs(this.ts, 11)).fontColor(CLAY)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .border({ width: 1, color: CLAY }).borderRadius(13)
              .onClick((): void => {
                StudioStore.get().dropCart([g.id]);
                promptAction.showToast({ message: '已从清单移出' });
              })
          } else {
            this.stepper(g.id)
          }
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 9, bottom: 9 })
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  cartList() {
    List({ space: 0 }) {
      ForEach(this.groups, (g: Group): void => {
        ListItemGroup({ header: this.groupHead(g), space: 0 }) {
          ForEach(g.items, (it: Goods): void => {
            ListItem() {
              this.cartRow(it)
            }
          }, (it: Goods): string => it.id + ':' + StudioStore.get().qtyOf(it.id) +
            (this.isOn(it.id) ? '#1' : '#0') + (this.manage ? 'm' : '') + (this.openSpec === it.id ? 'o' : ''))
        }
      }, (g: Group): string => this.grpKey(g))
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .sticky(StickyStyle.Header)
    .padding({ left: 14, right: 14 })
  }

  @Builder
  groupHead(g: Group) {
    Row({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Column().width(20).height(20).borderRadius(10)
          .backgroundColor(this.groupAllOn(g) ? CLAY : Color.Transparent)
          .border({ width: 1.5, color: this.groupAllOn(g) ? CLAY : '#C9BCA6' })
        if (this.groupAllOn(g)) {
          Text('✓').fontSize(fs(this.ts, 12)).fontColor(Color.White)
        }
      }
      .width(26).height(26)
      .onClick((): void => {
        this.toggleGroup(g);
      })
      Text(g.cat).fontSize(fs(this.ts, 13)).fontColor(INK).fontWeight(FontWeight.Medium)
      Text(`${g.items.length} 件`).fontSize(fs(this.ts, 11)).fontColor(SUB)
      Blank()
      Text(`¥${moneyText(g.items.reduce((a: number, x: Goods): number =>
        a + x.price * StudioStore.get().qtyOf(x.id), 0))}`)
        .fontSize(fs(this.ts, 11)).fontColor(LOESS)
    }
    .width('100%')
    .height(38)
    .padding({ left: 2, right: 2 })
    .backgroundColor($r('app.color.page_bg'))
  }

  @Builder
  likeRow(g: Goods) {
    Row({ space: 8 }) {
      Stack() {
        ArtCover({ palette: g.palette, shape: 'pot', seed: 2, img: g.img })
      }
      .width(60).height(60).borderRadius(9).clip(true)
      .onClick((): void => {
        goGoods(g.id);
      })
      Column({ space: 4 }) {
        Text(g.name).fontSize(fs(this.ts, 14)).fontColor(INK).fontWeight(FontWeight.Medium)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(`${g.cat} · ${g.era}`).fontSize(fs(this.ts, 11)).fontColor(SUB)
        Row() {
          Text(`¥${moneyText(g.price)}`).fontSize(fs(this.ts, 14)).fontColor(CLAY).fontWeight(FontWeight.Bold)
          Blank()
          Text(StudioStore.get().inCart(g.id) ? '已在清单' : '加入清单')
            .fontSize(fs(this.ts, 11))
            .fontColor(StudioStore.get().inCart(g.id) ? SUB : Color.White)
            .padding({ left: 11, right: 11, top: 5, bottom: 5 })
            .backgroundColor(StudioStore.get().inCart(g.id) ? '#F7F1E6' : CLAY)
            .borderRadius(13)
            .onClick((): void => {
              StudioStore.get().toggleCart(g.id);
              promptAction.showToast({
                message: StudioStore.get().inCart(g.id) ? '已加进清单' : '已移出清单'
              });
            })
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(10)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(10)
  }

  @Builder
  bottomBar() {
    Row({ space: 10 }) {
      Row({ space: 4 }) {
        Stack({ alignContent: Alignment.Center }) {
          Column().width(20).height(20).borderRadius(10)
            .backgroundColor(this.allChecked() ? CLAY : Color.Transparent)
            .border({ width: 1.5, color: this.allChecked() ? CLAY : '#C9BCA6' })
          if (this.allChecked()) {
            Text('✓').fontSize(fs(this.ts, 12)).fontColor(Color.White)
          }
        }
        .width(26).height(26)
        .onClick((): void => {
          this.checked = this.allChecked() ? [] : this.allIds();
        })
        Text('全选').fontSize(fs(this.ts, 12)).fontColor(INK)
      }

      Column({ space: 1 }) {
        Text(`合计 ¥${moneyText(this.sum())}`).fontSize(fs(this.ts, 14)).fontColor(INK).fontWeight(FontWeight.Bold)
        Text(`已勾 ${this.checkedN()} 件`).fontSize(fs(this.ts, 10)).fontColor(SUB)
      }
      .alignItems(HorizontalAlign.End)
      .layoutWeight(1)

      if (this.manage) {
        Text(`删除所选 (${this.checkedN()})`).fontSize(fs(this.ts, 13)).fontColor(Color.White)
          .padding({ left: 16, right: 16, top: 9, bottom: 9 })
          .backgroundColor('#C0392B').borderRadius(20)
          .onClick((): void => {
            this.dropChecked();
          })
      } else {
        Text(`去结算 (${this.checkedN()})`).fontSize(fs(this.ts, 13)).fontColor(Color.White)
          .padding({ left: 16, right: 16, top: 9, bottom: 9 })
          .backgroundColor(CLAY).borderRadius(20)
          .onClick((): void => {
            this.askSettle();
          })
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 8, bottom: 10 })
    .backgroundColor($r('app.color.card_bg'))
    .border({ width: { top: 1 }, color: LINE })
  }

  build() {
    Column() {
      this.head()

      Row() {
        this.tabCell(0, '清单')
        this.tabCell(1, '点赞')
      }
      .width('100%')
      .padding({ left: 14, right: 14 })
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius({ topLeft: 12, topRight: 12 })
      .margin({ left: 14, right: 14, top: 8 })

      if (this.tab === 0) {
        if (this.groups.length === 0) {
          Column({ space: 8 }) {
            Text('清单还是空的').fontSize(fs(this.ts, 15)).fontColor(INK)
            Text('文创卡片上点「♡ 收藏」就加进这里').fontSize(fs(this.ts, 12)).fontColor(SUB)
            Text('去挑几件').fontSize(fs(this.ts, 13)).fontColor(Color.White)
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .backgroundColor(CLAY).borderRadius(18)
              .onClick((): void => {
                router.back();
                switchTab(1);
              })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          this.cartList()
          this.bottomBar()
        }
      } else {
        if (this.liked.length === 0) {
          Column({ space: 8 }) {
            Text('还没点过赞').fontSize(fs(this.ts, 15)).fontColor(INK)
            Text('看到喜欢的物件点一下 ♥').fontSize(fs(this.ts, 12)).fontColor(SUB)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.liked, (g: Goods): void => {
              ListItem() {
                this.likeRow(g)
              }
            }, (g: Goods): string => 'lk' + g.id + (StudioStore.get().inCart(g.id) ? '#1' : '#0'))
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .padding({ left: 14, right: 14, top: 10, bottom: 16 })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .alignItems(HorizontalAlign.Start)
  }
}
