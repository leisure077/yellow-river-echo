import { Relic, RelicRepo, RELIC_CATS, RELIC_ERAS, RELIC_COLORS, ColorSeed } from '../service/RelicRepo';
import { ArtCover } from './ArtCover';
import { INK, SUB, CLAY, LINE, PAPER, fs, paletteOf } from '../common/Theme';

// @Builder 收对象字面量才会跟着状态重画，普通参数只是建时快照（真机实测：chip 点了不变色）
interface ChipArg {
  label: string;
  on: boolean;
  act: () => void;
}

// 「观文物」查询面板：搜索 + 分类 / 年代多选、颜色单选，结果两列排开，点卡片浮出文物小传。
// 做成组件而不是页面，是因为数字文物把它放在顶栏第一个页签里；条目与照片都随包，见 RelicRepo。
@Component
export struct RelicBrowser {
  @StorageLink('textScale') ts: number = 1;
  @State kw: string = '';
  @State cats: string[] = [];
  @State eras: string[] = [];
  @State colors: string[] = [];
  @State openId: string = '';

  flip(arr: string[], v: string): string[] {
    let out = arr.slice();
    let i = out.indexOf(v);
    if (i >= 0) {
      out.splice(i, 1);
    } else {
      out.push(v);
    }
    return out;
  }

  shown(): Relic[] {
    return RelicRepo.get().filtered(this.kw, this.cats, this.eras, this.colors);
  }

  filtered(): boolean {
    return this.cats.length > 0 || this.eras.length > 0 || this.colors.length > 0;
  }

  clearAll(): void {
    this.cats = [];
    this.eras = [];
    this.colors = [];
  }

  openRelic(): Relic | undefined {
    return this.openId.length > 0 ? RelicRepo.get().byId(this.openId) : undefined;
  }

  @Builder
  chip(arg: ChipArg) {
    Text(arg.label)
      .fontSize(fs(this.ts, 11))
      .fontColor(arg.on ? PAPER : INK)
      .backgroundColor(arg.on ? CLAY : 'rgba(255,255,255,0.72)')
      .border({ width: 1, color: arg.on ? CLAY : LINE })
      .borderRadius(12)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .onClick(arg.act)
  }

  @Builder
  groupHead(title: string) {
    Row({ space: 6 }) {
      Column().width(3).height(12).borderRadius(1.5).backgroundColor(CLAY)
      Text(title).fontSize(fs(this.ts, 12)).fontColor(INK).fontWeight(FontWeight.Medium)
    }
    .width('100%')
  }

  @Builder
  colorDot(c: ColorSeed) {
    Column({ space: 3 }) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(22).height(22).borderRadius(11)
          .backgroundColor(paletteOf(c.key).base)
          .border({ width: this.colors.indexOf(c.key) >= 0 ? 2.5 : 1,
            color: this.colors.indexOf(c.key) >= 0 ? CLAY : LINE })
        if (this.colors.indexOf(c.key) >= 0) {
          Text('✓').fontSize(fs(this.ts, 11)).fontColor(PAPER).fontWeight(FontWeight.Bold)
        }
      }
      Text(c.name).fontSize(fs(this.ts, 9)).fontColor(this.colors.indexOf(c.key) >= 0 ? CLAY : SUB)
    }
    .onClick((): void => {
      // 颜色只单选：点一个顶掉上一个，再点同一个才取消
      this.colors = this.colors.indexOf(c.key) >= 0 ? [] : [c.key];
    })
  }

  @Builder
  relicCell(r: Relic, i: number) {
    Column({ space: 5 }) {
      Column() {
        ArtCover({ palette: r.palette, shape: r.shape, seed: i + 1, label: r.cat, img: r.img })
      }
      .width('100%').height(104).borderRadius(10).clip(true)

      Text(r.name)
        .fontSize(fs(this.ts, 13)).fontColor(INK).fontWeight(FontWeight.Medium)
        .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Row({ space: 5 }) {
        Text(r.era)
          .fontSize(fs(this.ts, 9)).fontColor(CLAY)
          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          .backgroundColor('#F3E3D3').borderRadius(7)
        Text(r.cat)
          .fontSize(fs(this.ts, 9)).fontColor(SUB)
          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          .backgroundColor('rgba(229,218,198,0.5)').borderRadius(7)
        Blank()
        Column().width(9).height(9).borderRadius(4.5).backgroundColor(paletteOf(r.palette).deep)
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
      this.openId = r.id;
    })
  }

  // 文物小传：盖一层纸色浮卡，点空白或「知道了」收起
  @Builder
  detailOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%').height('100%')
        .backgroundColor('rgba(43,38,34,0.45)')
        .onClick((): void => {
          this.openId = '';
        })
      Column({ space: 10 }) {
        Column() {
          ArtCover({ palette: this.openRelic()!.palette, shape: this.openRelic()!.shape,
            seed: 3, label: this.openRelic()!.cat, img: this.openRelic()!.img })
        }
        .width(150).height(150).borderRadius(14).clip(true)

        Text(this.openRelic()!.name)
          .fontSize(fs(this.ts, 17)).fontColor(INK).fontWeight(FontWeight.Bold)
        Row({ space: 6 }) {
          Text(this.openRelic()!.era)
            .fontSize(fs(this.ts, 10)).fontColor(CLAY)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor('#F3E3D3').borderRadius(8)
          Text(this.openRelic()!.cat)
            .fontSize(fs(this.ts, 10)).fontColor(SUB)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor('rgba(229,218,198,0.6)').borderRadius(8)
        }
        Column({ space: 6 }) {
          Row() {
            Text('质地').fontSize(fs(this.ts, 11)).fontColor(SUB).width(44)
            Text(this.openRelic()!.material).fontSize(fs(this.ts, 12)).fontColor(INK).layoutWeight(1)
          }
          .width('100%').alignItems(VerticalAlign.Top)
          Row() {
            Text('颜色').fontSize(fs(this.ts, 11)).fontColor(SUB).width(44)
            Text(RelicRepo.get().colorName(this.openRelic()!.palette)).fontSize(fs(this.ts, 12)).fontColor(INK)
          }
          .width('100%')
          Row() {
            Text('藏地').fontSize(fs(this.ts, 11)).fontColor(SUB).width(44)
            Text(this.openRelic()!.hold).fontSize(fs(this.ts, 12)).fontColor(INK).layoutWeight(1)
          }
          .width('100%').alignItems(VerticalAlign.Top)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 18, right: 18 })

        Text(this.openRelic()!.desc)
          .fontSize(fs(this.ts, 12)).fontColor(SUB).lineHeight(fs(this.ts, 19)).width('100%')
          .padding({ left: 18, right: 18 })
        Text('知道了')
          .fontSize(fs(this.ts, 13)).fontColor('#FFFFFF')
          .padding({ left: 26, right: 26, top: 8, bottom: 8 })
          .backgroundColor(CLAY).borderRadius(17)
          .margin({ top: 4 })
          .onClick((): void => {
            this.openId = '';
          })
      }
      .width('82%')
      .padding({ top: 18, bottom: 18 })
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(16)
    }
    .width('100%').height('100%')
    .zIndex(50)
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Text(`共 ${RelicRepo.get().relics.length} 件 · 现显示 ${this.shown().length} 件`)
            .fontSize(fs(this.ts, 10)).fontColor(SUB)
          Blank()
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 8 })

        // 搜索：名称 / 质地 / 年代 / 纹样都能撞一下
        TextInput({ placeholder: '搜文物名称、质地或纹样', text: this.kw })
          .fontSize(fs(this.ts, 13)).fontColor(INK).placeholderColor('#B7A995')
          .backgroundColor('rgba(255,255,255,0.86)')
          .border({ width: 1, color: LINE }).borderRadius(17)
          .height(36).margin({ left: 14, right: 14, top: 6 })
          .enterKeyType(EnterKeyType.Search)
          .onChange((v: string): void => {
            this.kw = v;
          })

        Scroll() {
          Column({ space: 12 }) {
            // 筛选栏：分类 / 年代组内多选，颜色只单选，组间取交集
            Column({ space: 8 }) {
              this.groupHead('分类')
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                ForEach(RELIC_CATS, (c: string): void => {
                  Column() {
                    this.chip({ label: c, on: this.cats.indexOf(c) >= 0, act: (): void => {
                      this.cats = this.flip(this.cats, c);
                    } })
                  }.margin({ right: 6, bottom: 6 })
                }, (c: string): string => 'fc_' + c)
              }
              .width('100%')

              this.groupHead('年代')
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                ForEach(RELIC_ERAS, (e: string): void => {
                  Column() {
                    this.chip({ label: e, on: this.eras.indexOf(e) >= 0, act: (): void => {
                      this.eras = this.flip(this.eras, e);
                    } })
                  }.margin({ right: 6, bottom: 6 })
                }, (e: string): string => 'fe_' + e)
              }
              .width('100%')

              this.groupHead('颜色')
              Row() {
                ForEach(RELIC_COLORS, (c: ColorSeed): void => {
                  this.colorDot(c)
                }, (c: ColorSeed): string => 'fd_' + c.key)
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween)

              Row() {
                Text(this.filtered() ? `已筛 ${this.cats.length + this.eras.length + this.colors.length} 项`
                  : '未筛选，看全部')
                  .fontSize(fs(this.ts, 10)).fontColor(SUB)
                Blank()
                if (this.filtered() || this.kw.length > 0) {
                  Text('清空全部')
                    .fontSize(fs(this.ts, 11)).fontColor(CLAY)
                    .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                    .border({ width: 1, color: CLAY }).borderRadius(11)
                    .onClick((): void => {
                      this.clearAll();
                      this.kw = '';
                    })
                }
              }
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .backgroundColor('rgba(255,255,255,0.72)')
            .borderRadius(12)
            .border({ width: 1, color: LINE })

            // 结果两列
            if (this.shown().length === 0) {
              Column({ space: 6 }) {
                Text('没有对得上的文物').fontSize(fs(this.ts, 14)).fontColor(INK)
                Text('把筛选放一放，或换个词搜').fontSize(fs(this.ts, 11)).fontColor(SUB)
              }
              .width('100%').padding({ top: 40, bottom: 40 })
            } else {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.shown(), (r: Relic, i: number): void => {
                  this.relicCell(r, i)
                }, (r: Relic): string => r.id)
              }
              .width('100%')
            }
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 8, bottom: 24 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width('100%').height('100%')

      if (this.openRelic() !== undefined) {
        this.detailOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }
}
