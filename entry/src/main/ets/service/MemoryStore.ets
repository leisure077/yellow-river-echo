import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { FavRec, NoteRec, ProgressRec, TagRec, TopicRec, ViewLog, BackupData, AccProfile, PrevImport } from '../model/Models';
import { DEFAULT_TAG_NAMES } from '../common/Theme';

export class MemoryStore {
  private static readonly inst: MemoryStore = new MemoryStore();
  static get(): MemoryStore {
    return MemoryStore.inst;
  }

  onLocalChange: ((entity: string, id: string, payload: string, ts: number) => void) | null = null;

  private p: preferences.Preferences | null = null;
  favs: FavRec[] = [];
  tags: TagRec[] = [];
  notes: NoteRec[] = [];
  prog: ProgressRec[] = [];
  topics: TopicRec[] = [];
  views: ViewLog[] = [];
  conflictCopies: NoteRec[] = [];
  deviceSn: string = '';

  async init(ctx: common.Context): Promise<void> {
    if (this.p !== null) {
      return;
    }
    this.p = await preferences.getPreferences(ctx, 'hh_memory');
    this.favs = this.readArr<FavRec>('favs');
    this.tags = this.readArr<TagRec>('tags');
    this.notes = this.readArr<NoteRec>('notes');
    this.prog = this.readArr<ProgressRec>('prog');
    this.topics = this.readArr<TopicRec>('topics');
    this.views = this.readArr<ViewLog>('views');
    this.conflictCopies = this.readArr<NoteRec>('conflicts');
    this.deviceSn = this.p.getSync('deviceSn', '') as string;
    if (this.deviceSn.length === 0) {
      this.deviceSn = util.generateRandomUUID().substring(0, 8);
      await this.p.put('deviceSn', this.deviceSn);
    }
    if (this.tagsActive().length === 0) {
      for (let name of DEFAULT_TAG_NAMES) {
        let t: TagRec = { id: 'tg_' + Date.now() + '_' + name.length, name: name,
          createdAt: Date.now(), updatedAt: Date.now(), deleted: false };
        this.tags.push(t);
      }
      await this.persist('tags', this.tags);
    }
    if ((this.p.getSync('seeded_mem_v1', 0) as number) === 0) {
      await this.seedDemo();
      await this.p.put('seeded_mem_v1', 1);
    }
    MemoryStore.bumpRev();
  }

  private async seedDemo(): Promise<void> {
    let want = this.tagsActive().find((t: TagRec): boolean => t.name === '待实地探访');
    let been = this.tagsActive().find((t: TagRec): boolean => t.name === '已去过');
    let study = this.tagsActive().find((t: TagRec): boolean => t.name === '研究资料');
    let now = Date.now();
    let f1: FavRec = { siteId: 's01', tagIds: want === undefined ? [] : [want.id],
      createdAt: now - 86400000, updatedAt: now - 86400000, deleted: false };
    let f2: FavRec = { siteId: 's05', tagIds: been === undefined ? [] : [been.id],
      createdAt: now - 43200000, updatedAt: now - 43200000, deleted: false };
    let f3: FavRec = { siteId: 's04', tagIds: study === undefined ? [] : [study.id],
      createdAt: now - 3600000, updatedAt: now - 3600000, deleted: false };
    this.favs.push(f1, f2, f3);
    let n1: NoteRec = { id: 'nt_demo_1', siteId: 's01',
      text: '仰韶村先看窖穴剖面，再对彩陶盆残片，顺序别反。',
      createdAt: now - 86400000, updatedAt: now - 86400000, version: 1,
      deviceId: this.deviceSn, deleted: false, ord: now - 86400000 };
    let n2: NoteRec = { id: 'nt_demo_2', siteId: 's04',
      text: '二里头绿松石龙形器在二层展柜，牌释记得抄编号。',
      createdAt: now - 43200000, updatedAt: now - 43200000, version: 1,
      deviceId: this.deviceSn, deleted: false, ord: now - 43200000 };
    let n3: NoteRec = { id: 'nt_demo_3', siteId: 's02',
      text: '北阳平大房子基址比想象中大，返程留足时间。',
      createdAt: now - 3600000, updatedAt: now - 3600000, version: 1,
      deviceId: this.deviceSn, deleted: false, ord: now - 3600000 };
    this.notes.push(n1, n2, n3);
    await this.persist('favs', this.favs);
    await this.persist('notes', this.notes);
  }

  private readArr<T>(key: string): T[] {
    if (this.p === null) {
      return [];
    }
    let raw = this.p.getSync(key, '[]') as string;
    try {
      return JSON.parse(raw) as T[];
    } catch (e) {
      return [];
    }
  }

  private async persist(key: string, arr: Object[]): Promise<void> {
    if (this.p === null) {
      return;
    }
    let t0 = Date.now();
    await this.p.put(key, JSON.stringify(arr));
    if (Date.now() - t0 > 200) {
      console.warn('hh slow persist ' + key + ' ' + (Date.now() - t0) + 'ms');
    }
    this.scheduleFlush();
  }

  private flushTimer: number = -1;

  private scheduleFlush(): void {
    if (this.flushTimer >= 0 || this.p === null) {
      return;
    }
    this.flushTimer = setTimeout((): void => {
      this.flushTimer = -1;
      this.flushNow();
    }, 600);
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
      console.error('prefs flush: ' + e.message);
    });
  }

  static bumpRev(): void {
    let rev = AppStorage.get<number>('dataRev') ?? 0;
    AppStorage.setOrCreate('dataRev', rev + 1);
  }

  private emit(entity: string, id: string, rec: Object): void {
    let payload = JSON.stringify(rec);
    let r = rec as Record<string, Object>;
    let ts = r.updatedAt as number;
    setTimeout((): void => {
      if (this.onLocalChange !== null) {
        this.onLocalChange(entity, id, payload, ts);
      }
    }, 0);
  }

  favsActive(): FavRec[] {
    return this.favs.filter((f: FavRec): boolean => !f.deleted);
  }

  favOf(siteId: string): FavRec | undefined {
    return this.favsActive().find((f: FavRec): boolean => f.siteId === siteId);
  }

  isFav(siteId: string): boolean {
    return this.favOf(siteId) !== undefined;
  }

  favIds(): string[] {
    return this.favsActive().map((f: FavRec): string => f.siteId);
  }

  async addFav(siteId: string): Promise<void> {
    if (this.isFav(siteId)) {
      return;
    }
    let rec: FavRec = { siteId: siteId, tagIds: [], createdAt: Date.now(), updatedAt: Date.now(), deleted: false };
    this.favs.push(rec);
    await this.persist('favs', this.favs);
    this.emit('fav', siteId, rec);
    MemoryStore.bumpRev();
  }

  async removeFav(siteId: string): Promise<void> {
    let t0 = Date.now();
    let rec = this.favOf(siteId);
    if (rec === undefined) {
      return;
    }
    rec.deleted = true;
    rec.updatedAt = Date.now();
    await this.persist('favs', this.favs);
    this.emit('fav', siteId, rec);
    MemoryStore.bumpRev();
    console.warn('hh perf removeFav total ' + (Date.now() - t0) + 'ms');
  }

  async setFavTags(siteId: string, tagIds: string[]): Promise<void> {
    let rec = this.favOf(siteId);
    if (rec === undefined) {
      await this.addFav(siteId);
      rec = this.favOf(siteId);
    }
    if (rec === undefined) {
      return;
    }
    rec.tagIds = tagIds;
    rec.updatedAt = Date.now();
    await this.persist('favs', this.favs);
    this.emit('fav', siteId, rec);
    MemoryStore.bumpRev();
  }

  tagsActive(): TagRec[] {
    return this.tags.filter((t: TagRec): boolean => !t.deleted);
  }

  tagName(id: string): string {
    let t = this.tagsActive().find((x: TagRec): boolean => x.id === id);
    return t === undefined ? '' : t.name;
  }

  async addTag(name: string): Promise<void> {
    if (name.trim().length === 0) {
      return;
    }
    let rec: TagRec = { id: 'tg_' + Date.now(), name: name.trim(),
      createdAt: Date.now(), updatedAt: Date.now(), deleted: false };
    this.tags.push(rec);
    await this.persist('tags', this.tags);
    this.emit('tag', rec.id, rec);
    MemoryStore.bumpRev();
  }

  async renameTag(id: string, name: string): Promise<void> {
    let rec = this.tags.find((t: TagRec): boolean => t.id === id && !t.deleted);
    if (rec === undefined || name.trim().length === 0) {
      return;
    }
    rec.name = name.trim();
    rec.updatedAt = Date.now();
    await this.persist('tags', this.tags);
    this.emit('tag', id, rec);
    MemoryStore.bumpRev();
  }

  async deleteTag(id: string): Promise<void> {
    let rec = this.tags.find((t: TagRec): boolean => t.id === id && !t.deleted);
    if (rec === undefined) {
      return;
    }
    rec.deleted = true;
    rec.updatedAt = Date.now();
    for (let f of this.favsActive()) {
      let i = f.tagIds.indexOf(id);
      if (i >= 0) {
        f.tagIds.splice(i, 1);
        f.updatedAt = Date.now();
        this.emit('fav', f.siteId, f);
      }
    }
    await this.persist('tags', this.tags);
    await this.persist('favs', this.favs);
    this.emit('tag', id, rec);
    MemoryStore.bumpRev();
  }

  static ordOf(n: NoteRec): number {
    return n.ord !== undefined ? n.ord : n.updatedAt;
  }

  notesActive(): NoteRec[] {
    let out = this.notes.filter((n: NoteRec): boolean => !n.deleted);
    out.sort((a: NoteRec, b: NoteRec): number => MemoryStore.ordOf(b) - MemoryStore.ordOf(a));
    return out;
  }

  notesOfSite(siteId: string): NoteRec[] {
    return this.notesActive().filter((n: NoteRec): boolean => n.siteId === siteId);
  }

  async moveNote(id: string, delta: number): Promise<void> {
    let act = this.notesActive();
    let i = act.findIndex((n: NoteRec): boolean => n.id === id);
    let j = i + delta;
    if (i < 0 || j < 0 || j >= act.length) {
      return;
    }
    let t = act[i];
    act[i] = act[j];
    act[j] = t;
    let base = Date.now() + act.length;
    for (let k = 0; k < act.length; k++) {
      act[k].ord = base - k;
    }
    await this.persist('notes', this.notes);
    this.emit('note', id, act[j]);
    MemoryStore.bumpRev();
  }

  noteOf(id: string): NoteRec | undefined {
    return this.notes.find((n: NoteRec): boolean => n.id === id && !n.deleted);
  }

  async addNote(siteId: string, text: string, srcIds: string[]): Promise<NoteRec | null> {
    let body = text.trim();
    if (body.length === 0) {
      return null;
    }
    let rec: NoteRec = { id: 'nt_' + Date.now() + '_' + this.deviceSn, siteId: siteId, text: body,
      createdAt: Date.now(), updatedAt: Date.now(), version: 1, deviceId: this.deviceSn,
      deleted: false, ord: Date.now() };
    if (srcIds.length > 0) {
      rec.srcIds = srcIds;
    }
    this.notes.push(rec);
    await this.persist('notes', this.notes);
    this.emit('note', rec.id, rec);
    MemoryStore.bumpRev();
    return rec;
  }

  async updateNote(id: string, text: string): Promise<void> {
    let body = text.trim();
    let rec = this.noteOf(id);
    if (rec === undefined || body.length === 0) {
      return;
    }
    rec.text = body;
    rec.updatedAt = Date.now();
    rec.version = rec.version + 1;
    rec.deviceId = this.deviceSn;
    await this.persist('notes', this.notes);
    this.emit('note', id, rec);
    MemoryStore.bumpRev();
  }

  async deleteNote(id: string): Promise<void> {
    let rec = this.noteOf(id);
    if (rec === undefined) {
      return;
    }
    rec.deleted = true;
    rec.updatedAt = Date.now();
    await this.persist('notes', this.notes);
    this.emit('note', id, rec);
    MemoryStore.bumpRev();
  }

  async addConflictCopy(rec: NoteRec): Promise<void> {
    this.conflictCopies.unshift(rec);
    if (this.conflictCopies.length > 30) {
      this.conflictCopies = this.conflictCopies.slice(0, 30);
    }
    await this.persist('conflicts', this.conflictCopies);
  }

  async restoreConflict(id: string): Promise<void> {
    let idx = this.conflictCopies.findIndex((n: NoteRec): boolean => n.id === id);
    if (idx < 0) {
      return;
    }
    let src = this.conflictCopies[idx];
    this.conflictCopies.splice(idx, 1);
    await this.persist('conflicts', this.conflictCopies);
    await this.addNote(src.siteId, src.text, []);
  }

  progressOf(siteId: string): ProgressRec | undefined {
    return this.prog.find((p: ProgressRec): boolean => p.siteId === siteId);
  }

  async bumpSection(siteId: string, section: number): Promise<void> {
    let rec = this.progressOf(siteId);
    if (rec === undefined) {
      rec = { siteId: siteId, maxSection: section, read: false, updatedAt: Date.now() };
      this.prog.push(rec);
    } else if (section > rec.maxSection) {
      rec.maxSection = section;
      rec.updatedAt = Date.now();
    } else {
      return;
    }
    await this.persist('prog', this.prog);
    this.emit('prog', siteId, rec);
  }

  async markRead(siteId: string, read: boolean): Promise<void> {
    let rec = this.progressOf(siteId);
    if (rec === undefined) {
      rec = { siteId: siteId, maxSection: 0, read: read, updatedAt: Date.now() };
      this.prog.push(rec);
    } else {
      rec.read = read;
      rec.updatedAt = Date.now();
    }
    await this.persist('prog', this.prog);
    this.emit('prog', siteId, rec);
    MemoryStore.bumpRev();
  }

  readCount(): number {
    return this.prog.filter((p: ProgressRec): boolean => p.read).length;
  }

  touchView(siteId: string): void {
    this.views = this.views.filter((v: ViewLog): boolean => v.siteId !== siteId);
    this.views.unshift({ siteId: siteId, at: Date.now() });
    if (this.views.length > 50) {
      this.views = this.views.slice(0, 50);
    }
    if (this.p !== null) {
      this.p.put('views', JSON.stringify(this.views));
      this.scheduleFlush();
    }
  }

  async clearViews(): Promise<void> {
    this.views = [];
    await this.persist('views', this.views);
    MemoryStore.bumpRev();
  }

  topicsActive(): TopicRec[] {
    return this.topics.filter((t: TopicRec): boolean => !t.deleted);
  }

  topicOf(id: string): TopicRec | undefined {
    return this.topicsActive().find((t: TopicRec): boolean => t.id === id);
  }

  async addTopic(name: string): Promise<void> {
    if (name.trim().length === 0) {
      return;
    }
    let rec: TopicRec = { id: 'tp_' + Date.now(), name: name.trim(), siteIds: [],
      createdAt: Date.now(), updatedAt: Date.now(), deleted: false };
    this.topics.push(rec);
    await this.persist('topics', this.topics);
    this.emit('topic', rec.id, rec);
    MemoryStore.bumpRev();
  }

  async renameTopic(id: string, name: string): Promise<void> {
    let rec = this.topicOf(id);
    if (rec === undefined || name.trim().length === 0) {
      return;
    }
    rec.name = name.trim();
    rec.updatedAt = Date.now();
    await this.persist('topics', this.topics);
    this.emit('topic', id, rec);
    MemoryStore.bumpRev();
  }

  async deleteTopic(id: string): Promise<void> {
    let rec = this.topicOf(id);
    if (rec === undefined) {
      return;
    }
    rec.deleted = true;
    rec.updatedAt = Date.now();
    await this.persist('topics', this.topics);
    this.emit('topic', id, rec);
    MemoryStore.bumpRev();
  }

  async toggleTopicSite(id: string, siteId: string): Promise<void> {
    let rec = this.topicOf(id);
    if (rec === undefined) {
      return;
    }
    let i = rec.siteIds.indexOf(siteId);
    if (i >= 0) {
      rec.siteIds.splice(i, 1);
    } else {
      rec.siteIds.push(siteId);
    }
    rec.updatedAt = Date.now();
    await this.persist('topics', this.topics);
    this.emit('topic', id, rec);
    MemoryStore.bumpRev();
  }

  async applyRemote(entity: string, payload: string): Promise<void> {
    if (entity === 'fav') {
      this.mergeInto<FavRec>('favs', this.favs, JSON.parse(payload) as FavRec, (x: FavRec): string => x.siteId);
    } else if (entity === 'tag') {
      this.mergeInto<TagRec>('tags', this.tags, JSON.parse(payload) as TagRec, (x: TagRec): string => x.id);
    } else if (entity === 'note') {
      this.mergeInto<NoteRec>('notes', this.notes, JSON.parse(payload) as NoteRec, (x: NoteRec): string => x.id);
    } else if (entity === 'prog') {
      this.mergeInto<ProgressRec>('prog', this.prog, JSON.parse(payload) as ProgressRec,
        (x: ProgressRec): string => x.siteId);
    } else if (entity === 'topic') {
      this.mergeInto<TopicRec>('topics', this.topics, JSON.parse(payload) as TopicRec,
        (x: TopicRec): string => x.id);
    }
    MemoryStore.bumpRev();
  }

  private mergeInto<T>(key: string, arr: T[], rec: T, idOf: (x: T) => string): void {
    let id = idOf(rec);
    let idx = arr.findIndex((x: T): boolean => idOf(x) === id);
    if (idx < 0) {
      arr.push(rec);
    } else {
      let old = arr[idx] as Record<string, Object>;
      let neu = rec as Record<string, Object>;
      if ((neu.updatedAt as number) >= (old.updatedAt as number)) {
        arr[idx] = rec;
      }
    }
    if (this.p !== null) {
      this.p.put(key, JSON.stringify(arr));
      this.scheduleFlush();
    }
  }

  localTs(entity: string, id: string): number {
    if (entity === 'fav') {
      let r = this.favs.find((x: FavRec): boolean => x.siteId === id);
      return r === undefined ? 0 : r.updatedAt;
    }
    if (entity === 'tag') {
      let r = this.tags.find((x: TagRec): boolean => x.id === id);
      return r === undefined ? 0 : r.updatedAt;
    }
    if (entity === 'note') {
      let r = this.notes.find((x: NoteRec): boolean => x.id === id);
      return r === undefined ? 0 : r.updatedAt;
    }
    if (entity === 'prog') {
      let r = this.prog.find((x: ProgressRec): boolean => x.siteId === id);
      return r === undefined ? 0 : r.updatedAt;
    }
    let r = this.topics.find((x: TopicRec): boolean => x.id === id);
    return r === undefined ? 0 : r.updatedAt;
  }

  recordOf(entity: string, id: string): Object | undefined {
    if (entity === 'fav') {
      return this.favs.find((x: FavRec): boolean => x.siteId === id);
    }
    if (entity === 'tag') {
      return this.tags.find((x: TagRec): boolean => x.id === id);
    }
    if (entity === 'note') {
      return this.notes.find((x: NoteRec): boolean => x.id === id);
    }
    if (entity === 'prog') {
      return this.prog.find((x: ProgressRec): boolean => x.siteId === id);
    }
    return this.topics.find((x: TopicRec): boolean => x.id === id);
  }

  setJson(key: string, val: Object): void {
    if (this.p === null) {
      return;
    }
    this.p.put(key, JSON.stringify(val));
    this.scheduleFlush();
  }

  getJson<T>(key: string): T[] {
    return this.readArr<T>(key);
  }

  saveDraft(siteId: string, text: string): void {
    if (this.p !== null) {
      this.p.put('draft_' + siteId, text);
    }
  }

  loadDraft(siteId: string): string {
    if (this.p === null) {
      return '';
    }
    return this.p.getSync('draft_' + siteId, '') as string;
  }

  clearDraft(siteId: string): void {
    if (this.p !== null) {
      this.p.delete('draft_' + siteId);
    }
  }

  exportAll(siteCount: number, accounts: AccProfile[]): BackupData {
    let data: BackupData = {
      formatVer: 2, appVer: '1.0.0', exportedAt: Date.now(), siteCount: siteCount,
      checksum: 0,
      favorites: this.favs, tags: this.tags, notes: this.notes,
      progress: this.prog, topics: this.topics, accounts: accounts
    };
    data.checksum = MemoryStore.fnv(MemoryStore.bodyOf(data));
    return data;
  }

  private static bodyOf(d: BackupData): string {
    let body = JSON.stringify(d.favorites) + JSON.stringify(d.notes) +
      JSON.stringify(d.tags) + JSON.stringify(d.progress) + JSON.stringify(d.topics);
    if (d.formatVer >= 2 && d.accounts !== undefined) {
      body += JSON.stringify(d.accounts);
    }
    return body;
  }

  static fnv(s: string): number {
    let h = 2166136261;
    for (let i = 0; i < s.length; i++) {
      h = Math.imul(h ^ s.charCodeAt(i), 16777619);
    }
    return h >>> 0;
  }

  private prevOf(): PrevImport | null {
    if (this.p === null) {
      return null;
    }
    let raw = this.p.getSync('prev_import_snapshot', '') as string;
    if (raw.length === 0) {
      return null;
    }
    try {
      return JSON.parse(raw) as PrevImport;
    } catch (e) {
      console.warn('prev_import_snapshot broken: ' + JSON.stringify(e));
      return null;
    }
  }

  canUndoImport(): boolean {
    return this.prevOf() !== null;
  }

  undoAt(): number {
    if (this.p === null) {
      return 0;
    }
    return this.p.getSync('prev_import_at', 0) as number;
  }

  undoFrom(): string {
    if (this.p === null) {
      return '';
    }
    return this.p.getSync('prev_import_from', '') as string;
  }

  async undoImport(): Promise<boolean> {
    let prev = this.prevOf();
    if (prev === null || this.p === null) {
      return false;
    }
    this.favs = prev.favs ?? [];
    this.tags = prev.tags ?? [];
    this.notes = prev.notes ?? [];
    this.prog = prev.prog ?? [];
    this.topics = prev.topics ?? [];
    await this.persist('favs', this.favs);
    await this.persist('tags', this.tags);
    await this.persist('notes', this.notes);
    await this.persist('prog', this.prog);
    await this.persist('topics', this.topics);
    await this.p.put('prev_import_snapshot', '');
    await this.p.put('prev_import_at', 0);
    await this.p.put('prev_import_from', '');
    await this.p.flush();
    let now = Date.now();
    console.info('[HH_BACKUP] undo import at ' + now + ' restored ' +
      this.favs.length + ' fav / ' + this.notes.length + ' note / ' + this.topics.length + ' topic');
    MemoryStore.bumpRev();
    return true;
  }

  async importAll(data: BackupData, from: string): Promise<boolean> {
    if (data.formatVer !== 1 && data.formatVer !== 2) {
      console.warn('[HH_BACKUP] reject formatVer=' + data.formatVer + ' from ' + from);
      return false;
    }
    if (MemoryStore.fnv(MemoryStore.bodyOf(data)) !== data.checksum) {
      console.warn('[HH_BACKUP] checksum mismatch from ' + from);
      return false;
    }
    if (this.p !== null) {
      let prev: PrevImport = {
        favs: this.favs, tags: this.tags, notes: this.notes, prog: this.prog, topics: this.topics
      };
      await this.p.put('prev_import_snapshot', JSON.stringify(prev));
      await this.p.put('prev_import_at', Date.now());
      await this.p.put('prev_import_from', from);
      await this.p.flush();
    }
    this.favs = data.favorites;
    this.tags = data.tags;
    this.notes = data.notes;
    this.prog = data.progress;
    this.topics = data.topics;
    await this.persist('favs', this.favs);
    await this.persist('tags', this.tags);
    await this.persist('notes', this.notes);
    await this.persist('prog', this.prog);
    await this.persist('topics', this.topics);
    let now = Date.now();
    for (let f of this.favs) {
      this.emit('fav', f.siteId, f);
    }
    for (let t of this.tags) {
      this.emit('tag', t.id, t);
    }
    for (let n of this.notes) {
      this.emit('note', n.id, n);
    }
    for (let pr of this.prog) {
      this.emit('prog', pr.siteId, pr);
    }
    for (let tp of this.topics) {
      this.emit('topic', tp.id, tp);
    }
    console.info('[HH_BACKUP] import done from ' + from + ' at ' + now);
    MemoryStore.bumpRev();
    return true;
  }
}
