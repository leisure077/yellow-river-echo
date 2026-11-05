import { promptAction } from '@kit.ArkUI';
import { SiteRepo } from '../service/SiteRepo';
import { MemoryStore } from '../service/MemoryStore';
import { SyncService } from '../service/SyncService';
import { NoteRec, SiteInfo } from '../model/Models';
import { fs, INK, SUB, LOESS, CLAY, fmtTime } from '../common/Theme';
import { goNote } from '../common/Nav';

@Component
export struct NoteView {
  
  @StorageLink('textScale') ts: number = 1;
  @StorageLink('dataRev') @Watch('reload') rev: number = 0;
  @StorageLink('syncRev') syncRev: number = 0;
  
  @State notes: NoteRec[] = [];
  @State organize: boolean = false;
  @State sel: string[] = [];
  @State pickSite: boolean = false;
  @State mergeOpen: boolean = false;
  @State mergeText: string = '';

  aboutToAppear(): void {
    this.reload();
  }

  reload(): void {
    this.notes = MemoryStore.get().notesActive();
  }

  syncBadge(n: NoteRec): string {
    let s = SyncService.get();
    if (s.state !== 'ready' || s.localOnly) {
      return '仅本机';
    }
    return s.dirty.has('note:' + n.id) ? '待同步' : '已同步';
  }

  siteName(id: string): string {
    let s = SiteRepo.get().byId(id);
    return s === undefined ? '游离笔记' : s.name;
  }

  canMerge(): boolean {
    if (this.sel.length < 2) {
      return false;
    }
    let first = MemoryStore.get().noteOf(this.sel[0]);
    if (first === undefined) {
      return false;
    }
    for (let id of this.sel) {
      let n = MemoryStore.get().noteOf(id);
      if (n === undefined || n.siteId !== first.siteId) {
        return false;
      }
    }
    return true;
  }

  buildMerge(): string {
    let parts: string[] = [];
    for (let id of this.sel) {
      let n = MemoryStore.get().noteOf(id);
      if (n !== undefined) {
        parts.push(n.text);
      }
    }
    return parts.join('\n\n');
  }

  mergeSiteId(): string {
    let n = MemoryStore.get().noteOf(this.sel[0]);
    return n === undefined ? '' : n.siteId;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Text('我的笔记')
            .fontSize(fs(this.ts, 20))
            .fontColor(INK)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
          Text(this.organize ? '退出整理' : '整理合并')
            .fontSize(fs(this.ts, 13))
            .fontColor(CLAY)
            .onClick((): void => {
              this.organize = !this.organize;
              this.sel = [];
            })
          Text('写笔记')
            .fontSize(fs(this.ts, 13))
            .fontColor(Color.White)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor(CLAY)
            .borderRadius(12)
            .onClick((): void => {
              this.pickSite = true;
            })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12 })

        if (this.notes.length === 0) {
          Column({ space: 6 }) {
            Text('还没有写过笔记').fontSize(fs(this.ts, 15)).fontColor(INK)
            Text('在遗址详情页点「写一笔」，现场的话先存本机').fontSize(fs(this.ts, 12)).fontColor(SUB)
          }
          .margin({ top: 60 })
        } else {
          List({ space: 8 }) {
            ForEach(this.notes, (n: NoteRec): void => {
              ListItem() {
                Row({ space: 10 }) {
                  if (this.organize) {
                    Checkbox()
                      .select(this.sel.indexOf(n.id) >= 0)
                      .selectedColor(CLAY)
                      .onChange((on: boolean): void => {
                        let i = this.sel.indexOf(n.id);
                        if (on && i < 0) {
                          this.sel.push(n.id);
                        } else if (!on && i >= 0) {
                          this.sel.splice(i, 1);
                        }
                      })
                  }
                  Column({ space: 4 }) {
                    Text(this.siteName(n.siteId))
                      .fontSize(fs(this.ts, 11))
                      .fontColor(CLAY)
                    Text(n.text)
                      .fontSize(fs(this.ts, 14))
                      .fontColor(INK)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Row({ space: 8 }) {
                      Text('改于 ' + fmtTime(n.updatedAt)).fontSize(fs(this.ts, 10)).fontColor(SUB)
                      Text(this.syncBadge(n)).fontSize(fs(this.ts, 10)).fontColor(SUB)
                      if (n.srcIds !== undefined && n.srcIds.length > 0) {
                        Text(`由 ${n.srcIds.length} 篇合并`).fontSize(fs(this.ts, 10)).fontColor(LOESS)
                      }
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  if (this.organize) {
                    Column({ space: 12 }) {
                      Text('↑')
                        .fontSize(fs(this.ts, 14))
                        .fontColor(SUB)
                        .onClick(async (): Promise<void> => {
                          await MemoryStore.get().moveNote(n.id, -1);
                        })
                      Text('↓')
                        .fontSize(fs(this.ts, 14))
                        .fontColor(SUB)
                        .onClick(async (): Promise<void> => {
                          await MemoryStore.get().moveNote(n.id, 1);
                        })
                    }
                  }
                }
                .width('100%')
                .padding(12)
                .backgroundColor($r('app.color.card_bg'))
                .borderRadius(10)
                .onClick((): void => {
                  if (!this.organize) {
                    goNote('', n.id);
                  }
                })
              }
            }, (n: NoteRec, i: number): string => n.id + '_' + i + '_' + this.rev)
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .padding({ left: 14, right: 14 })
        }

        if (this.organize) {
          Row({ space: 10 }) {
            Text(`已选 ${this.sel.length} 篇 · 限同一遗址 · 箭头可调顺序`).fontSize(fs(this.ts, 12)).fontColor(SUB).layoutWeight(1)
            Button('合并')
              .enabled(this.canMerge())
              .backgroundColor(LOESS)
              .onClick((): void => {
                this.mergeText = this.buildMerge();
                this.mergeOpen = true;
              })
          }
          .width('100%')
          .padding({ left: 14, right: 14, bottom: 12 })
        }
      }
      .width('100%')
      .height('100%')

      if (this.pickSite) {
        Column()
          .width('100%').height('100%')
          .backgroundColor('#66000000')
          .onClick((): void => {
            this.pickSite = false;
          })
        Column({ space: 8 }) {
          Text('给哪处遗址记一笔').fontSize(fs(this.ts, 16)).fontColor(INK).fontWeight(FontWeight.Medium)
          List() {
            ForEach(SiteRepo.get().sites, (s: SiteInfo): void => {
              ListItem() {
                Text(s.name)
                  .fontSize(fs(this.ts, 14))
                  .fontColor(INK)
                  .width('100%')
                  .padding(10)
                  .onClick((): void => {
                    this.pickSite = false;
                    goNote(s.id, '');
                  })
              }
            }, (s: SiteInfo): string => s.id)
          }
          .height(280)
          .scrollBar(BarState.Auto)
        }
        .width('100%')
        .padding(16)
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius({ topLeft: 16, topRight: 16 })
      }

      if (this.mergeOpen) {
        Column()
          .width('100%').height('100%')
          .backgroundColor('#66000000')
          .onClick((): void => {
            this.mergeOpen = false;
          })
        Column({ space: 8 }) {
          Text('合并预览（原文都会保留）').fontSize(fs(this.ts, 16)).fontColor(INK).fontWeight(FontWeight.Medium)
          TextArea({ text: this.mergeText })
            .height(200)
            .fontSize(fs(this.ts, 13))
            .onChange((v: string): void => {
              this.mergeText = v;
            })
          Row({ space: 10 }) {
            Button('取消').backgroundColor($r('app.color.line')).fontColor(INK)
              .onClick((): void => {
                this.mergeOpen = false;
              })
            Button('存为新笔记')
              .backgroundColor(CLAY)
              .onClick(async (): Promise<void> => {
                let ids = this.sel.slice();
                let rec = await MemoryStore.get().addNote(this.mergeSiteId(), this.mergeText, ids);
                this.mergeOpen = false;
                this.sel = [];
                if (rec !== null) {
                  promptAction.showToast({ message: '已合并为一条新笔记' });
                }
              })
          }
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
}
