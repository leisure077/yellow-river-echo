import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BackupData } from '../model/Models';
import { MemoryStore } from './MemoryStore';
import { SiteRepo } from './SiteRepo';

export class BackupService {
  static async exportSnapshot(ctx: common.Context): Promise<string> {
    let data = MemoryStore.get().exportAll(SiteRepo.get().sites.length);
    let text = JSON.stringify(data);
    let name = 'hhmem_backup_' + Date.now() + '.json';
    let dir = ctx.filesDir + '/backups';
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir);
    }
    BackupService.writeText(dir + '/' + name, text);
    try {
      let docPicker = new picker.DocumentViewPicker();
      let opt: picker.DocumentSaveOptions = { newFileNames: [name], fileSuffixChoices: ['.json'] };
      let uris = await docPicker.save(opt);
      if (uris.length > 0) {
        BackupService.writeText(uris[0], text);
        return '已导出到所选文件';
      }
    } catch (e) {
      console.warn('picker save skipped: ' + JSON.stringify(e));
    }
    return '已存到应用目录 ' + name;
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
    let text = BackupService.readText(uris[0]);
    try {
      let data = JSON.parse(text) as BackupData;
      let ok = await MemoryStore.get().importAll(data);
      return ok ? '恢复成功，变更会同步到其他设备' : '校验和不匹配，文件可能损坏';
    } catch (e) {
      return '文件读不动，已放弃本次恢复';
    }
  }

  private static writeText(path: string, text: string): void {
    let file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, text);
    fs.closeSync(file);
  }

  private static readText(path: string): string {
    let file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    let len = fs.statSync(file.fd).size;
    let buf = new ArrayBuffer(len);
    fs.readSync(file.fd, buf);
    fs.closeSync(file);
    let dec = util.TextDecoder.create('utf-8');
    return dec.decodeToString(new Uint8Array(buf));
  }
}
