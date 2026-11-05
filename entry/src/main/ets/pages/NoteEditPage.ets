import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { SiteRepo } from '../service/SiteRepo';
import { MemoryStore } from '../service/MemoryStore';
import { SyncService } from '../service/SyncService';
import { NoteRec } from '../model/Models';
import { fs, INK, SUB, LOESS, CLAY, fmtTime } from '../common/Theme';
import { params } from '../common/Nav';

@Entry
@Component
struct NoteEditPage {
  @StorageLink('textScale') ts: number = 1;
  @StorageLink('dataRev') rev: number = 0;
  @StorageLink('syncRev') syncRev: number = 0;
  @State noteId: string = '';
  @State siteId: string = '';
  @State text: string = '';

  aboutToAppear(): void {
    let p = params();
    if (p.noteId !== undefined && p.noteId!.length > 0) {
      let rec = MemoryStore.get().noteOf(p.noteId!);
      if (rec !== undefined) {
        this.noteId = rec.id;
        this.siteId = rec.siteId;
        this.text = rec.text;
      }
    } else if (p.siteId !== undefined && p.siteId!.length > 0) {
      this.siteId = p.siteId!;
      this.text = MemoryStore.get().loadDraft(this.siteId);
    }
  }

  siteName(): string {
    let s = SiteRepo.get().byId(this.siteId);
    return s === undefined ? '未关联遗址' : s.name;
  }

  cur(): NoteRec | undefined {
    return this.noteId.length > 0 ? MemoryStore.get().noteOf(this.noteId) : undefined;
  }

  syncBadge(): string {
    let s = SyncService.get();
    if (s.state !== 'ready' || s.localOnly) {
      return '仅本机';
    }
    if (this.noteId.length === 0) {
      return '未保存';
    }
    return s.dirty.has('note:' + this.noteId) ? '待同步' : '已同步';
  }

  async save(): Promise<void> {
    let body = this.text.trim();
    if (body.length === 0) {
      promptAction.showToast({ message: '空白笔记就不留了' });
      return;
    }
    if (body.length > 5000) {
      promptAction.showToast({ message: '正文超过 5000 字，先拆成两篇吧' });
      return;
    }
    if (this.noteId.length > 0) {
      await MemoryStore.get().updateNote(this.noteId, body);
    } else {
      await MemoryStore.get().addNote(this.siteId, body, []);
      MemoryStore.get().clearDraft(this.siteId);
    }
    promptAction.showToast({ message: '已存到本机' });
    router.back();
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Text('‹ 返回').fontSize(fs(this.ts, 15)).fontColor(CLAY)
          .onClick((): void => {
            router.back();
          })
        Text(this.noteId.length > 0 ? '编辑笔记' : '记一笔').fontSize(fs(this.ts, 18)).fontColor(INK)
          .fontWeight(FontWeight.Bold).layoutWeight(1)
        Text('删除').fontSize(fs(this.ts, 14)).fontColor(SUB)
          .visibility(this.noteId.length > 0 ? Visibility.Visible : Visibility.Hidden)
          .onClick((): void => {
            AlertDialog.show({
              title: '删除这条笔记？',
              message: '其他设备上的副本会在同步后一并移除',
              primaryButton: {
                value: '删',
                fontColor: CLAY,
                action: async (): Promise<void> => {
                  await MemoryStore.get().deleteNote(this.noteId);
                  router.back();
                }
              },
              secondaryButton: { value: '留着', action: (): void => {} }
            });
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10 })

      Row({ space: 6 }) {
        Text('关联：').fontSize(fs(this.ts, 12)).fontColor(SUB)
        Text(this.siteName()).fontSize(fs(this.ts, 12)).fontColor(CLAY)
        Blank()
        Text(`${this.text.length}/5000`).fontSize(fs(this.ts, 11)).fontColor(this.text.length > 5000 ? CLAY : SUB)
      }
      .width('100%')
      .padding({ left: 14, right: 14 })

      TextArea({ text: this.text, placeholder: '现场看到什么就记什么，先存本机，回头再整理' })
        .height('55%')
        .fontSize(fs(this.ts, 14))
        .lineHeight(fs(this.ts, 24))
        .backgroundColor($r('app.color.card_bg'))
        .margin({ left: 14, right: 14 })
        .onChange((v: string): void => {
          this.text = v;
          if (this.noteId.length === 0 && this.siteId.length > 0) {
            MemoryStore.get().saveDraft(this.siteId, v);
          }
        })

      Row({ space: 10 }) {
        Column({ space: 2 }) {
          if (this.cur() !== undefined) {
            Text('建于 ' + fmtTime(this.cur()!.createdAt)).fontSize(fs(this.ts, 11)).fontColor(SUB)
            Text('改于 ' + fmtTime(this.cur()!.updatedAt) +
              ` · 第 ${this.cur()!.version} 版 · 设备 ${this.cur()!.deviceId}`)
              .fontSize(fs(this.ts, 11)).fontColor(SUB)
          } else {
            Text('新笔记，草稿只留在本机').fontSize(fs(this.ts, 11)).fontColor(SUB)
          }
          Text('同步状态：' + this.syncBadge()).fontSize(fs(this.ts, 11)).fontColor(LOESS)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button('保存')
          .backgroundColor(CLAY)
          .onClick((): void => {
            this.save();
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .alignItems(HorizontalAlign.Start)
  }
}
