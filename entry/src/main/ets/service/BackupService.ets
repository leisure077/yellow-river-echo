import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { BackupData, SnapshotRow, DirStat } from '../model/Models';
import { MemoryStore } from './MemoryStore';
import { StudioStore } from './StudioStore';
import { SiteRepo } from './SiteRepo';

const SANDBOX_DIR = 'backups';
const INBOX_DIRS: string[] = ['/data/local/tmp/hh_inbox', '/data/local/tmp'];
const MAX_ROW = 40;

export class BackupService {
  static lastUrl: string = '';

  static probeAtBoot(ctx: common.Context): void {
    let rows = BackupService.probeDirs(ctx);
    for (let r of rows) {
      console.info('[HH_BACKUP] probe ' + r.dir + ' readable=' + r.readable + ' snaps=' + r.count);
    }
  }

  static backupDir(ctx: common.Context): string {
    return ctx.filesDir + '/' + SANDBOX_DIR;
  }

  private static ensureDir(dir: string): boolean {
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir);
      }
      return true;
    } catch (e) {
      console.warn('[HH_BACKUP] mkdir ' + dir + ': ' + JSON.stringify(e));
      return false;
    }
  }

  static async exportSnapshot(ctx: common.Context): Promise<string> {
    let st = StudioStore.get();
    let data = MemoryStore.get().exportAll(SiteRepo.get().sites.length, st.accountsAsProfiles());
    let text = JSON.stringify(data);
    if (text.indexOf('"digest"') >= 0) {
      console.error('[HH_BACKUP] export aborted: digest leaked');
      return '导出中止：快照里出现了口令摘要，请把这份文件发给作者';
    }
    let name = 'hhmem_backup_' + Date.now() + '.json';
    let dir = BackupService.backupDir(ctx);
    let where = '';
    if (BackupService.ensureDir(dir)) {
      let path = dir + '/' + name;
      BackupService.writeText(path, text);
      let size = 0;
      try {
        size = fs.statSync(path).size;
      } catch (e) {
        console.warn('[HH_BACKUP] stat ' + path + ': ' + JSON.stringify(e));
      }
      where = path + '（' + size + ' B）';
      console.info('[HH_BACKUP] exported ' + name + ' bytes=' + size + ' notes=' + data.notes.length +
        ' favs=' + data.favorites.length + ' topics=' + data.topics.length +
        ' accs=' + (data.accounts ?? []).length +
        ' checksum=' + data.checksum);
      let rows = BackupService.listSnapshots(ctx);
      MemoryStore.get().setJson('known_snaps', rows.map((r: SnapshotRow): string => r.path));
    }
    try {
      let docPicker = new picker.DocumentViewPicker();
      let opt: picker.DocumentSaveOptions = { newFileNames: [name], fileSuffixChoices: ['.json'] };
      let uris = await docPicker.save(opt);
      if (uris.length > 0) {
        BackupService.writeText(uris[0], text);
        return '已导出到所选文件，应用目录也留了一份';
      }
    } catch (e) {
      console.warn('[HH_BACKUP] picker save skipped: ' + JSON.stringify(e));
    }
    return where.length > 0 ? '已存到 ' + where : '导出没成，应用目录不可写';
  }

  static async restoreSnapshot(ctx: common.Context): Promise<string> {
    let docPicker = new picker.DocumentViewPicker();
    let uris: string[] = [];
    try {
      uris = await docPicker.select();
    } catch (e) {
      return '没拿到文件，已取消';
    }
    if (uris.length === 0) {
      return '没拿到文件，已取消';
    }
    return BackupService.restoreFromPath(ctx, uris[0]);
  }

  static async restoreFromPath(ctx: common.Context, path: string): Promise<string> {
    let text = BackupService.readText(path);
    if (text.length === 0) {
      console.warn('[HH_BACKUP] restore failed: empty or unreadable ' + path);
      return '这个文件应用读不到（权限不够），换局域网导入或走选择文件';
    }
    return BackupService.restoreFromText(text, BackupService.baseName(path));
  }

  static async importFromUrl(ctx: common.Context, url: string): Promise<string> {
    let u = url.trim();
    if (u.indexOf('http://') !== 0 && u.indexOf('https://') !== 0) {
      return '要填 http:// 开头的完整地址，例如 http://10.0.2.2:8899/hhmem_backup_xxx.json';
    }
    let hc = http.createHttp();
    let text = '';
    try {
      const opt: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 8000,
        readTimeout: 15000
      };
      let res = await hc.request(u, opt);
      if (res.responseCode !== 200) {
        console.warn('[HH_BACKUP] http ' + res.responseCode + ' ' + u);
        return '这台设备取不到该地址（HTTP ' + res.responseCode + '）';
      }
      text = typeof res.result === 'string' ? res.result : '';
    } catch (e) {
      console.warn('[HH_BACKUP] http fetch failed ' + u + ': ' + JSON.stringify(e));
      return '取不到这个地址，检查电脑上的服务是否还开着：' + JSON.stringify(e);
    } finally {
      hc.destroy();
    }
    if (text.length === 0) {
      return '取回来是空的，这个地址不是一份快照文件';
    }
    console.info('[HH_BACKUP] fetched ' + u + ' bytes=' + text.length);
    let msg = await BackupService.restoreFromText(text, BackupService.baseName(u.split('?')[0]));
    if (msg.indexOf('恢复成功') === 0) {
      BackupService.lastUrl = u;
    }
    return msg;
  }

  static async restoreFromText(text: string, name: string): Promise<string> {
    let data: BackupData | null = null;
    try {
      data = JSON.parse(text) as BackupData;
    } catch (e) {
      console.warn('[HH_BACKUP] restore failed: not json ' + name);
      return '文件不是这份 App 导出的快照，已放弃';
    }
    if (data === null || data.checksum === undefined) {
      return '文件里没有校验和，不能确定没被改坏';
    }
    let accText = JSON.stringify(data.accounts ?? []);
    if (accText.indexOf('"digest"') >= 0 || accText.indexOf('"pwd"') >= 0) {
      console.error('[HH_BACKUP] import refused: ' + name + ' carries credential fields');
      return '这份快照的账号档案里带口令字段，已拒绝导入（本机数据没动）';
    }
    let st = StudioStore.get();
    st.backupAccountsNow();
    let ok = await MemoryStore.get().importAll(data, name);
    if (!ok) {
      st.undoAccounts();
      return '校验和不匹配，文件可能损坏，本机数据没动';
    }
    let accs = data.accounts ?? [];
    let adopted = st.restoreProfiles(accs);
    console.info('[HH_BACKUP] restored ' + name + ' accounts=' + accs.length + ' adopted=' + adopted);
    return '恢复成功：笔记 ' + data.notes.length + ' 条、收藏 ' + data.favorites.length +
      ' 个、账号档案 ' + adopted + ' 份（可一键撤销）';
  }

  static async undoRestore(ctx: common.Context): Promise<string> {
    let mem = MemoryStore.get();
    if (!mem.canUndoImport()) {
      return '这台设备上没有可撤销的恢复记录';
    }
    let at = mem.undoAt();
    let from = mem.undoFrom();
    let accOk = StudioStore.get().undoAccounts();
    let ok = await mem.undoImport();
    if (!ok) {
      return '撤销没成，本机数据保持现状';
    }
    console.info('[HH_BACKUP] undone restore of ' + from + ' (at ' + at + ', accounts ' + accOk + ')');
    return '已退回恢复前的本机数据（原文件：' + (from.length > 0 ? from : '未知') + '）';
  }

  static probeDirs(ctx: common.Context): DirStat[] {
    let out: DirStat[] = [];
    let cand: string[] = [BackupService.backupDir(ctx)].concat(INBOX_DIRS);
    for (let dir of cand) {
      let n = 0;
      let readable = false;
      try {
        let arr = fs.listFileSync(dir);
        readable = true;
        for (let f of arr) {
          if (f.indexOf('hhmem_backup_') === 0 && f.endsWith('.json')) {
            n += 1;
          }
        }
      } catch (e) {
        readable = false;
      }
      out.push({ dir: dir, readable: readable, count: n });
    }
    return out;
  }

  static listSnapshots(ctx: common.Context): SnapshotRow[] {
    let known: string[] = [];
    try {
      known = MemoryStore.get().getJson<string>('known_snaps');
    } catch (e) {
      known = [];
    }
    let rows: SnapshotRow[] = [];
    let cand: string[] = [BackupService.backupDir(ctx)].concat(INBOX_DIRS);
    for (let dir of cand) {
      let names: string[] = [];
      try {
        names = fs.listFileSync(dir);
      } catch (e) {
        console.warn('[HH_BACKUP] dir unreadable ' + dir + ': ' + JSON.stringify(e));
        continue;
      }
      for (let n of names) {
        if (n.indexOf('hhmem_backup_') !== 0 || !n.endsWith('.json')) {
          continue;
        }
        let p = dir + '/' + n;
        let size = 0;
        let at = 0;
        try {
          let stat = fs.statSync(p);
          size = stat.size;
          at = stat.mtime > 0 ? stat.mtime * 1000 : 0;
        } catch (e) {
          console.warn('[HH_BACKUP] stat ' + p + ': ' + JSON.stringify(e));
        }
        rows.push({ dir: BackupService.dirTag(dir), name: n, path: p, size: size, at: at,
          mine: known.indexOf(p) >= 0 });
      }
    }
    rows.sort((a: SnapshotRow, b: SnapshotRow): number => b.name.localeCompare(a.name));
    return rows.slice(0, MAX_ROW);
  }

  private static dirTag(dir: string): string {
    if (dir.indexOf(SANDBOX_DIR) >= 0) {
      return '本机导出';
    }
    return '外部收件箱';
  }

  static baseName(path: string): string {
    let i = path.lastIndexOf('/');
    return i >= 0 ? path.substring(i + 1) : path;
  }

  private static writeText(path: string, text: string): void {
    let file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, text);
    fs.closeSync(file);
  }

  private static readText(path: string): string {
    try {
      let file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      let len = fs.statSync(file.fd).size;
      let buf = new ArrayBuffer(len);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      let dec = util.TextDecoder.create('utf-8');
      return dec.decodeToString(new Uint8Array(buf));
    } catch (e) {
      console.warn('[HH_BACKUP] readText ' + path + ': ' + JSON.stringify(e));
      return '';
    }
  }
}
