import { distributedKVStore, preferences } from '@kit.ArkData';
import { distributedDeviceManager } from '@kit.DistributedServiceKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MemoryStore } from './MemoryStore';
import { StudioStore } from './StudioStore';
import { NoteRec, AccProfile } from '../model/Models';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HH_SYNC';

export interface DeviceRow {
  name: string;
  id: string;
}

export interface ConflictRow {
  key: string;
  at: number;
  kept: string;
}

export interface SyncLog {
  at: number;
  tag: string;
  msg: string;
}

// deviceStateChange 回调的载荷形状（SDK 用的是匿名对象类型，这里给个名字好标注）
export interface DeviceStateEvent {
  action: distributedDeviceManager.DeviceStateChange;
  device: distributedDeviceManager.DeviceBasicInfo;
}

export class SyncService {
  private static readonly inst: SyncService = new SyncService();
  static get(): SyncService {
    return SyncService.inst;
  }

  state: string = 'off';
  hint: string = '同步未开始';
  lastSyncAt: number = 0;
  conflicts: ConflictRow[] = [];
  devices: DeviceRow[] = [];
  dirty: Map<string, number> = new Map();
  localOnly: boolean = false;
  log: SyncLog[] = [];
  permGranted: boolean | null = null;

  private kv?: distributedKVStore.SingleKVStore;
  private devMgr?: distributedDeviceManager.DeviceManager;
  private p: preferences.Preferences | null = null;
  private syncing: boolean = false;
  private syncTimer: number = -1;
  private lastDevScan: number = 0;
  private putFailStreak: number = 0;
  private booted: boolean = false;
  private watching: boolean = false;
  private inflightKeys: string[] = [];
  private inflightDevs: string[] = [];
  private ackDevs: string[] = [];
  private ackTimer: number = -1;
  private flushTimer: number = -1;

  private note(tag: string, msg: string): void {
    this.log.unshift({ at: Date.now(), tag: tag, msg: msg });
    if (this.log.length > 40) {
      this.log.pop();
    }
    hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s %{public}s', tag, msg);
  }

  async init(ctx: common.Context, bundleName: string): Promise<void> {
    if (this.booted) {
      return;
    }
    this.booted = true;
    MemoryStore.get().onLocalChange = (entity: string, id: string, payload: string, ts: number): void => {
      this.push(entity, id, payload, ts);
    };
    try {
      this.p = await preferences.getPreferences(ctx, 'hh_sync');
      this.lastSyncAt = this.p.getSync('lastSyncAt', 0) as number;
      this.localOnly = (this.p.getSync('localOnly', false) as boolean) === true;
      let raw = this.p.getSync('dirty', '{}') as string;
      let saved = JSON.parse(raw) as Record<string, number>;
      for (let k of Object.keys(saved)) {
        this.dirty.set(k, saved[k]);
      }
    } catch (e) {
      console.error('sync prefs: ' + JSON.stringify(e));
      this.note('warn', '本机同步账本读不出来，重新开了一份：' + JSON.stringify(e));
    }
    try {
      const cfg: distributedKVStore.KVManagerConfig = {
        context: ctx,
        bundleName: bundleName
      };
      let mgr = distributedKVStore.createKVManager(cfg);
      const opt: distributedKVStore.Options = {
        createIfMissing: true,
        encrypt: false,
        backup: false,
        autoSync: false,
        kvStoreType: distributedKVStore.KVStoreType.SINGLE_VERSION,
        securityLevel: distributedKVStore.SecurityLevel.S1
      };
      this.kv = await mgr.getKVStore<distributedKVStore.SingleKVStore>('hh_memory_kv', opt);
      this.kv.on('dataChange', distributedKVStore.SubscribeType.SUBSCRIBE_TYPE_REMOTE,
        (data: distributedKVStore.ChangeNotification): void => {
          this.onRemote(data.insertEntries.concat(data.updateEntries));
        });
      this.devMgr = distributedDeviceManager.createDeviceManager(bundleName);
      // 账号档案出本机的第二路挂钩：只喂 AccProfile，正文里出现口令类字段会被 push 挡下
      StudioStore.get().accOut = (id: string, payload: string, ts: number): void => {
        this.push('acc', id, payload, ts);
      };
      try {
        this.kv.on('syncComplete', (values: Array<[string, number]>): void => {
          this.onSyncComplete(values);
        });
      } catch (e) {
        this.note('warn', 'syncComplete 订阅失败：' + JSON.stringify(e));
      }
      this.state = 'ready';
      this.note('ready', 'KV 存储就绪：hh_memory_kv / SINGLE_VERSION / S1');
      if (this.localOnly) {
        this.hint = '本机模式：数据只写本地，跨设备同步暂停';
        this.note('info', '上次退出时是本机模式，未启动设备扫描');
      } else {
        this.hint = '等待可信设备出现';
        this.hydrateAccounts();
        setTimeout((): void => {
          this.refreshDevices();
          if (this.dirty.size > 0) {
            this.note('info', '开机续传：账本里还有 ' + this.dirty.size + ' 条没送出去');
            this.retry();
          }
        }, 1200);
      }
      if (this.permGranted !== null) {
        this.afterPerm();
      }
    } catch (e) {
      this.state = 'unavailable';
      this.hint = '本机分布式服务不可用，数据仍保存在本地，恢复后自动续传';
      this.note('error', 'createKVManager / getKVStore 失败：' + JSON.stringify(e));
      console.error('kv init: ' + JSON.stringify(e));
    }
    this.notify();
  }

  // EntryAbility 拿到授权结果后调这里。init 之前调也安全，结果会存着等 init 收尾时补做。
  setPerm(granted: boolean, detail: string): void {
    this.permGranted = granted;
    this.note(granted ? 'ok' : 'warn', '分布式权限：' + (granted ? '已授予' : '未授予') + '（' + detail + '）');
    if (this.booted) {
      this.afterPerm();
    }
  }

  private afterPerm(): void {
    if (this.permGranted !== true) {
      this.hint = '未授予「设备发现和连接」，跨设备同步暂停；本机数据与备份迁移不受影响';
      this.notify();
      return;
    }
    this.watchDevices();
    this.lastDevScan = 0;
    this.refreshDevices(true);
    if (this.dirty.size > 0) {
      this.retry();
    }
  }

  // 设备上线自动续传，不用人再点「立即重试」
  private watchDevices(): void {
    if (this.devMgr === undefined || this.watching) {
      return;
    }
    try {
      this.devMgr.on('deviceStateChange', (info: DeviceStateEvent): void => {
        let up = info.action === distributedDeviceManager.DeviceStateChange.AVAILABLE;
        this.note('device', '设备状态变化：' + (info.device.deviceName ?? '未命名') +
          (up ? ' 可用' : ' 离线') + '（action=' + info.action + '）');
        this.lastDevScan = 0;
        this.refreshDevices(true);
        if (up && this.dirty.size > 0) {
          this.trySync();
        }
      });
      this.watching = true;
      this.note('ok', '已订阅 deviceStateChange，可信设备上线自动续传');
    } catch (e) {
      this.note('warn', 'deviceStateChange 订阅失败：' + JSON.stringify(e));
    }
  }

  // dataChange 只报「将来」的变化。开机先扫一遍本地 KV 里的 acc: 键，
  // 把之前没收到通知的档案补上（KV 同步是整库复制，通道一通这些键就在本机库里）。
  private hydrateAccounts(): void {
    if (this.kv === undefined) {
      return;
    }
    this.kv.getEntries('acc:').then((entries: distributedKVStore.Entry[]): void => {
      let st = StudioStore.get();
      let adopted = 0;
      for (let en of entries) {
        let v = en.value;
        if (typeof v !== 'string') {
          continue;
        }
        if (st.applyRemoteAcc(v)) {
          adopted += 1;
        }
      }
      this.note('info', 'KV 档案回灌：读到 ' + entries.length + ' 条 acc 键，采纳 ' + adopted + ' 条');
    }).catch((err: Error): void => {
      this.note('warn', 'KV 档案回灌失败：' + err.message);
    });
  }

  private onSyncComplete(values: Array<[string, number]>): void {
    let ok = 0;
    let fails: string[] = [];
    for (let v of values) {
      let dev = v[0];
      let code = v[1];
      if (code === 0) {
        ok += 1;
        if (this.ackDevs.indexOf(dev) < 0) {
          this.ackDevs.push(dev);
        }
      } else {
        fails.push(dev.substring(0, 8) + '… code=' + code);
      }
    }
    this.note(ok > 0 ? 'ok' : 'warn', 'syncComplete 回执：' + ok + ' 台成功' +
      (fails.length > 0 ? '，失败 ' + fails.join(' / ') : ''));
    if (fails.length === 0 && ok > 0) {
      this.settleInflight();
    } else if (fails.length > 0) {
      this.hint = '同步回执里有失败码，待同步队列保留，可稍后重试';
    }
    this.notify();
  }

  // 只有拿到成功回执，才把这一批账本销掉（旧写法是 4 秒后无条件清，等于假装送达）
  private settleInflight(): void {
    let cleared = 0;
    for (let k of this.inflightKeys) {
      if (this.dirty.has(k)) {
        this.dirty.delete(k);
        cleared += 1;
      }
    }
    this.lastSyncAt = Date.now();
    this.syncing = false;
    this.hint = '已收到 ' + this.ackDevs.length + ' 台设备的同步回执，销账 ' + cleared + ' 条';
    this.note('ok', '按回执销账 ' + cleared + ' 条（本批发出 ' + this.inflightKeys.length + ' 条）');
    this.inflightKeys = [];
    this.inflightDevs = [];
    this.ackDevs = [];
    if (this.ackTimer >= 0) {
      clearTimeout(this.ackTimer);
      this.ackTimer = -1;
    }
    this.persistDirty();
  }

  private push(entity: string, id: string, payload: string, ts: number): void {
    let key = entity + ':' + id;
    // 口令类字段一律不许上通道。StudioStore 只发 AccProfile，这里是最后一道闸。
    if (payload.indexOf('"digest"') >= 0 || payload.indexOf('"pwd"') >= 0) {
      this.note('error', '拒绝上通道：' + key + ' 的正文里有口令类字段');
      return;
    }
    this.dirty.set(key, ts);
    if (this.localOnly || this.kv === undefined) {
      this.persistDirty();
      this.notify();
      return;
    }
    let t0 = Date.now();
    this.kv.put(key, payload).then((): void => {
      this.putFailStreak = 0;
      this.scheduleSync();
    }).catch((err: Error): void => {
      console.warn('hh perf kv.put fail ' + key + ' ' + (Date.now() - t0) + 'ms ' + err.message);
      this.putFailStreak += 1;
      this.note('warn', 'kv.put 失败 ' + key + '：' + err.message + '（连续 ' + this.putFailStreak + ' 次）');
      if (this.putFailStreak >= 3) {
        this.setLocalOnly(true, '分布式存储多次写入失败，已自动切换为本机模式');
        return;
      }
      this.hint = '写入分布式库失败：' + err.message;
      this.notify();
    });
  }

  setLocalOnly(on: boolean, why: string = ''): void {
    this.localOnly = on;
    this.note('state', on ? '进入本机模式：' + (why.length > 0 ? why : '用户手动切换')
      : '恢复跨设备同步：重新扫描可信设备');
    if (on) {
      if (this.syncTimer >= 0) {
        clearTimeout(this.syncTimer);
        this.syncTimer = -1;
      }
      this.devices = [];
      this.syncing = false;
      this.hint = why.length > 0 ? why : '本机模式：数据只写本地，跨设备同步暂停';
    } else {
      this.putFailStreak = 0;
      this.hint = '等待可信设备出现';
      this.refreshDevices(true);
      if (this.dirty.size > 0) {
        this.trySync();
      }
    }
    if (this.p !== null) {
      this.p.put('localOnly', on);
    }
    this.persistDirty();
    this.notify();
  }

  private scheduleSync(): void {
    if (this.syncTimer >= 0) {
      return;
    }
    this.syncTimer = setTimeout((): void => {
      this.syncTimer = -1;
      this.trySync();
    }, 1500);
  }

  refreshDevices(force: boolean = false): void {
    if (this.devMgr === undefined || this.localOnly) {
      return;
    }
    let now = Date.now();
    if (!force && now - this.lastDevScan < 8000) {
      return;
    }
    this.lastDevScan = now;
    try {
      let list = this.devMgr.getAvailableDeviceListSync();
      this.devices = list.map((d: distributedDeviceManager.DeviceBasicInfo): DeviceRow =>
        ({ name: d.deviceName, id: d.networkId ?? '' }));
      this.note('state', '设备扫描：' + this.devices.length + ' 台同账号可信设备');
      if (this.devices.length === 0 && this.hint.indexOf('不可用') < 0) {
        this.hint = '未发现同账号可信设备，检查蓝牙/Wi-Fi 与登录状态';
      }
    } catch (e) {
      this.devices = [];
      this.note('warn', '设备扫描抛异常：' + JSON.stringify(e));
    }
    this.notify();
  }

  private trySync(): void {
    if (this.localOnly || this.kv === undefined || this.syncing || this.dirty.size === 0) {
      return;
    }
    this.refreshDevices();
    if (this.devices.length === 0) {
      this.persistDirty();
      this.notify();
      return;
    }
    this.syncing = true;
    let ids = this.devices.map((d: DeviceRow): string => d.id).filter((s: string): boolean => s.length > 0);
    let sent = this.dirty.size;
    let ks: string[] = [];
    this.dirty.forEach((ts: number, key: string): void => {
      ks.push(key);
    });
    this.inflightKeys = ks;
    this.inflightDevs = ids.slice(0);
    this.ackDevs = [];
    try {
      this.kv.sync(ids, distributedKVStore.SyncMode.PUSH_PULL, 3000);
      this.note('state', 'PUSH_PULL 已发出：' + ids.length + ' 台设备 / ' + sent + ' 条变更 / 超时 3000ms');
      if (this.ackTimer >= 0) {
        clearTimeout(this.ackTimer);
      }
      // 拿不到回执就把这一批留在账本里，只放开「同步中」的闸门。
      // 旧写法是 4 秒后 dirty.clear()，等于没确认就宣称已经送达。
      this.ackTimer = setTimeout((): void => {
        this.ackTimer = -1;
        if (this.inflightKeys.length === 0) {
          return;
        }
        this.syncing = false;
        this.hint = '8 秒内没收到同步回执，账本保留 ' + this.dirty.size + ' 条，可手动重试';
        this.note('warn', '同步回执超时：本批发出 ' + this.inflightKeys.length +
          ' 条，对端未确认，不销账（目标 ' + this.inflightDevs.length + ' 台）');
        this.inflightKeys = [];
        this.inflightDevs = [];
        this.persistDirty();
        this.notify();
      }, 8000);
    } catch (e) {
      this.syncing = false;
      this.inflightKeys = [];
      this.inflightDevs = [];
      this.hint = '同步通道异常，本地内容不受影响，稍后可手动重试';
      this.note('error', 'kv.sync 抛异常：' + JSON.stringify(e));
      this.persistDirty();
      this.notify();
    }
  }

  retry(): void {
    this.note('info', '手动重试：清扫描节流后重新 PUSH_PULL');
    this.lastDevScan = 0;
    this.refreshDevices(true);
    this.trySync();
  }

  private async onRemote(entries: distributedKVStore.Entry[]): Promise<void> {
    if (this.kv === undefined) {
      return;
    }
    let store = MemoryStore.get();
    for (let en of entries) {
      let key = en.key;
      let raw = en.value;
      if (typeof raw !== 'string') {
        continue;
      }
      let payload: string = raw;
      try {
        let rec = JSON.parse(payload) as Record<string, Object>;
        let remoteTs = rec.updatedAt as number;
        let sep = key.indexOf(':');
        let entity = key.substring(0, sep);
        let id = key.substring(sep + 1);
        let localTs = store.localTs(entity, id);
        // 账号档案不在 MemoryStore 的五类记忆里，走通用分支会被当成未知实体丢掉。
        // 谁新用谁由 StudioStore.upsertProfile 自己判（本机更新就原样不动），这里只负责销账和留痕。
        if (entity === 'acc') {
          if (payload.indexOf('"digest"') >= 0 || payload.indexOf('"pwd"') >= 0) {
            this.note('error', '拒收档案 ' + key + '：正文里出现了口令类字段');
            continue;
          }
          let st = StudioStore.get();
          let cur = st.accountOf(id);
          let curTs = cur === undefined ? 0 : (cur.updatedAt ?? cur.createdAt);
          let adopted = st.applyRemoteAcc(payload);
          this.dirty.delete(key);
          this.note(adopted ? 'remote' : 'conflict', '档案 ' + key + '：本机 ' + curTs +
            (adopted ? ' < 远端 ' + remoteTs + '，已采纳 → 这台设备免密可进' : ' ≥ 远端 ' + remoteTs + '，保留本机版本'));
          continue;
        }
        if (this.dirty.has(key) && localTs > remoteTs) {
          this.conflicts.unshift({ key: key, at: Date.now(), kept: '本机版本' });
          if (this.conflicts.length > 20) {
            this.conflicts.pop();
          }
          this.note('conflict', '冲突 ' + key + '：本机 ' + localTs + ' > 远端 ' + remoteTs + '，保留本机版本');
          if (entity === 'note') {
            await store.addConflictCopy(JSON.parse(payload) as NoteRec);
          }
          let mine = store.recordOf(entity, id);
          if (mine !== undefined) {
            await this.kv.put(key, JSON.stringify(mine));
          }
          this.hint = '发现 ' + this.conflicts.length + ' 条冲突，已按最新时间保留';
        } else {
          this.dirty.delete(key);
          await store.applyRemote(entity, payload);
          this.note('remote', '采纳远端 ' + key + '（本机 ' + localTs + ' ≤ 远端 ' + remoteTs + '）');
        }
      } catch (e) {
        console.error('remote key ' + key + ': ' + JSON.stringify(e));
      }
    }
    this.persistDirty();
    this.notify();
  }

  private persistDirty(): void {
    if (this.p === null) {
      return;
    }
    let obj: Record<string, number> = {};
    this.dirty.forEach((ts: number, key: string): void => {
      obj[key] = ts;
    });
    this.p.put('dirty', JSON.stringify(obj));
    this.p.put('lastSyncAt', this.lastSyncAt);
    this.scheduleFlush();
  }

  // 账本必须真的落到磁盘：进程被杀之后重新开机还能看到「这几条没送出去」，
  // 这就是「最终一致」而不是「尽力而为」的落点。800ms 合并一次，避免每条变更都触发 IO。
  private scheduleFlush(): void {
    if (this.flushTimer >= 0 || this.p === null) {
      return;
    }
    this.flushTimer = setTimeout((): void => {
      this.flushTimer = -1;
      this.flushNow();
    }, 800);
  }

  flushNow(): void {
    if (this.p === null) {
      return;
    }
    if (this.flushTimer >= 0) {
      clearTimeout(this.flushTimer);
      this.flushTimer = -1;
    }
    this.p.flush().catch((e: Error): void => {
      console.error('sync prefs flush: ' + JSON.stringify(e));
    });
  }

  pendingCount(): number {
    return this.dirty.size;
  }

  private notify(): void {
    let rev = AppStorage.get<number>('syncRev') ?? 0;
    AppStorage.setOrCreate('syncRev', rev + 1);
  }
}
