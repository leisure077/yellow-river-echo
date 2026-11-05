import { router, promptAction } from '@kit.ArkUI';
import { SiteInfo } from '../model/Models';
import { SiteRepo } from '../service/SiteRepo';
import { StudioStore } from '../service/StudioStore';
import { BasinMap } from '../common/BasinMap';
import { INK, SUB, LOESS, CLAY, agoText, coverRes, fs } from '../common/Theme';
import { goDetail } from '../common/Nav';

const MAP_H: number = 310;

@Entry
@Component
struct CheckinPage {
  @StorageLink('textScale') ts: number = 1;
  @StorageLink('studioRev') @Watch('reload') studioRev: number = 0;
  @State sites: SiteInfo[] = [];
  @State doneIds: string[] = [];
  @State checkedList: SiteInfo[] = [];
  @State sel: SiteInfo | undefined = undefined;
  @State flashReq: string = '';
  private flashSeq: number = 0;

  aboutToAppear(): void {
    this.reload();
  }

  reload(): void {
    this.sites = SiteRepo.get().sites;
    this.doneIds = StudioStore.get().checkedSiteIds();
    let list: SiteInfo[] = [];
    for (let c of StudioStore.get().siteCheckins) {
      let s = SiteRepo.get().byId(c.siteId);
      if (s !== undefined) {
        list.push(s);
      }
    }
    this.checkedList = list;
  }

  isChecked(id: string): boolean {
    return this.doneIds.indexOf(id) >= 0;
  }

  checkedLabel(): string {
    let s = this.sel;
    if (s === undefined) {
      return '已打卡';
    }
    let r = StudioStore.get().checkinOf(s.id);
    return r === undefined ? '已打卡 · 刚刚' : '已打卡 · ' + agoText(r.at);
  }

  pickSite(id: string): void {
    let s = SiteRepo.get().byId(id);
    if (s !== undefined) {
      this.sel = s;
    }
  }

  flash(id: string): void {
    this.flashSeq = this.flashSeq + 1;
    this.flashReq = `${id}|${this.flashSeq}`;
  }

  doCheckin(): void {
    let s = this.sel;
    if (s === undefined) {
      return;
    }
    if (StudioStore.get().checkinSite(s.id)) {
      this.flash(s.id);
      promptAction.showToast({ message: '已盖章：' + s.name });
    }
  }

  undoCheckin(): void {
    let s = this.sel;
    if (s === undefined) {
      return;
    }
    StudioStore.get().undoCheckinSite(s.id);
    promptAction.showToast({ message: '已撤销这一步' });
  }

  @Builder
  chip(col: string, text: string) {
    Row({ space: 5 }) {
      Circle().width(9).height(9).fill(col)
      Text(text).fontSize(fs(this.ts, 11)).fontColor(SUB)
    }
  }

  @Builder
  selCard() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Image(coverRes(this.sel!.cover))
          .width(56).height(56).borderRadius(8).objectFit(ImageFit.Cover)
        Column({ space: 3 }) {
          Text(this.sel!.name)
            .fontSize(fs(this.ts, 16)).fontColor(INK).fontWeight(FontWeight.Bold)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${this.sel!.city} · ${this.sel!.eras.join('/')} · ${this.sel!.types.join('/')}`)
            .fontSize(fs(this.ts, 11)).fontColor(SUB)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('看档案 ›')
          .fontSize(fs(this.ts, 12)).fontColor(CLAY)
          .onClick((): void => {
            goDetail(this.sel!.id);
          })
      }
      .width('100%')

      Row({ space: 10 }) {
        if (this.isChecked(this.sel!.id)) {
          Text(this.checkedLabel())
            .fontSize(fs(this.ts, 12)).fontColor(LOESS).layoutWeight(1)
          Text('撤销这一步')
            .fontSize(fs(this.ts, 12)).fontColor(SUB)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .border({ width: 1, color: $r('app.color.line') })
            .borderRadius(14)
            .onClick((): void => {
              this.undoCheckin();
            })
        } else {
          Text('这一步还没走过').fontSize(fs(this.ts, 12)).fontColor(SUB).layoutWeight(1)
          Text('盖章打卡')
            .fontSize(fs(this.ts, 13)).fontColor('#FFFFFF')
            .padding({ left: 16, right: 16, top: 7, bottom: 7 })
            .backgroundColor(CLAY)
            .borderRadius(15)
            .onClick((): void => {
              this.doCheckin();
            })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(14)
  }

  @Builder
  emptyCard() {
    Column({ space: 6 }) {
      Text('点河道上的一个小圆').fontSize(fs(this.ts, 13)).fontColor(INK)
      Text('遗址圈都在河南流域那一段：按右下角「河南流域」一键放大，或双指放大地图。点发光的水面还会溅起水花')
        .fontSize(fs(this.ts, 11)).fontColor(SUB)
    }
    .width('100%')
    .padding({ top: 18, bottom: 18 })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(14)
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text('‹ 返回').fontSize(fs(this.ts, 15)).fontColor(CLAY)
          .onClick((): void => {
            router.back();
          })
        Text('河图洛书').fontSize(fs(this.ts, 18)).fontColor(INK).fontWeight(FontWeight.Bold).layoutWeight(1)
        Text(`${this.doneIds.length} / ${this.sites.length}`).fontSize(fs(this.ts, 14)).fontColor(LOESS)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10 })

      Scroll() {
        Column({ space: 12 }) {
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Text('黄河全流域 · 水系脉络').fontSize(fs(this.ts, 14)).fontColor('#F2E6CF').fontWeight(FontWeight.Medium)
              Blank()
              Text('双指缩放 · 拖动平移 · 点河道溅水花').fontSize(fs(this.ts, 10)).fontColor('rgba(226,216,196,0.62)')
            }
            .width('100%')

            BasinMap({
              mapHeight: MAP_H,
              activeId: this.sel === undefined ? '' : this.sel!.id,
              flashReq: this.flashReq,
              onSitePick: (id: string): void => {
                this.pickSite(id);
              },
              onMiss: (x: number, y: number): void => {
                promptAction.showToast({ message: '点亮的黄色是黄河干流，银白色是支流' });
              }
            })

            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
              Row({ space: 4 }) {
                Circle().width(8).height(8).fill('#FFD873')
                Text('干流').fontSize(fs(this.ts, 10)).fontColor('#A9B4C4')
              }.margin({ right: 12, bottom: 4 })
              Row({ space: 4 }) {
                Circle().width(8).height(8).fill('#CBD6E6')
                Text('大小支流').fontSize(fs(this.ts, 10)).fontColor('#A9B4C4')
              }.margin({ right: 12, bottom: 4 })
              Row({ space: 4 }) {
                Circle().width(8).height(8).fill(CLAY)
                Text('盖过章的遗址').fontSize(fs(this.ts, 10)).fontColor('#A9B4C4')
              }.margin({ right: 12, bottom: 4 })
              Row({ space: 4 }) {
                Circle().width(8).height(8).fill('#F0EBE2')
                Text('城镇').fontSize(fs(this.ts, 10)).fontColor('#A9B4C4')
              }.margin({ bottom: 4 })
            }
            .width('100%')
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#1A212A')
          .borderRadius(16)

          Stack({ alignContent: Alignment.BottomStart }) {
            Image($r('app.media.hh_scene_a'))
              .width('100%').height(92).borderRadius(10).objectFit(ImageFit.Cover)
            Text('黄河乾坤湾 · 实景')
              .fontSize(fs(this.ts, 10)).fontColor('#FFFFFF')
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .backgroundColor('rgba(43,38,34,0.45)')
              .borderRadius({ topLeft: 10, bottomRight: 10 })
              .margin(6)
          }
          .width('100%')

          if (this.sel === undefined) {
            this.emptyCard()
          } else {
            this.selCard()
          }

          Column({ space: 6 }) {
            Row() {
              Text('这条河走了').fontSize(fs(this.ts, 12)).fontColor(SUB)
              Blank()
              Text(`${Math.round(this.sites.length === 0 ? 0 :
                this.doneIds.length * 100 / this.sites.length)}%`)
                .fontSize(fs(this.ts, 12)).fontColor(CLAY).fontWeight(FontWeight.Medium)
            }
            .width('100%')
            Stack({ alignContent: Alignment.Start }) {
              Column().width('100%').height(6).borderRadius(3)
                .backgroundColor($r('app.color.line'))
              Column().width(`${this.sites.length === 0 ? 0 :
                Math.round(this.doneIds.length * 100 / this.sites.length)}%`)
                .height(6).borderRadius(3)
                .backgroundColor(LOESS)
            }
            .width('100%')
          }
          .width('100%')
          .padding(14)
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(14)

          Column({ space: 8 }) {
            Row() {
              Text('盖过的章').fontSize(fs(this.ts, 16)).fontColor(INK).fontWeight(FontWeight.Medium)
              Blank()
              Text(`${this.checkedList.length} 处`).fontSize(fs(this.ts, 11)).fontColor(SUB)
            }
            .width('100%')

            if (this.checkedList.length === 0) {
              Text('还没有章。河道上随便点一个圈，先盖一个试试')
                .fontSize(fs(this.ts, 12)).fontColor(SUB)
                .width('100%').padding({ top: 8, bottom: 8 })
            } else {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.checkedList, (s: SiteInfo): void => {
                  Row({ space: 5 }) {
                    Text(s.name.substring(0, 1))
                      .fontSize(fs(this.ts, 10)).fontColor('#F6E2CE')
                      .width(16).height(16).borderRadius(4)
                      .textAlign(TextAlign.Center)
                      .backgroundColor('rgba(166,85,61,0.86)')
                    Text(s.name).fontSize(fs(this.ts, 12)).fontColor(INK)
                  }
                  .padding({ left: 8, right: 10, top: 5, bottom: 5 })
                  .margin({ right: 8, bottom: 8 })
                  .backgroundColor($r('app.color.card_bg'))
                  .border({ width: 1, color: '#D9C9A8' })
                  .borderRadius(14)
                  .onClick((): void => {
                    goDetail(s.id);
                  })
                }, (s: SiteInfo): string => s.id)
              }
              .width('100%')
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
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
