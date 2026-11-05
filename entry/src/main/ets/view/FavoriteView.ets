import { router } from '@kit.ArkUI';
import { SiteRepo } from '../service/SiteRepo';
import { MemoryStore } from '../service/MemoryStore';
import { FavRec, SiteInfo, TagRec } from '../model/Models';
import { fs, coverRes, INK, SUB, LOESS, CLAY } from '../common/Theme';
import { goDetail } from '../common/Nav';

@Component
export struct FavoriteView {
  @StorageLink('textScale') ts: number = 1;
  @StorageLink('dataRev') @Watch('reload') rev: number = 0;
  @State favs: FavRec[] = [];
  @State tags: TagRec[] = [];
  @State filterTag: string = '';
  @State manage: boolean = false;
  @State tagInput: string = '';
  @State renameId: string = '';
  @State sheetFav: string = '';
  @State sheetPicked: string[] = [];

  aboutToAppear(): void {
    this.reload();
  }

  reload(): void {
    this.favs = MemoryStore.get().favsActive();
    this.tags = MemoryStore.get().tagsActive();
  }

  shownFavs(): FavRec[] {
    let list = this.favs;
    if (this.filterTag.length > 0) {
      list = list.filter((f: FavRec): boolean => f.tagIds.indexOf(this.filterTag) >= 0);
    }
    return list;
  }

  tagCount(id: string): number {
    return this.favs
      .filter((f: FavRec): boolean => f.tagIds.indexOf(id) >= 0).length;
  }

  openSheet(siteId: string): void {
    let fav = MemoryStore.get().favOf(siteId);
    this.sheetPicked = fav === undefined ? [] : fav.tagIds.slice();
    this.sheetFav = siteId;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Text('我的收藏')
            .fontSize(fs(this.ts, 20))
            .fontColor(INK)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
          Text(this.manage ? '完成' : '管理标签')
            .fontSize(fs(this.ts, 13))
            .fontColor(CLAY)
            .onClick((): void => {
              this.manage = !this.manage;
            })
          Text('我的主题')
            .fontSize(fs(this.ts, 13))
            .fontColor(CLAY)
            .onClick((): void => {
              router.pushUrl({ url: 'pages/TopicPage' });
            })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12 })

        if (this.manage) {
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              TextInput({ text: this.tagInput, placeholder: this.renameId.length > 0 ? '新名字' : '新标签名' })
                .height(36)
                .fontSize(fs(this.ts, 13))
                .layoutWeight(1)
                .onChange((v: string): void => {
                  this.tagInput = v;
                })
              Button(this.renameId.length > 0 ? '保存' : '添加')
                .height(36)
                .fontSize(fs(this.ts, 13))
                .backgroundColor(LOESS)
                .onClick(async (): Promise<void> => {
                  if (this.renameId.length > 0) {
                    await MemoryStore.get().renameTag(this.renameId, this.tagInput);
                    this.renameId = '';
                  } else {
                    await MemoryStore.get().addTag(this.tagInput);
                  }
                  this.tagInput = '';
                })
            }
            ForEach(this.tags, (t: TagRec): void => {
              Row({ space: 10 }) {
                Text(t.name).fontSize(fs(this.ts, 14)).fontColor(INK).layoutWeight(1)
                Text(`${this.tagCount(t.id)} 条`).fontSize(fs(this.ts, 12)).fontColor(SUB)
                Text('改名').fontSize(fs(this.ts, 12)).fontColor(CLAY)
                  .onClick((): void => {
                    this.renameId = t.id;
                    this.tagInput = t.name;
                  })
                Text('删除').fontSize(fs(this.ts, 12)).fontColor(SUB)
                  .onClick(async (): Promise<void> => {
                    await MemoryStore.get().deleteTag(t.id);
                  })
              }
              .width('100%')
            }, (t: TagRec): string => t.id + '_' + this.rev)
          }
          .padding(12)
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(10)
          .margin({ left: 14, right: 14 })
        }

        Scroll() {
          Row({ space: 8 }) {
            Text('全部')
              .fontSize(fs(this.ts, 13))
              .fontColor(this.filterTag.length === 0 ? Color.White : SUB)
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .borderRadius(13)
              .backgroundColor(this.filterTag.length === 0 ? CLAY : $r('app.color.card_bg'))
              .onClick((): void => {
                this.filterTag = '';
              })
            ForEach(this.tags, (t: TagRec): void => {
              Text(t.name)
                .fontSize(fs(this.ts, 13))
                .fontColor(this.filterTag === t.id ? Color.White : SUB)
                .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                .borderRadius(13)
                .backgroundColor(this.filterTag === t.id ? CLAY : $r('app.color.card_bg'))
                .onClick((): void => {
                  this.filterTag = this.filterTag === t.id ? '' : t.id;
                })
            }, (t: TagRec): string => t.id + '_' + this.rev)
          }
          .padding({ left: 14, right: 14 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')

        if (this.shownFavs().length === 0) {
          Column({ space: 6 }) {
            Text('这里还是空的').fontSize(fs(this.ts, 15)).fontColor(INK)
            Text('去探索页找一处遗址，点星标收进来').fontSize(fs(this.ts, 12)).fontColor(SUB)
          }
          .margin({ top: 60 })
        } else {
          List({ space: 8 }) {
            ForEach(this.shownFavs(), (f: FavRec): void => {
              ListItem() {
                this.favRow(f)
              }
            }, (f: FavRec): string => f.siteId + '_' + f.tagIds.join(',') + '_' + this.rev)
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .padding({ left: 14, right: 14 })
        }
        Blank().height(10)
      }
      .width('100%')
      .height('100%')

      if (this.sheetFav.length > 0) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')
          .onClick((): void => {
            this.sheetFav = '';
          })
        Column({ space: 10 }) {
          Text('归类到标签').fontSize(fs(this.ts, 16)).fontColor(INK).fontWeight(FontWeight.Medium)
          ForEach(this.tags, (t: TagRec): void => {
            Row() {
              Text(t.name).fontSize(fs(this.ts, 14)).fontColor(INK).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.sheetPicked.indexOf(t.id) >= 0 })
                .selectedColor(CLAY)
                .onChange((on: boolean): void => {
                  let i = this.sheetPicked.indexOf(t.id);
                  if (on && i < 0) {
                    this.sheetPicked.push(t.id);
                  } else if (!on && i >= 0) {
                    this.sheetPicked.splice(i, 1);
                  }
                })
            }.width('100%')
          }, (t: TagRec): string => t.id)
          Button('保存归类')
            .backgroundColor(LOESS)
            .fontColor(Color.White)
            .onClick(async (): Promise<void> => {
              await MemoryStore.get().setFavTags(this.sheetFav, this.sheetPicked);
              this.sheetFav = '';
            })
        }
        .width('100%')
        .padding(16)
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius({ topLeft: 16, topRight: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }

  @Builder
  favRow(f: FavRec) {
    if (SiteRepo.get().byId(f.siteId) !== undefined) {
      Row({ space: 10 }) {
        Image(coverRes((SiteRepo.get().byId(f.siteId) as SiteInfo).cover))
          .width(56)
          .height(56)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
        Column({ space: 4 }) {
          Text((SiteRepo.get().byId(f.siteId) as SiteInfo).name)
            .fontSize(fs(this.ts, 15)).fontColor(INK).fontWeight(FontWeight.Medium)
          Text(`${(SiteRepo.get().byId(f.siteId) as SiteInfo).city} · ${(SiteRepo.get().byId(f.siteId) as SiteInfo).eras.join('/')}`)
            .fontSize(fs(this.ts, 12)).fontColor(SUB)
          Row({ space: 4 }) {
            ForEach(f.tagIds, (tid: string): void => {
              Text(MemoryStore.get().tagName(tid))
                .fontSize(fs(this.ts, 10))
                .fontColor(CLAY)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .border({ width: 1, color: '#D9C9A8' })
                .borderRadius(8)
            }, (tid: string): string => tid)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column({ space: 8 }) {
          Text('归类').fontSize(fs(this.ts, 12)).fontColor(CLAY)
            .onClick((): void => {
              this.openSheet(f.siteId);
            })
          Text('移除').fontSize(fs(this.ts, 12)).fontColor(SUB)
            .onClick(async (): Promise<void> => {
              await MemoryStore.get().removeFav(f.siteId);
            })
        }
      }
      .width('100%')
      .padding(10)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(10)
      .onClick((): void => {
        goDetail(f.siteId);
      })
    }
  }
}
