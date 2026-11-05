import { router } from '@kit.ArkUI';
import { MemoryStore } from '../service/MemoryStore';
import { StudioStore } from '../service/StudioStore';
import { SiteRepo } from '../service/SiteRepo';
import { SyncService, DeviceRow, SyncLog } from '../service/SyncService';
import { ERAS, INK, SUB, LOESS, CLAY, RIVER, fmtTime, fs } from '../common/Theme';
import { riverY } from '../common/River';

interface CountArg {
  label: string;
  live: number;
  note: string;
}

interface ParamArg {
  k: string;
  v: string;
}

interface CountRow {
  label: string;
  live: number;
  note: string;
}

interface EraBucket {
  era: string;
  total: number;
  done: number;
}

@Entry
@Component
struct EngineerPage {
  @StorageLink('syncRev') @Watch('reload') syncRev: number = 0;
  @StorageLink('dataRev') @Watch('reload') dataRev: number = 0;
  @StorageLink('studioRev') @Watch('reload') studioRev: number = 0;
  @StorageLink('textScale') ts: number = 1;
  @State state: string = 'off';
  @State hint: string = '';
  @State localOn: boolean = false;
  @State pending: number = 0;
  @State lastAt: number = 0;
  @State logs: SyncLog[] = [];
  @State devs: DeviceRow[] = [];
  @State distRows: CountRow[] = [];
  @State localRows: CountRow[] = [];
  @State buckets: EraBucket[] = [];
  @State queueSample: string = '';
  @State sn: string = '';
  @State clock: number = Date.now();
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ticker: number = -1;

  aboutToAppear(): void {
    this.reload();
    
    this.ticker = setInterval((): void => {
      this.clock = Date.now();
      this.reload();
    }, 2000);
  }

  aboutToDisappear(): void {
    if (this.ticker >= 0) {
      clearInterval(this.ticker);
      this.ticker = -1;
    }
  }

  reload(): void {
    let s = SyncService.get();
    let m = MemoryStore.get();
    let st = StudioStore.get();
    this.state = s.state;
    this.hint = s.hint;
    this.localOn = s.localOnly;
    this.pending = s.pendingCount();
    this.lastAt = s.lastSyncAt;
    this.logs = s.log.slice(0);
    this.devs = s.devices.slice(0);
    this.sn = m.deviceSn;

    let dist: CountRow[] = [];
    dist.push({ label: '收藏 fav', live: m.favsActive().length,
      note: '墓碑 ' + (m.favs.length - m.favsActive().length) + ' 条，按 siteId 归并' });
    dist.push({ label: '标签 tag', live: m.tagsActive().length,
      note: '删标签只解除关联，不删收藏' });
    dist.push({ label: '笔记 note', live: m.notesActive().length,
      note: '五字段齐全：version / deviceId / updatedAt / deleted' });
    dist.push({ label: '进度 prog', live: m.prog.length,
      note: '无墓碑，读过的节数只增不减' });
    dist.push({ label: '主题 topic', live: m.topicsActive().length,
      note: '站点关系存在 siteIds 里' });
    this.distRows = dist;

    let local: CountRow[] = [];
    local.push({ label: '浏览足迹 views', live: m.views.length, note: '只留最近 50 条，本机' });
    local.push({ label: '冲突副本 conflicts', live: m.conflictCopies.length, note: '被时间戳判负的旧笔记，可找回' });
    local.push({ label: 'DIY 作品 works', live: st.works.length, note: '上限 30 件，本机' });
    local.push({ label: '每日签到 checkins', live: st.checkins.length, note: '连签 ' + st.streak() + ' 天' });
    local.push({ label: '现场打卡 siteCheckins', live: st.siteCheckins.length, note: '只存本机，不跨端覆盖' });
    local.push({ label: '自测记录 quizRuns', live: st.quizRuns.length, note: '上限 20 次' });
    local.push({ label: '文创点赞 likes', live: st.likes.length, note: '本机记录' });
    local.push({ label: '心愿单 cart', live: st.cart.length, note: '本机记录' });
    local.push({ label: '集字 chars', live: st.chars.length, note: '工坊收集，本机' });
    this.localRows = local;

    let sample: string[] = [];
    s.dirty.forEach((ts: number, key: string): void => {
      if (sample.length < 5) {
        sample.push(key);
      }
    });
    this.queueSample = sample.join('  ·  ');

    let bs: EraBucket[] = [];
    for (let era of ERAS) {
      let total = 0;
      let done = 0;
      for (let site of SiteRepo.get().sites) {
        if (site.eras.indexOf(era) >= 0) {
          total += 1;
          if (st.checkinOf(site.id) !== undefined) {
            done += 1;
          }
        }
      }
      bs.push({ era: era, total: total, done: done });
    }
    this.buckets = bs;
    this.paint();
  }

  private paint(): void {
    let c = this.ctx;
    let w = c.width;
    let h = c.height;
    if (w <= 0 || h <= 0 || this.buckets.length === 0) {
      return;
    }
    c.clearRect(0, 0, w, h);
    let base = h - 16;
    let span = base - 18;

    let steps = 40;
    c.beginPath();
    for (let k = 0; k <= steps; k++) {
      let u = k / steps;
      let x = u * w;
      let y = 12 + riverY(u) * 14;
      if (k === 0) {
        c.moveTo(x, y);
      } else {
        c.lineTo(x, y);
      }
    }
    c.strokeStyle = 'rgba(74,123,140,0.30)';
    c.lineWidth = 2.2;
    c.stroke();

    let maxT = 1;
    for (let b of this.buckets) {
      if (b.total > maxT) {
        maxT = b.total;
      }
    }
    let slot = w / this.buckets.length;
    let bw = slot * 0.46;
    for (let i = 0; i < this.buckets.length; i++) {
      let b = this.buckets[i];
      let cx = slot * (i + 0.5);
      let ht = (b.total / maxT) * span;
      c.fillStyle = 'rgba(200,161,96,0.30)';
      c.fillRect(cx - bw / 2, base - ht, bw, ht);
      if (b.done > 0) {
        let hd = (b.done / maxT) * span;
        c.fillStyle = 'rgba(166,85,61,0.82)';
        c.fillRect(cx - bw / 2, base - hd, bw, hd);
      }
      c.beginPath();
      c.moveTo(cx - slot * 0.42, base);
      c.lineTo(cx + slot * 0.42, base);
      c.strokeStyle = 'rgba(229,218,198,1)';
      c.lineWidth = 1;
      c.stroke();
    }
  }

  stateText(): string {
    if (this.localOn) {
      return '本机模式（同步暂停）';
    }
    if (this.state === 'ready') {
      return 'ready · 已就绪';
    }
    if (this.state === 'unavailable') {
      return 'unavailable · 分布式服务不可用';
    }
    return 'off · 尚未开始';
  }

  stateColor(): string {
    if (this.localOn) {
      return LOESS;
    }
    return this.state === 'ready' ? RIVER : (this.state === 'unavailable' ? CLAY : SUB);
  }

  tagColor(tag: string): string {
    if (tag === 'error') {
      return CLAY;
    }
    if (tag === 'warn') {
      return LOESS;
    }
    if (tag === 'conflict') {
      return CLAY;
    }
    if (tag === 'ok' || tag === 'remote') {
      return RIVER;
    }
    return SUB;
  }

  checkedTotal(): number {
    return StudioStore.get().siteCheckins.length;
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text('‹ 返回').fontSize(fs(this.ts, 15)).fontColor(CLAY)
          .onClick((): void => {
            router.back();
          })
        Text('河工面板').fontSize(fs(this.ts, 18)).fontColor(INK).fontWeight(FontWeight.Bold).layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10 })

      Scroll() {
        Column({ space: 12 }) {
          
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Circle().width(10).height(10).fill(this.stateColor())
              Text(this.stateText()).fontSize(fs(this.ts, 15)).fontColor(INK).fontWeight(FontWeight.Medium)
              Blank()
              Text('观测 ' + fmtTime(this.clock)).fontSize(fs(this.ts, 10)).fontColor(SUB)
            }
            .width('100%')
            Text(this.hint).fontSize(fs(this.ts, 12)).fontColor(SUB).width('100%')
            Row({ space: 8 }) {
              this.cell({ label: '待同步', live: this.pending, note: 'dirty 队列' })
              this.cell({ label: '冲突', live: SyncService.get().conflicts.length, note: '本次启动' })
              this.cell({ label: '可信设备', live: this.devs.length, note: '本次扫描' })
              this.cell({ label: '现场打卡', live: this.checkedTotal(), note: '本机' })
            }
            .width('100%')
            Text('最后成功同步：' + fmtTime(this.lastAt)).fontSize(fs(this.ts, 11)).fontColor(SUB)
            if (this.queueSample.length > 0) {
              Text('队列样本：' + this.queueSample)
                .fontSize(fs(this.ts, 11)).fontColor(SUB).width('100%')
            }
            Row({ space: 10 }) {
              Button('刷新设备').fontSize(fs(this.ts, 12)).backgroundColor($r('app.color.line')).fontColor(INK)
                .onClick((): void => {
                  SyncService.get().refreshDevices(true);
                })
              Button('立即续传').fontSize(fs(this.ts, 12)).backgroundColor(CLAY).fontColor('#FFFFFF')
                .onClick((): void => {
                  SyncService.get().retry();
                })
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(14)
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(12)

          Column({ space: 6 }) {
            Text('状态机日志 · 本次启动以来').fontSize(fs(this.ts, 15)).fontColor(INK).fontWeight(FontWeight.Medium)
            if (this.logs.length === 0) {
              Text('还没有事件。改一条笔记或点「立即续传」就会留下记录。').fontSize(fs(this.ts, 12)).fontColor(SUB)
            } else {
              ForEach(this.logs, (lg: SyncLog): void => {
                Row({ space: 8 }) {
                  Text(lg.tag).fontSize(fs(this.ts, 10)).fontColor('#FFFFFF')
                    .backgroundColor(this.tagColor(lg.tag))
                    .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                    .borderRadius(6)
                  Text(lg.msg).fontSize(fs(this.ts, 11)).fontColor(INK).layoutWeight(1).maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(fmtTime(lg.at)).fontSize(fs(this.ts, 10)).fontColor(SUB)
                }
                .width('100%')
                .padding({ top: 4, bottom: 4 })
              }, (lg: SyncLog): string => `${lg.at}_${lg.msg}`)
            }
            Text('日志只在内存里，杀掉进程就清空——不写盘是为了不把调试信息带进备份。')
              .fontSize(fs(this.ts, 10)).fontColor(SUB)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(14)
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(12)

          Column({ space: 4 }) {
            Text('进分布式清单的 5 类数据').fontSize(fs(this.ts, 15)).fontColor(INK).fontWeight(FontWeight.Medium)
            Text('键格式 entity:id，值为整条记录的 JSON')
              .fontSize(fs(this.ts, 10)).fontColor(SUB)
            ForEach(this.distRows, (r: CountRow): void => {
              this.row(r)
            }, (r: CountRow): string => r.label)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(14)
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(12)

          Column({ space: 4 }) {
            Text('只存本机的互动数据').fontSize(fs(this.ts, 15)).fontColor(INK).fontWeight(FontWeight.Medium)
            Text('这些刻意不进同步队列：换设备互相覆盖没有意义')
              .fontSize(fs(this.ts, 10)).fontColor(SUB)
            ForEach(this.localRows, (r: CountRow): void => {
              this.row(r)
            }, (r: CountRow): string => r.label)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(14)
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(12)

          Column({ space: 4 }) {
            Text('LWW 参数（照代码原样抄，不是文档口径）').fontSize(fs(this.ts, 15)).fontColor(INK).fontWeight(FontWeight.Medium)
            this.param({ k: 'store_id', v: 'hh_memory_kv' })
            this.param({ k: 'kv_store_type', v: 'SINGLE_VERSION' })
            this.param({ k: 'security_level', v: 'S1' })
            this.param({ k: 'sync_mode', v: 'PUSH_PULL' })
            this.param({ k: 'sync_timeout', v: '3000 ms' })
            this.param({ k: '回执判定', v: '4000 ms 内未抛异常即清队列' })
            this.param({ k: '合并窗口', v: '1500 ms 内多次改动只发一次' })
            this.param({ k: '降级阈值', v: 'kv.put 连续失败 3 次 → 本机模式' })
            this.param({ k: '冲突策略', v: 'updatedAt 新者胜，败方笔记留档' })
            this.param({ k: 'device_sn', v: this.sn })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(14)
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(12)

          Column({ space: 6 }) {
            Text('河道热力图 · 按年代').fontSize(fs(this.ts, 15)).fontColor(INK).fontWeight(FontWeight.Medium)
            Canvas(this.ctx)
              .width('100%')
              .height(150)
              .onReady((): void => {
                this.paint();
              })
            Row({ space: 12 }) {
              ForEach(this.buckets, (b: EraBucket): void => {
                Column({ space: 1 }) {
                  Text(b.era).fontSize(fs(this.ts, 11)).fontColor(INK)
                  Text(`${b.done}/${b.total}`).fontSize(fs(this.ts, 10)).fontColor(b.done > 0 ? CLAY : SUB)
                }
                .layoutWeight(1)
              }, (b: EraBucket): string => b.era)
            }
            .width('100%')
            Text('浅黄＝该年代收录遗址数，赭红＝你在现场打过卡的数量。打卡只存本机，换设备不跟着走。')
              .fontSize(fs(this.ts, 10)).fontColor(SUB)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(14)
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(12)

          Text('彩蛋入口是连点边侧栏头像 5 次。本页所有数字都来自本机 preferences 与内存状态，全程离线。')
            .fontSize(fs(this.ts, 10)).fontColor(SUB)
            .width('100%')
            .padding({ left: 4, right: 4 })

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
  cell(arg: CountArg) {
    Column({ space: 2 }) {
      Text(`${arg.live}`).fontSize(fs(this.ts, 18)).fontColor(INK).fontWeight(FontWeight.Bold)
      Text(arg.label).fontSize(fs(this.ts, 10)).fontColor(SUB)
      Text(arg.note).fontSize(fs(this.ts, 9)).fontColor(SUB).opacity(0.8)
    }
    .layoutWeight(1)
    .padding(8)
    .backgroundColor($r('app.color.page_bg'))
    .borderRadius(8)
  }

  @Builder
  row(r: CountRow) {
    Row({ space: 8 }) {
      Text(r.label).fontSize(fs(this.ts, 13)).fontColor(INK).width(128)
      Text(`${r.live}`).fontSize(fs(this.ts, 13)).fontColor(CLAY).fontWeight(FontWeight.Bold).width(38)
      Text(r.note).fontSize(fs(this.ts, 10)).fontColor(SUB).layoutWeight(1).maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 5, bottom: 5 })
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  param(p: ParamArg) {
    Row({ space: 8 }) {
      Text(p.k).fontSize(fs(this.ts, 12)).fontColor(RIVER).width(108)
      Text(p.v).fontSize(fs(this.ts, 12)).fontColor(INK).layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }
}
