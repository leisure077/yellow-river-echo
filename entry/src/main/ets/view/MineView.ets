import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { WorkRec, SiteInfo, NoteRec, Goods } from '../model/Models';
import { SiteRepo } from '../service/SiteRepo';
import { MemoryStore } from '../service/MemoryStore';
import { StudioStore } from '../service/StudioStore';
import { ContentRepo } from '../service/ContentRepo';
import { SyncService } from '../service/SyncService';
import { BackupService } from '../service/BackupService';
import { ArtCover } from './ArtCover';
import { fs, INK, SUB, LOESS, CLAY, fmtTime, agoText, moneyText, coverRes, coverOf, paletteOf } from '../common/Theme';
import { openDrawer, goSync, goTopic, goCourses, goPottery, goDetail, goNote, goArchive, goGoods, switchTab, openSignOutAsk } from '../common/Nav';
import { padX, rowSize } from '../common/Breakpoint';

const SHAPES: string[] = ['pot', 'jar', 'ding', 'tile', 'stele', 'tower', 'cave', 'scroll', 'coin', 'box', 'bridge', 'kiln'];

// @Builder 用对象字面量收参，数字改了才会跟着重画；传值只是建时快照
interface StatArg {
  title: string;
  value: string;
}

interface FuncArg {
  icon: string;
  title: string;
  value: string;
  onTap: () => void;
}

@Component
export struct MineView {
  // 字号档位变了要整页重画：不持有这行，切档后这一页还是老字号
  @StorageLink('textScale') ts: number = 1;
  @StorageLink('dataRev') @Watch('syncCount') dataRev: number = 0;
  @StorageLink('syncRev') @Watch('syncCount') syncRev: number = 0;
  @StorageLink('studioRev') @Watch('syncCount') studioRev: number = 0;
  @StorageLink('bp') bp: string = 'sm';
  @State busy: boolean = false;
  @State sub: number = 0;
  @State bioEdit: boolean = false;
  @State bioText: string = '';
  @State workN: number = 0;
  @State favN: number = 0;
  @State noteN: number = 0;
  @State readN: number = 0;
  @State streakN: number = 0;
  @State likeN: number = 0;
  @State nick: string = '';
  @State bio: string = '';
  @State viewN: number = 0;
  @State localOn: boolean = false;
  @State accN: number = 0;

  aboutToAppear(): void {
    this.syncCount();
  }

  // 上面那排数字得跟着删改走，绑到状态变量上才会重画
  syncCount(): void {
    let st = StudioStore.get();
    let mem = MemoryStore.get();
    this.workN = st.works.length;
    this.favN = mem.favsActive().length;
    this.noteN = mem.notesActive().length;
    this.readN = mem.readCount();
    this.streakN = st.streak();
    this.likeN = this.likedGoods().length;
    this.nick = st.profile.nick;
    this.bio = st.profile.bio;
    this.viewN = mem.views.length;
    this.localOn = SyncService.get().localOnly;
    this.accN = st.accounts.length;
  }

  async doExport(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    let ctx = getContext(this) as common.UIAbilityContext;
    let msg = await BackupService.exportSnapshot(ctx);
    this.busy = false;
    promptAction.showToast({ message: msg });
  }

  async doRestore(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    let ctx = getContext(this) as common.UIAbilityContext;
    let msg = await BackupService.restoreSnapshot(ctx);
    this.busy = false;
    promptAction.showToast({ message: msg });
  }

  avatarKey(): string {
    let n = StudioStore.get().profile.avatar;
    let keys: string[] = ['yangshao', 'longshan', 'xiashang', 'zhou', 'hantang', 'song'];
    return keys[n >= 0 && n < keys.length ? n : 0];
  }

  shapeOf(s: string): string {
    return SHAPES.indexOf(s) >= 0 ? s : 'pot';
  }

  coverName(site: SiteInfo): string {
    return site.cover.length > 0 ? site.cover : coverOf(site.eras[0]);
  }

  noteSite(siteId: string): string {
    let s = SiteRepo.get().byId(siteId);
    return s === undefined ? '游离笔记' : s.name;
  }

  noteTag(id: string): string {
    let s = SyncService.get();
    if (s.localOnly) {
      return '本机';
    }
    return s.dirty.has('note:' + id) ? '待同步' : '已同步';
  }

  chunk<T>(arr: T[], size: number): T[][] {
    let out: T[][] = [];
    let cur: T[] = [];
    for (let i = 0; i < arr.length; i++) {
      cur.push(arr[i]);
      if (cur.length === size) {
        out.push(cur);
        cur = [];
      }
    }
    if (cur.length > 0) {
      out.push(cur);
    }
    return out;
  }

  // 一行没铺满要补空位，否则最后一格的 layoutWeight 会把卡片拉宽。
  // 列数是问断点要的，手机 3 列时补位数量和原来写死的分支一模一样。
  blanks(rowLen: number, cols: number): number[] {
    let out: number[] = [];
    for (let i = rowLen; i < cols; i++) {
      out.push(i);
    }
    return out;
  }

  workCols(): number {
    return rowSize(this.bp, 3);
  }

  goodCols(): number {
    return rowSize(this.bp, 2);
  }

  workRows(): WorkRec[][] {
    return this.chunk(StudioStore.get().works, this.workCols());
  }

  favSites(): SiteInfo[] {
    let out: SiteInfo[] = [];
    let repo = SiteRepo.get();
    let ids = MemoryStore.get().favIds();
    for (let id of ids) {
      let s = repo.byId(id);
      if (s !== undefined) {
        out.push(s);
      }
    }
    return out;
  }

  favRows(): SiteInfo[][] {
    return this.chunk(this.favSites(), this.workCols());
  }

  likedGoods(): Goods[] {
    let out: Goods[] = [];
    let repo = ContentRepo.get();
    let ids = StudioStore.get().likes;
    for (let id of ids) {
      let g = repo.goodOf(id);
      if (g !== undefined) {
        out.push(g);
      }
    }
    return out;
  }

  goodRows(): Goods[][] {
    return this.chunk(this.likedGoods(), this.goodCols());
  }

  @Builder
  statCell(arg: StatArg) {
    Column({ space: 2 }) {
      Text(arg.value).fontSize(fs(this.ts, 16)).fontColor(INK).fontWeight(FontWeight.Bold)
      Text(arg.title).fontSize(fs(this.ts, 10)).fontColor(SUB)
    }
    .layoutWeight(1)
  }

  @Builder
  tabCell(idx: number, title: string) {
    Column({ space: 5 }) {
      Text(title).fontSize(fs(this.ts, 15))
        .fontColor(this.sub === idx ? INK : SUB)
        .fontWeight(this.sub === idx ? FontWeight.Bold : FontWeight.Normal)
      Column().width(20).height(3).borderRadius(2)
        .backgroundColor(this.sub === idx ? CLAY : Color.Transparent)
    }
    .layoutWeight(1)
    .padding({ top: 8, bottom: 6 })
    .onClick((): void => {
      this.sub = idx;
    })
  }

  @Builder
  guide(text: string, btn: string, act: () => void) {
    Column({ space: 10 }) {
      Text(text).fontSize(fs(this.ts, 13)).fontColor(SUB)
      Text(btn).fontSize(fs(this.ts, 13)).fontColor('#FFFFFF')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor(CLAY).borderRadius(18)
        .onClick((): void => {
          act();
        })
    }
    .width('100%')
    .padding({ top: 34, bottom: 34 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  funcRow(arg: FuncArg) {
    Row({ space: 12 }) {
      Text(arg.icon).fontSize(fs(this.ts, 15)).fontColor(LOESS).width(20)
      Text(arg.title).fontSize(fs(this.ts, 15)).fontColor(INK).layoutWeight(1)
      if (arg.value.length > 0) {
        Text(arg.value).fontSize(fs(this.ts, 12)).fontColor(SUB)
      }
      Text('›').fontSize(fs(this.ts, 16)).fontColor(SUB)
    }
    .width('100%')
    .height(48)
    .padding({ left: 14, right: 14 })
    .onClick((): void => {
      arg.onTap();
    })
  }

  @Builder
  workCell(w: WorkRec, seed: number) {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        ArtCover({ palette: w.glaze, shape: this.shapeOf(w.shape), seed: seed, label: w.word })
          .width('100%').height('100%')
        Text('✕').fontSize(fs(this.ts, 11)).fontColor('#FFFFFF')
          .width(20).height(20).textAlign(TextAlign.Center)
          .backgroundColor('rgba(43,38,34,0.45)').borderRadius(10)
          .margin(5)
          .onClick((): void => {
            StudioStore.get().dropWork(w.id);
          })
      }
      .width('100%').aspectRatio(1).borderRadius(10).clip(true)
      Text(w.name).fontSize(fs(this.ts, 12)).fontColor(INK).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').margin({ top: 4 })
      Text(fmtTime(w.createdAt).substring(0, 10)).fontSize(fs(this.ts, 10)).fontColor(SUB)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  favCell(s: SiteInfo) {
    Column({ space: 3 }) {
      Image(coverRes(this.coverName(s)))
        .width('100%').aspectRatio(1).objectFit(ImageFit.Cover).borderRadius(10)
      Text(s.name).fontSize(fs(this.ts, 12)).fontColor(INK).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      Text(s.city).fontSize(fs(this.ts, 10)).fontColor(SUB)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .onClick((): void => {
      goDetail(s.id);
    })
  }

  @Builder
  goodCell(g: Goods, idx: number) {
    Column({ space: 4 }) {
      ArtCover({ palette: g.palette, shape: 'box', seed: idx, label: '', img: g.img })
        .width('100%').aspectRatio(1).borderRadius(10)
      Text(g.name).fontSize(fs(this.ts, 12)).fontColor(INK).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      Row() {
        Text('¥' + moneyText(g.price)).fontSize(fs(this.ts, 12)).fontColor(CLAY).fontWeight(FontWeight.Medium)
        Blank()
        Text('取消点赞').fontSize(fs(this.ts, 10)).fontColor(SUB)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor($r('app.color.page_bg')).borderRadius(10)
          .onClick((): void => {
            StudioStore.get().toggleLike(g.id);
          })
      }
      .width('100%')
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .onClick((): void => {
      goGoods(g.id);
    })
  }

  @Builder
  noteCell(n: NoteRec) {
    Column({ space: 5 }) {
      Row() {
        Text(this.noteSite(n.siteId)).fontSize(fs(this.ts, 13)).fontColor(CLAY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Text(this.noteTag(n.id)).fontSize(fs(this.ts, 10)).fontColor(SUB)
          .padding({ left: 7, right: 7, top: 3, bottom: 3 })
          .backgroundColor($r('app.color.page_bg')).borderRadius(8)
        Text(agoText(n.updatedAt)).fontSize(fs(this.ts, 10)).fontColor(SUB).margin({ left: 8 })
      }
      .width('100%')
      Text(n.text).fontSize(fs(this.ts, 13)).fontColor(INK).maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(10)
    .onClick((): void => {
      goNote(n.siteId, n.id);
    })
  }

  @Builder
  profileBlock() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Column() {
          Text(this.nick.substring(0, 1))
            .fontSize(fs(this.ts, 22)).fontColor(paletteOf(this.avatarKey()).ink).fontWeight(FontWeight.Bold)
        }
        .width(56).height(56).borderRadius(28)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(paletteOf(this.avatarKey()).deep)

        Column({ space: 3 }) {
          Text(this.nick.length > 0 ? this.nick : '未命名')
            .fontSize(fs(this.ts, 18)).fontColor(INK).fontWeight(FontWeight.Bold).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.bio).fontSize(fs(this.ts, 12)).fontColor(SUB).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('编辑').fontSize(fs(this.ts, 13)).fontColor(INK)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .border({ width: 1, color: $r('app.color.line') }).borderRadius(16)
          .onClick((): void => {
            this.bioText = StudioStore.get().profile.bio;
            this.bioEdit = true;
          })
      }
      .width('100%')

      if (this.bioEdit) {
        Column({ space: 8 }) {
          TextInput({ text: this.bioText, placeholder: '写一句签名' })
            .fontSize(fs(this.ts, 13)).fontColor(INK).backgroundColor($r('app.color.page_bg'))
            .onChange((v: string): void => {
              this.bioText = v;
            })
          Row({ space: 10 }) {
            Text('保存').fontSize(fs(this.ts, 13)).fontColor('#FFFFFF')
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .backgroundColor(CLAY).borderRadius(16)
              .onClick((): void => {
                StudioStore.get().setBio(this.bioText.trim());
                this.bioEdit = false;
                promptAction.showToast({ message: '签名已更新' });
              })
            Text('取消').fontSize(fs(this.ts, 13)).fontColor(SUB)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .backgroundColor($r('app.color.page_bg')).borderRadius(16)
              .onClick((): void => {
                this.bioEdit = false;
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.End)
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
  }

  build() {
    Column() {
      Row() {
        Text('☰').fontSize(fs(this.ts, 20)).fontColor(INK).width(48).textAlign(TextAlign.Start)
          .onClick((): void => {
            openDrawer();
          })
        Text('我的').fontSize(fs(this.ts, 17)).fontColor(INK).fontWeight(FontWeight.Bold)
          .layoutWeight(1).textAlign(TextAlign.Center)
        Text('同步').fontSize(fs(this.ts, 14)).fontColor(SUB).width(48).textAlign(TextAlign.End)
          .onClick((): void => {
            goSync();
          })
      }
      .width('100%')
      .height(48)
      .padding({ left: padX(this.bp, 14), right: padX(this.bp, 14) })

      Scroll() {
        Column({ space: 12 }) {
          this.profileBlock()

          Row() {
            this.statCell({ title: '作品', value: `${this.workN}` })
            this.statCell({ title: '收藏', value: `${this.favN}` })
            this.statCell({ title: '笔记', value: `${this.noteN}` })
            this.statCell({ title: '读完', value: `${this.readN}` })
            this.statCell({ title: '连签', value: `${this.streakN}` })
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(12)

          Column({ space: 10 }) {
            Row() {
              this.tabCell(0, '作品')
              this.tabCell(1, '收藏')
              this.tabCell(2, '笔记')
              this.tabCell(3, '喜欢')
            }
            .width('100%')

            if (this.sub === 0) {
              if (this.workN === 0) {
                this.guide('还没有作品', '去彩陶工坊做一件', (): void => {
                  goPottery();
                })
              } else {
                Column({ space: 10 }) {
                  ForEach(this.workRows(), (row: WorkRec[], ri: number): void => {
                    Row({ space: 8 }) {
                      ForEach(row, (w: WorkRec, i: number): void => {
                        this.workCell(w, ri * this.workCols() + i)
                      }, (w: WorkRec): string => w.id)
                      ForEach(this.blanks(row.length, this.workCols()), (k: number): void => {
                        Column().layoutWeight(1)
                      }, (k: number): string => 'wb' + k)
                    }
                    .width('100%')
                  }, (row: WorkRec[]): string => 'wr_' + row[0].id)
                }
                .width('100%')
              }
            } else if (this.sub === 1) {
              if (this.favN === 0) {
                this.guide('还没有收藏遗址', '去档案库看看', (): void => {
                  goArchive(0);
                })
              } else {
                Column({ space: 10 }) {
                  ForEach(this.favRows(), (row: SiteInfo[]): void => {
                    Row({ space: 8 }) {
                      ForEach(row, (s: SiteInfo): void => {
                        this.favCell(s)
                      }, (s: SiteInfo): string => s.id)
                      ForEach(this.blanks(row.length, this.workCols()), (k: number): void => {
                        Column().layoutWeight(1)
                      }, (k: number): string => 'fb' + k)
                    }
                    .width('100%')
                  }, (row: SiteInfo[]): string => 'fr_' + row[0].id)
                }
                .width('100%')
              }
            } else if (this.sub === 2) {
              if (this.noteN === 0) {
                this.guide('还没写过笔记', '挑一处遗址记两行', (): void => {
                  goArchive(2);
                })
              } else {
                Column({ space: 8 }) {
                  ForEach(MemoryStore.get().notesActive(), (n: NoteRec): void => {
                    this.noteCell(n)
                  }, (n: NoteRec): string => n.id)
                }
                .width('100%')
              }
            } else {
              if (this.likeN === 0) {
                this.guide('还没有点过赞', '去文创页逛逛', (): void => {
                  switchTab(1);
                })
              } else {
                Column({ space: 10 }) {
                  ForEach(this.goodRows(), (row: Goods[], ri: number): void => {
                    Row({ space: 8 }) {
                      ForEach(row, (g: Goods, i: number): void => {
                        this.goodCell(g, ri * this.goodCols() + i)
                      }, (g: Goods): string => 'lr_' + g.id)
                      ForEach(this.blanks(row.length, this.goodCols()), (k: number): void => {
                        Column().layoutWeight(1)
                      }, (k: number): string => 'gb' + k)
                    }
                    .width('100%')
                  }, (row: Goods[]): string => 'gr_' + row[0].id)
                }
                .width('100%')
              }
            }
          }
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(12)

          Column() {
            this.funcRow({ icon: '⇄', title: '同步面板', value: '', onTap: (): void => {
              goSync();
            } })
            Divider().color($r('app.color.line'))
            this.funcRow({ icon: '⊚', title: '主题知识网络', value: '', onTap: (): void => {
              goTopic();
            } })
            Divider().color($r('app.color.line'))
            this.funcRow({ icon: '☼', title: '课程影像', value: '', onTap: (): void => {
              goCourses();
            } })
            Divider().color($r('app.color.line'))
            Row({ space: 12 }) {
              Text('◎').fontSize(fs(this.ts, 15)).fontColor(LOESS).width(20)
              Text('离线模式').fontSize(fs(this.ts, 15)).fontColor(INK).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.localOn })
                .selectedColor(LOESS)
                .onChange((on: boolean): void => {
                  SyncService.get().setLocalOnly(on);
                })
            }
            .width('100%')
            .height(48)
            .padding({ left: 14, right: 14 })

            Divider().color($r('app.color.line'))
            this.funcRow({ icon: '↥', title: '导出备份', value: this.busy ? '正在打包…' : '', onTap: (): void => {
              this.doExport();
            } })
            Divider().color($r('app.color.line'))
            this.funcRow({ icon: '↧', title: '导入恢复', value: this.busy ? '正在处理…' : '', onTap: (): void => {
              this.doRestore();
            } })
            Divider().color($r('app.color.line'))
            this.funcRow({ icon: '✕', title: '清空浏览记录', value: `${this.viewN} 条`, onTap: (): void => {
              MemoryStore.get().clearViews();
              promptAction.showToast({ message: '已清空，推荐会回到精选' });
            } })

            Divider().color($r('app.color.line'))
            Row({ space: 12 }) {
              Text('⏻').fontSize(fs(this.ts, 15)).fontColor(CLAY).width(20)
              Text('退出登录').fontSize(fs(this.ts, 15)).fontColor(CLAY).layoutWeight(1)
              Text(this.nick.length > 0 ? this.nick : '未登录').fontSize(fs(this.ts, 12)).fontColor(SUB)
              Text('›').fontSize(fs(this.ts, 16)).fontColor(SUB)
            }
            .width('100%')
            .height(48)
            .padding({ left: 14, right: 14 })
            .onClick((): void => {
              openSignOutAsk();
            })
          }
          .padding({ top: 6, bottom: 6 })
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(12)

          Text('黄河续响平台')
            .fontSize(fs(this.ts, 10)).fontColor(SUB).textAlign(TextAlign.Center)
            .margin({ top: 8, bottom: 18 })
        }
        .width('100%')
        .padding({ left: padX(this.bp, 14), right: padX(this.bp, 14) })
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
