import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { MemoryStore } from '../service/MemoryStore';
import { SyncService, DeviceRow, ConflictRow } from '../service/SyncService';
import { SiteRepo } from '../service/SiteRepo';
import { BackupService } from '../service/BackupService';
import { StudioStore } from '../service/StudioStore';
import { NoteRec, SnapshotRow, DirStat } from '../model/Models';
import { fs, INK, SUB, LOESS, CLAY, RIVER, fmtTime } from '../common/Theme';

interface MetricArg {
  title: string;
  value: string;
}

@Entry
@Component
struct SyncPage {
  @StorageLink('textScale') ts: number = 1;
  @StorageLink('syncRev') @Watch('sync') syncRev: number = 0;
  @StorageLink('dataRev') rev: number = 0;
  @State hint: string = '';
  @State pending: number = 0;
  @State conflictN: number = 0;
  @State devN: number = 0;
  @State lastAt: number = 0;
  @State localOn: boolean = false;
  @State srvState: string = '';
  @State snaps: SnapshotRow[] = [];
  @State dirs: DirStat[] = [];
  @State canUndo: boolean = false;
  @State accN: number = 0;
  // 演示时不想在手机上敲整条地址：拉过一次就把这条留着
  @State snapUrl: string = 'http://10.0.2.2:8877/hhmem_latest.json';

  aboutToAppear(): void {
    if (BackupService.lastUrl.length > 0) {
      this.snapUrl = BackupService.lastUrl;
    }
    this.sync();
  }

  sync(): void {
    let s = SyncService.get();
    this.hint = s.hint;
    this.pending = s.pendingCount();
    this.conflictN = s.conflicts.length;
    this.devN = s.devices.length;
    this.lastAt = s.lastSyncAt;
    this.localOn = s.localOnly;
    this.srvState = s.state;
    this.accN = StudioStore.get().accounts.length;
    let ctx = getContext(this) as common.UIAbilityContext;
    this.snaps = BackupService.listSnapshots(ctx);
    this.dirs = BackupService.probeDirs(ctx);
    this.canUndo = MemoryStore.get().canUndoImport();
  }

  say(msg: string): void {
    promptAction.showToast({ message: msg });
    this.sync();
  }

  doExport(): void {
    let ctx = getContext(this) as common.UIAbilityContext;
    BackupService.exportSnapshot(ctx).then((m: string): void => {
      this.say(m);
    });
  }

  doPick(): void {
    let ctx = getContext(this) as common.UIAbilityContext;
    BackupService.restoreSnapshot(ctx).then((m: string): void => {
      this.say(m);
    });
  }

  doRestoreFrom(path: string): void {
    let ctx = getContext(this) as common.UIAbilityContext;
    BackupService.restoreFromPath(ctx, path).then((m: string): void => {
      this.say(m);
    });
  }

  doUndo(): void {
    let ctx = getContext(this) as common.UIAbilityContext;
    BackupService.undoRestore(ctx).then((m: string): void => {
      this.say(m);
    });
  }

  doFetch(): void {
    let ctx = getContext(this) as common.UIAbilityContext;
    this.say('正在从局域网取这份快照…');
    BackupService.importFromUrl(ctx, this.snapUrl).then((m: string): void => {
      this.say(m);
    });
  }

  stateText(): string {
    if (this.localOn) {
      return '本机模式';
    }
    if (this.srvState === 'ready') {
      return '同步已就绪';
    }
    if (this.srvState === 'unavailable') {
      return '本机分布式服务不可用';
    }
    return '尚未开始';
  }

  stateColor(): string {
    if (this.localOn) {
      return LOESS;
    }
    return this.srvState === 'ready' ? RIVER : (this.srvState === 'unavailable' ? CLAY : SUB);
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text('‹ 返回').fontSize(fs(this.ts, 15)).fontColor(CLAY)
          .onClick((): void => {
            router.back();
          })
        Text('同步面板').fontSize(fs(this.ts, 18)).fontColor(INK).fontWeight(FontWeight.Bold).layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10 })

      Scroll() {
        Column({ space: 12 }) {
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Circle().width(10).height(10).fill(this.stateColor())
              Text(this.stateText()).fontSize(fs(this.ts, 16)).fontColor(INK).fontWeight(FontWeight.Medium)
            }
            Text(this.hint).fontSize(fs(this.ts, 12)).fontColor(SUB)
            GridRow({ columns: 3, gutter: 8 }) {
              GridCol() {
                this.metric({ title: '待同步', value: `${this.pending}` })
              }
              GridCol() {
                this.metric({ title: '冲突', value: `${this.conflictN}` })
              }
              GridCol() {
                this.metric({ title: '设备', value: `${this.devN}` })
              }
            }
            Text('最后成功：' + fmtTime(this.lastAt))
              .fontSize(fs(this.ts, 12)).fontColor(SUB)
            Scroll() {
              Row({ space: 10 }) {
                Button('立即重试')
                  .fontSize(fs(this.ts, 13))
                  .backgroundColor(CLAY)
                  .onClick((): void => {
                    SyncService.get().retry();
                  })
                Button('刷新设备')
                  .fontSize(fs(this.ts, 13))
                  .backgroundColor($r('app.color.line'))
                  .fontColor(INK)
                  .onClick((): void => {
                    SyncService.get().refreshDevices(true);
                  })
                Button(this.localOn ? '开启跨设备同步' : '切到本机模式')
                  .fontSize(fs(this.ts, 13))
                  .backgroundColor($r('app.color.line'))
                  .fontColor(INK)
                  .onClick((): void => {
                    SyncService.get().setLocalOnly(!this.localOn);
                  })
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(14)
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(12)

          Column({ space: 8 }) {
            Row() {
              Text('备份快照 · 跨设备迁移').fontSize(fs(this.ts, 15)).fontColor(INK)
                .fontWeight(FontWeight.Medium).layoutWeight(1)
              Text('重新扫描').fontSize(fs(this.ts, 12)).fontColor(LOESS)
                .onClick((): void => {
                  this.sync();
                })
            }
            .width('100%')
            ForEach(this.dirs.slice(0, 6), (d: DirStat): void => {
              Row({ space: 8 }) {
                Text(d.readable ? '应用可读' : '应用读不到').fontSize(fs(this.ts, 11))
                  .fontColor(d.readable ? RIVER : CLAY)
                Text(d.dir).fontSize(fs(this.ts, 11)).fontColor(SUB).layoutWeight(1)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(d.count + ' 份').fontSize(fs(this.ts, 11)).fontColor(SUB)
              }
              .width('100%')
            }, (d: DirStat): string => d.dir)
            if (this.snaps.length === 0) {
              Text('这台设备上还没有本机导出的快照。跨设备迁移：另一台设备点「导出快照」，'
                + '电脑上跑 python tools/snap_bridge.py serve，这里直接点「拉取导入」。')
                .fontSize(fs(this.ts, 12)).fontColor(SUB)
            } else {
              ForEach(this.snaps.slice(0, this.snaps.length), (s: SnapshotRow): void => {
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Text(s.name).fontSize(fs(this.ts, 12)).fontColor(INK)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(s.dir + ' · ' + s.size + ' B · ' + (s.at > 0 ? fmtTime(s.at) : '时间未知') +
                      (s.mine ? ' · 本机导过' : ''))
                      .fontSize(fs(this.ts, 11)).fontColor(SUB)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  Text('恢复').fontSize(fs(this.ts, 12)).fontColor(LOESS)
                    .onClick((): void => {
                      this.doRestoreFrom(s.path);
                    })
                }
                .width('100%')
                .padding({ top: 4, bottom: 4 })
              }, (s: SnapshotRow): string => s.path)
            }
            Text('从局域网拉另一台设备的快照（电脑上的服务起来后直接点「拉取导入」）')
              .fontSize(fs(this.ts, 11)).fontColor(SUB)
            Row({ space: 8 }) {
              TextInput({ placeholder: 'http://10.0.2.2:8877/hhmem_latest.json', text: this.snapUrl })
                .height(38)
                .fontSize(fs(this.ts, 12))
                .backgroundColor('#FBF6EC')
                .borderRadius(10)
                .border({ width: 1, color: $r('app.color.line') })
                .layoutWeight(1)
                .onChange((v: string): void => {
                  this.snapUrl = v;
                })
              Button('拉取导入')
                .fontSize(fs(this.ts, 13))
                .backgroundColor(RIVER)
                .onClick((): void => {
                  this.doFetch();
                })
            }
            .width('100%')
            Scroll() {
              Row({ space: 10 }) {
                Button('导出快照')
                  .fontSize(fs(this.ts, 13))
                  .backgroundColor(CLAY)
                  .onClick((): void => {
                    this.doExport();
                  })
                Button('选择文件导入')
                  .fontSize(fs(this.ts, 13))
                  .backgroundColor($r('app.color.line'))
                  .fontColor(INK)
                  .onClick((): void => {
                    this.doPick();
                  })
                if (this.canUndo) {
                  Button('撤销上次恢复')
                    .fontSize(fs(this.ts, 13))
                    .backgroundColor($r('app.color.line'))
                    .fontColor(CLAY)
                    .onClick((): void => {
                      this.doUndo();
                    })
                }
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
            Text('本机账号档案 ' + this.accN + ' 份；快照只带昵称/头像/创建时间，不带口令摘要')
              .fontSize(fs(this.ts, 11)).fontColor(SUB)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(14)
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(12)

          Column({ space: 6 }) {
            Text('可信设备').fontSize(fs(this.ts, 15)).fontColor(INK).fontWeight(FontWeight.Medium)
            if (this.devN === 0) {
              Text('没发现同账号设备。两台真机登录同一账号、开蓝牙和 Wi-Fi 后再刷新。')
                .fontSize(fs(this.ts, 12)).fontColor(SUB)
            } else {
              ForEach(SyncService.get().devices, (d: DeviceRow): void => {
                Row() {
                  Text(d.name).fontSize(fs(this.ts, 14)).fontColor(INK).layoutWeight(1)
                  Text(d.id.substring(0, 8) + '…').fontSize(fs(this.ts, 11)).fontColor(SUB)
                }.width('100%').padding({ top: 6, bottom: 6 })
              }, (d: DeviceRow): string => d.id)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(14)
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(12)

          Column({ space: 6 }) {
            Text('冲突记录（最新时间戳优先）').fontSize(fs(this.ts, 15)).fontColor(INK).fontWeight(FontWeight.Medium)
            if (this.conflictN === 0) {
              Text('还没有发生过冲突。').fontSize(fs(this.ts, 12)).fontColor(SUB)
            } else {
              ForEach(SyncService.get().conflicts, (c: ConflictRow): void => {
                Row() {
                  Text(c.key).fontSize(fs(this.ts, 12)).fontColor(INK).layoutWeight(1)
                  Text(fmtTime(c.at) + ' 保留' + c.kept).fontSize(fs(this.ts, 11)).fontColor(SUB)
                }.width('100%').padding({ top: 4, bottom: 4 })
              }, (c: ConflictRow): string => c.key + c.at)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(14)
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(12)

          if (MemoryStore.get().conflictCopies.length > 0) {
            Column({ space: 6 }) {
              Text('被覆盖的旧笔记（可找回）').fontSize(fs(this.ts, 15)).fontColor(INK).fontWeight(FontWeight.Medium)
              ForEach(MemoryStore.get().conflictCopies, (n: NoteRec): void => {
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Text(SiteRepo.get().byId(n.siteId)?.name ?? '游离笔记')
                      .fontSize(fs(this.ts, 12)).fontColor(CLAY)
                    Text(n.text).fontSize(fs(this.ts, 12)).fontColor(INK)
                      .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  Text('找回为笔记').fontSize(fs(this.ts, 12)).fontColor(LOESS)
                    .onClick(async (): Promise<void> => {
                      await MemoryStore.get().restoreConflict(n.id);
                    })
                }
                .width('100%')
                .padding({ top: 6, bottom: 6 })
              }, (n: NoteRec): string => n.id)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(14)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(12)
          }

          Blank().height(20)
        }
        .padding({ left: 14, right: 14 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  metric(arg: MetricArg) {
    Column({ space: 2 }) {
      Text(arg.value).fontSize(fs(this.ts, 20)).fontColor(INK).fontWeight(FontWeight.Bold)
      Text(arg.title).fontSize(fs(this.ts, 11)).fontColor(SUB)
    }
    .width('100%')
    .padding(8)
    .backgroundColor($r('app.color.page_bg'))
    .borderRadius(8)
  }
}
