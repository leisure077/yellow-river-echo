import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { Profile, AccountRec, AccProfile, WorkRec, CheckinRec, QuizRun, LocalComment, Post, CartLine } from '../model/Models';
import { VerifyGate } from './VerifyGate';
import { SCALE_STEPS, SCALE_DEFAULT } from '../common/Theme';

export class StudioStore {
  private static readonly inst: StudioStore = new StudioStore();
  static get(): StudioStore {
    return StudioStore.inst;
  }

  profile: Profile = { nick: '', avatar: 0, bio: '黄河岸边，一路捡旧物', joinedAt: 0 };
  accounts: AccountRec[] = [];
  likes: string[] = [];
  cart: string[] = [];
  cartLines: CartLine[] = [];
  chars: string[] = [];
  checkins: string[] = [];
  works: WorkRec[] = [];
  readPosts: string[] = [];
  followed: string[] = [];
  postComments: LocalComment[] = [];
  userPosts: Post[] = [];
  guideSeen: boolean = false;
  // 默认就落最大档：现场演示离屏幕有距离，进去第一屏就得读得清
  scaleStep: number = SCALE_DEFAULT;
  siteCheckins: CheckinRec[] = [];
  quizRuns: QuizRun[] = [];
  accOut: ((id: string, payload: string, ts: number) => void) | null = null;

  private p: preferences.Preferences | null = null;

  async init(ctx: common.Context): Promise<void> {
    if (this.p !== null) {
      return;
    }
    this.p = await preferences.getPreferences(ctx, 'hh_studio');
    this.guideSeen = (this.p.getSync('guideSeen', false) as boolean) === true;
    let raw = this.p.getSync('profile', '') as string;
    if (raw.length > 0) {
      try {
        this.profile = JSON.parse(raw) as Profile;
      } catch (e) {
        console.warn('profile broken, reset');
      }
    }
    this.likes = this.readArr('likes');
    this.accounts = this.readArr<AccountRec>('accounts');
    for (let a of this.accounts) {
      a.phone = a.phone ?? '';
      a.updatedAt = a.updatedAt ?? a.createdAt;
      a.adopted = a.adopted ?? false;
    }
    this.cart = this.readArr('cart');
    this.cartLines = this.readArr<CartLine>('cartLines');
    this.chars = this.readArr('chars');
    this.checkins = this.readArr('checkins');
    this.works = this.readArr<WorkRec>('works');
    this.readPosts = this.readArr('readPosts');
    this.followed = this.readArr('followed');
    this.postComments = this.readArr<LocalComment>('postComments');
    this.userPosts = this.readArr<Post>('userPosts');
    this.scaleStep = this.clampStep(this.p.getSync('scaleStep', SCALE_DEFAULT) as number);
    this.siteCheckins = this.readArr<CheckinRec>('siteCheckins');
    this.quizRuns = this.readArr<QuizRun>('quizRuns');
    AppStorage.setOrCreate('textScale', SCALE_STEPS[this.scaleStep]);
  }

  private clampStep(n: number): number {
    let i = Math.floor(n);
    if (i < 0 || i >= SCALE_STEPS.length) {
      return SCALE_DEFAULT;
    }
    return i;
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

  private save(key: string, val: Object): void {
    if (this.p === null) {
      return;
    }
    this.p.put(key, JSON.stringify(val));
    this.scheduleFlush();
    StudioStore.rev();
  }

  private flushTimer: number = -1;

  scheduleFlush(): void {
    if (this.p === null || this.flushTimer >= 0) {
      return;
    }
    this.flushTimer = setTimeout((): void => {
      this.flushTimer = -1;
      this.flushNow();
    }, 900);
  }

  static rev(): void {
    let r = AppStorage.get<number>('studioRev') ?? 0;
    AppStorage.setOrCreate('studioRev', r + 1);
  }

  signedIn(): boolean {
    return this.profile.joinedAt > 0;
  }

  markGuideSeen(): void {
    this.guideSeen = true;
    if (this.p !== null) {
      this.p.put('guideSeen', true);
      this.scheduleFlush();
    }
  }

  redoGuide(): void {
    this.guideSeen = false;
    if (this.p !== null) {
      this.p.put('guideSeen', false);
      this.scheduleFlush();
    }
    StudioStore.rev();
  }

  async signIn(nick: string, avatar: number): Promise<void> {
    this.profile = { nick: nick, avatar: avatar, bio: this.profile.bio, joinedAt: Date.now() };
    this.save('profile', this.profile);
  }

  static digest(nick: string, pwd: string): string {
    let s = nick + '|' + pwd;
    let a = 5381;
    let b = 52711;
    for (let i = 0; i < s.length; i++) {
      let code = s.charCodeAt(i);
      a = (((a << 5) + a) ^ code) >>> 0;
      b = (((b << 7) + b) + code * (i + 7)) >>> 0;
    }
    return a.toString(16) + '-' + b.toString(16);
  }

  accountOf(nick: string): AccountRec | undefined {
    let n = nick.trim();
    return this.accounts.find((x: AccountRec): boolean => x.nick === n);
  }

  hasAccounts(): boolean {
    return this.accounts.length > 0;
  }

  lastAccount(): AccountRec | undefined {
    if (this.accounts.length === 0) {
      return undefined;
    }
    let best = this.accounts[0];
    for (let x of this.accounts) {
      if (x.lastAt > best.lastAt) {
        best = x;
      }
    }
    return best;
  }

  register(nick: string, pwd: string, confirm: string, avatar: number,
    phone: string, code: string): string {
    let n = nick.trim();
    if (n.length < 2) {
      return '昵称至少两个字';
    }
    if (n.length > 12) {
      return '昵称别超过十二个字';
    }
    if (pwd.length < 6 || pwd.length > 16) {
      return '口令要 6-16 位';
    }
    if (pwd !== confirm) {
      return '两次口令对不上';
    }
    if (this.accountOf(n) !== undefined) {
      return `「${n}」在这台设备上注册过了，直接登录`;
    }
    let pErr = VerifyGate.phoneErr(phone);
    if (pErr.length > 0) {
      return pErr;
    }
    let cErr = VerifyGate.get().verify(phone, code);
    if (cErr.length > 0) {
      return cErr;
    }
    let rec: AccountRec = { nick: n, digest: StudioStore.digest(n, pwd), avatar: avatar,
      createdAt: Date.now(), lastAt: Date.now(), phone: VerifyGate.mask(VerifyGate.digits(phone)) };
    this.accounts.push(rec);
    this.save('accounts', this.accounts);
    this.emitAcc(rec);
    this.applySession(rec);
    return '';
  }

  private emitAcc(a: AccountRec): void {
    let p: AccProfile = {
      nick: a.nick, avatar: a.avatar, createdAt: a.createdAt,
      phoneMask: a.phone, updatedAt: a.updatedAt ?? Date.now(), deleted: false
    };
    if (this.accOut !== null) {
      this.accOut(p.nick, JSON.stringify(p), p.updatedAt);
    }
  }

  accountsAsProfiles(): AccProfile[] {
    let out: AccProfile[] = [];
    for (let a of this.accounts) {
      out.push({ nick: a.nick, avatar: a.avatar, createdAt: a.createdAt,
        phoneMask: a.phone, updatedAt: a.updatedAt ?? a.createdAt, deleted: false });
    }
    return out;
  }

  upsertProfile(p: AccProfile, from: string): boolean {
    let name = (p.nick ?? '').trim();
    if (name.length === 0 || name.length > 12) {
      console.warn('skip bad acc profile from ' + from + ' : nick=' + name.length);
      return false;
    }
    let i = this.accounts.findIndex((x: AccountRec): boolean => x.nick === name);
    if (i >= 0) {
      let old = this.accounts[i];
      if ((old.updatedAt ?? old.createdAt) >= p.updatedAt) {
        return false;
      }
      old.avatar = p.avatar;
      old.createdAt = p.createdAt;
      old.phone = p.phoneMask;
      old.updatedAt = p.updatedAt;
      if (old.digest.length === 0) {
        old.adopted = true;
      }
      console.info('acc updated from ' + from + ' : ' + name);
    } else {
      this.accounts.push({ nick: name, digest: '', avatar: p.avatar, createdAt: p.createdAt,
        lastAt: 0, phone: p.phoneMask, updatedAt: p.updatedAt, adopted: true });
      console.info('acc adopted from ' + from + ' : ' + name);
    }
    this.save('accounts', this.accounts);
    let r = AppStorage.get<number>('remoteAccAt') ?? 0;
    AppStorage.setOrCreate('remoteAccAt', r < p.updatedAt ? p.updatedAt : r);
    return true;
  }

  adoptedAccount(): AccountRec | undefined {
    let best: AccountRec | undefined = undefined;
    for (let a of this.accounts) {
      if (a.adopted === true && a.digest.length === 0 && (best === undefined || a.lastAt < best.lastAt)) {
        best = a;
      }
    }
    return best;
  }

  applyRemoteAcc(payload: string): boolean {
    try {
      return this.upsertProfile(JSON.parse(payload) as AccProfile, 'kv');
    } catch (e) {
      console.warn('applyRemoteAcc parse: ' + JSON.stringify(e));
      return false;
    }
  }

  enterWithoutPassword(nick: string): boolean {
    let rec = this.accountOf(nick);
    if (rec === undefined || rec.adopted !== true || rec.digest.length > 0) {
      return false;
    }
    rec.lastAt = Date.now();
    rec.updatedAt = rec.updatedAt ?? rec.createdAt;
    this.save('accounts', this.accounts);
    this.applySession(rec);
    return true;
  }

  restoreProfiles(list: AccProfile[]): number {
    if (list === undefined || list.length === 0) {
      return 0;
    }
    let n = 0;
    for (let p of list) {
      if (this.upsertProfile(p, 'snapshot')) {
        n += 1;
      }
    }
    return n;
  }

  login(nick: string, pwd: string): string {
    let rec = this.accountOf(nick);
    if (rec === undefined) {
      return this.accounts.length === 0 ? '这台设备还没有账号，先注册一个' : `本机没有「${nick.trim()}」这个账号`;
    }
    if (rec.adopted === true && rec.digest.length === 0) {
      rec.lastAt = Date.now();
      this.save('accounts', this.accounts);
      this.applySession(rec);
      return '';
    }
    if (rec.digest !== StudioStore.digest(rec.nick, pwd)) {
      return '口令不对，再想想';
    }
    rec.lastAt = Date.now();
    this.save('accounts', this.accounts);
    this.applySession(rec);
    return '';
  }

  setLocalPassword(nick: string, pwd: string, confirm: string): string {
    let rec = this.accountOf(nick);
    if (rec === undefined) {
      return '本机没有这个账号';
    }
    if (pwd.length < 6 || pwd.length > 16) {
      return '口令要 6-16 位';
    }
    if (pwd !== confirm) {
      return '两次口令对不上';
    }
    rec.digest = StudioStore.digest(rec.nick, pwd);
    rec.adopted = false;
    this.save('accounts', this.accounts);
    return '';
  }

  backupAccountsNow(): void {
    if (this.p === null) {
      return;
    }
    this.p.put('prev_accounts', JSON.stringify(this.accounts));
    this.p.put('prev_acc_at', Date.now());
    this.scheduleFlush();
  }

  undoAccounts(): boolean {
    if (this.p === null) {
      return false;
    }
    let raw = this.p.getSync('prev_accounts', '') as string;
    if (raw.length === 0) {
      return false;
    }
    try {
      this.accounts = JSON.parse(raw) as AccountRec[];
    } catch (e) {
      console.warn('prev_accounts broken: ' + JSON.stringify(e));
      return false;
    }
    this.save('accounts', this.accounts);
    this.p.put('prev_accounts', '');
    this.p.put('prev_acc_at', 0);
    this.scheduleFlush();
    return true;
  }

  prevAccountsAt(): number {
    if (this.p === null) {
      return 0;
    }
    return this.p.getSync('prev_acc_at', 0) as number;
  }

  private applySession(rec: AccountRec): void {
    this.profile = { nick: rec.nick, avatar: rec.avatar, bio: this.profile.bio, joinedAt: Date.now() };
    this.save('profile', this.profile);
  }

  signOut(): void {
    this.profile.joinedAt = 0;
    this.save('profile', this.profile);
  }

  async setBio(bio: string): Promise<void> {
    this.profile.bio = bio;
    this.save('profile', this.profile);
  }

  isLiked(id: string): boolean {
    return this.likes.indexOf(id) >= 0;
  }

  toggleLike(id: string): void {
    let i = this.likes.indexOf(id);
    if (i >= 0) {
      this.likes.splice(i, 1);
    } else {
      this.likes.unshift(id);
    }
    this.save('likes', this.likes);
  }

  inCart(id: string): boolean {
    return this.cart.indexOf(id) >= 0;
  }

  toggleCart(id: string): void {
    let i = this.cart.indexOf(id);
    if (i >= 0) {
      this.cart.splice(i, 1);
      this.cartLines = this.cartLines.filter((l: CartLine): boolean => l.id !== id);
    } else {
      this.cart.push(id);
      this.cartLines.push({ id: id, n: 1 });
    }
    this.save('cart', this.cart);
    this.save('cartLines', this.cartLines);
  }

  qtyOf(id: string): number {
    for (let l of this.cartLines) {
      if (l.id === id) {
        return l.n > 0 ? l.n : 1;
      }
    }
    return 1;
  }

  setQty(id: string, n: number): void {
    if (n <= 0) {
      this.dropCart([id]);
      return;
    }
    if (this.cart.indexOf(id) < 0) {
      this.cart.push(id);
      this.save('cart', this.cart);
    }
    let line = this.cartLines.find((l: CartLine): boolean => l.id === id);
    if (line === undefined) {
      this.cartLines.push({ id: id, n: n });
    } else {
      line.n = n;
    }
    this.save('cartLines', this.cartLines);
  }

  dropCart(ids: string[]): void {
    if (ids.length === 0) {
      return;
    }
    this.cart = this.cart.filter((x: string): boolean => ids.indexOf(x) < 0);
    this.cartLines = this.cartLines.filter((l: CartLine): boolean => ids.indexOf(l.id) < 0);
    this.save('cart', this.cart);
    this.save('cartLines', this.cartLines);
  }

  pruneGoods(alive: string[]): void {
    let lk = this.likes.filter((x: string): boolean => alive.indexOf(x) >= 0);
    let ct = this.cart.filter((x: string): boolean => alive.indexOf(x) >= 0);
    let cl = this.cartLines.filter((l: CartLine): boolean => alive.indexOf(l.id) >= 0);
    if (lk.length === this.likes.length && ct.length === this.cart.length && cl.length === this.cartLines.length) {
      return;
    }
    this.likes = lk;
    this.cart = ct;
    this.cartLines = cl;
    this.save('likes', this.likes);
    this.save('cart', this.cart);
    this.save('cartLines', this.cartLines);
  }

  isFollowed(nick: string): boolean {
    return this.followed.indexOf(nick) >= 0;
  }

  toggleFollow(nick: string): void {
    let i = this.followed.indexOf(nick);
    if (i >= 0) {
      this.followed.splice(i, 1);
    } else {
      this.followed.push(nick);
    }
    this.save('followed', this.followed);
  }

  markPostRead(id: string): void {
    if (this.readPosts.indexOf(id) < 0) {
      this.readPosts.push(id);
      this.save('readPosts', this.readPosts);
    }
  }

  markFeedRead(ids: string[]): void {
    let added = 0;
    for (let id of ids) {
      if (this.readPosts.indexOf(id) < 0) {
        this.readPosts.push(id);
        added++;
      }
    }
    if (added > 0) {
      this.save('readPosts', this.readPosts);
    }
  }

  commentsFor(postId: string): LocalComment[] {
    return this.postComments.filter((c: LocalComment): boolean => c.postId === postId);
  }

  addPostComment(postId: string, text: string): boolean {
    let t = text.trim();
    if (t.length === 0) {
      return false;
    }
    let rec: LocalComment = { id: `lc_${Date.now()}`, postId: postId, text: t, at: Date.now() };
    this.postComments.push(rec);
    this.save('postComments', this.postComments);
    return true;
  }

  publishPost(text: string, topic: string, img: string): boolean {
    let t = text.trim();
    if (t.length === 0) {
      return false;
    }
    let nick = this.profile.nick.length > 0 ? this.profile.nick : '河边来的人';
    let now = Date.now();
    let rec: Post = {
      id: `up_${now}`, author: nick, role: '我自己', kind: '图文',
      img: img, text: t, siteId: '', topic: topic, likes: 0, at: now, comments: []
    };
    this.userPosts.push(rec);
    this.save('userPosts', this.userPosts);
    return true;
  }

  removeUserPost(postId: string): boolean {
    let i = this.userPosts.findIndex((p: Post): boolean => p.id === postId);
    if (i < 0) {
      return false;
    }
    this.userPosts.splice(i, 1);
    this.save('userPosts', this.userPosts);
    let kept = this.postComments.filter((c: LocalComment): boolean => c.postId !== postId);
    if (kept.length !== this.postComments.length) {
      this.postComments = kept;
      this.save('postComments', this.postComments);
    }
    return true;
  }

  isMyPost(postId: string): boolean {
    for (let p of this.userPosts) {
      if (p.id === postId) {
        return true;
      }
    }
    return false;
  }

  unread(total: number): number {
    return total > this.readPosts.length ? total - this.readPosts.length : 0;
  }

  hasChar(c: string): boolean {
    return this.chars.indexOf(c) >= 0;
  }

  addChar(c: string): boolean {
    if (this.chars.indexOf(c) >= 0) {
      return false;
    }
    this.chars.push(c);
    this.save('chars', this.chars);
    return true;
  }

  today(): string {
    let d = new Date();
    let m = d.getMonth() + 1;
    let dd = d.getDate();
    return `${d.getFullYear()}-${m < 10 ? '0' : ''}${m}-${dd < 10 ? '0' : ''}${dd}`;
  }

  checkedToday(): boolean {
    return this.checkins.indexOf(this.today()) >= 0;
  }

  checkin(): boolean {
    let day = this.today();
    if (this.checkins.indexOf(day) >= 0) {
      return false;
    }
    this.checkins.push(day);
    this.save('checkins', this.checkins);
    return true;
  }

  streak(): number {
    let n = 0;
    let cursor = new Date();
    for (let i = 0; i < 60; i++) {
      let m = cursor.getMonth() + 1;
      let dd = cursor.getDate();
      let key = `${cursor.getFullYear()}-${m < 10 ? '0' : ''}${m}-${dd < 10 ? '0' : ''}${dd}`;
      if (this.checkins.indexOf(key) >= 0) {
        n += 1;
      } else if (i > 0 || n > 0) {
        break;
      }
      cursor.setDate(cursor.getDate() - 1);
    }
    return n;
  }

  addWork(w: WorkRec): void {
    this.works.unshift(w);
    if (this.works.length > 30) {
      this.works.pop();
    }
    this.save('works', this.works);
  }

  workOf(id: string): WorkRec | undefined {
    for (let w of this.works) {
      if (w.id === id) {
        return w;
      }
    }
    return undefined;
  }

  dropWork(id: string): void {
    let i = -1;
    for (let k = 0; k < this.works.length; k++) {
      if (this.works[k].id === id) {
        i = k;
        break;
      }
    }
    if (i >= 0) {
      this.works.splice(i, 1);
      this.save('works', this.works);
    }
  }

  setScaleStep(i: number): void {
    this.scaleStep = this.clampStep(i);
    AppStorage.setOrCreate('textScale', SCALE_STEPS[this.scaleStep]);
    if (this.p !== null) {
      this.p.put('scaleStep', this.scaleStep);
      this.scheduleFlush();
    }
    StudioStore.rev();
  }

  checkinOf(siteId: string): CheckinRec | undefined {
    for (let c of this.siteCheckins) {
      if (c.siteId === siteId) {
        return c;
      }
    }
    return undefined;
  }

  siteChecked(siteId: string): boolean {
    return this.checkinOf(siteId) !== undefined;
  }

  checkinSite(siteId: string): boolean {
    if (this.siteChecked(siteId)) {
      return false;
    }
    let rec: CheckinRec = { siteId: siteId, at: Date.now() };
    this.siteCheckins.unshift(rec);
    this.save('siteCheckins', this.siteCheckins);
    return true;
  }

  undoCheckinSite(siteId: string): void {
    this.siteCheckins = this.siteCheckins.filter((c: CheckinRec): boolean => c.siteId !== siteId);
    this.save('siteCheckins', this.siteCheckins);
  }

  checkedSiteIds(): string[] {
    return this.siteCheckins.map((c: CheckinRec): string => c.siteId);
  }

  addQuizRun(persona: string, picks: number[]): void {
    let rec: QuizRun = {
      id: `qz_${Date.now()}`,
      persona: persona,
      at: Date.now(),
      picks: picks
    };
    this.quizRuns.unshift(rec);
    if (this.quizRuns.length > 20) {
      this.quizRuns.pop();
    }
    this.save('quizRuns', this.quizRuns);
  }

  latestQuiz(): QuizRun | undefined {
    return this.quizRuns.length > 0 ? this.quizRuns[0] : undefined;
  }

  flushNow(): void {
    if (this.flushTimer >= 0) {
      clearTimeout(this.flushTimer);
      this.flushTimer = -1;
    }
    if (this.p !== null) {
      this.p.flush().catch((e: Error): void => {
        console.error('studio flush: ' + e.message);
      });
    }
  }
}
