import { distributedKVStore, preferences } from '@kit.ArkData';
import { distributedDeviceManager } from '@kit.DistributedServiceKit';
import { common } from '@kit.AbilityKit';
import { MemoryStore } from './MemoryStore';
import { NoteRec } from '../model/Models';

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

  private kv?: distributedKVStore.SingleKVStore;
  private devMgr?: distributedDeviceManager.DeviceManager;
  private p: preferences.Preferences | null = null;
  private syncing: boolean = false;
  private syncTimer: number = -1;
  private lastDevScan: number = 0;
  private putFailStreak: number = 0;
  private booted: boolean = false;

  private note(tag: string, msg: string): void {
    this.log.unshift({ at: Date.now(), tag: tag, msg: msg });
    if (this.log.length > 40) {
      this.log.pop();
    }
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
      this.state = 'ready';
      this.note('ready', 'KV 存储就绪：hh_memory_kv / SINGLE_VERSION / S1');
      if (this.localOnly) {
        this.hint = '本机模式：数据只写本地，跨设备同步暂停';
        this.note('info', '上次退出时是本机模式，未启动设备扫描');
      } else {
        this.hint = '等待可信设备出现';
        setTimeout((): void => {
          this.refreshDevices();
          if (this.dirty.size > 0) {
            this.note('info', '开机续传：账本里还有 ' + this.dirty.size + ' 条没送出去');
            this.retry();
          }
        }, 1200);
      }
    } catch (e) {
      this.state = 'unavailable';
      this.hint = '本机分布式服务不可用，数据仍保存在本地，恢复后自动续传';
      this.note('error', 'createKVManager / getKVStore 失败：' + JSON.stringify(e));
      console.error('kv init: ' + JSON.stringify(e));
    }
    this.notify();
  }

  private push(entity: string, id: string, payload: string, ts: number): void {
    let key = entity + ':' + id;
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
    try {
      this.kv.sync(ids, distributedKVStore.SyncMode.PUSH_PULL, 3000);
      this.note('state', 'PUSH_PULL 已发出：' + ids.length + ' 台设备 / ' + sent + ' 条变更 / 超时 3000ms');
      setTimeout((): void => {
        this.syncing = false;
        this.dirty.clear();
        this.lastSyncAt = Date.now();
        this.hint = '已向 ' + ids.length + ' 台设备推送 ' + sent + ' 条变更';
        this.note('ok', '4 秒内无异常，队列已清（对端落库以 dataChange 为准）');
        this.persistDirty();
        this.notify();
      }, 4000);
    } catch (e) {
      this.syncing = false;
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
      let payload = raw;
      try {
        let rec = JSON.parse(payload) as Record<string, Object>;
        let remoteTs = rec.updatedAt as number;
        let sep = key.indexOf(':');
        let entity = key.substring(0, sep);
        let id = key.substring(sep + 1);
        let localTs = store.localTs(entity, id);
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
  }

  pendingCount(): number {
    return this.dirty.size;
  }

  private notify(): void {
    let rev = AppStorage.get<number>('syncRev') ?? 0;
    AppStorage.setOrCreate('syncRev', rev + 1);
  }
}
