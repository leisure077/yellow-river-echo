import { router } from '@kit.ArkUI';
import { MemoryStore } from '../service/MemoryStore';
import { SyncService, DeviceRow, ConflictRow } from '../service/SyncService';
import { SiteRepo } from '../service/SiteRepo';
import { NoteRec } from '../model/Models';
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

  aboutToAppear(): void {
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
