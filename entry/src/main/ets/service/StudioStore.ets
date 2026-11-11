import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { Profile, AccountRec, WorkRec, CheckinRec, QuizRun, LocalComment, Post, CartLine } from '../model/Models';
import { VerifyGate } from './VerifyGate';
import { SCALE_STEPS, SCALE_DEFAULT } from '../common/Theme';

// 本机互动与创作数据：昵称头像、商品点赞/清单、集字、签到、彩陶作品。
// 刻意不进分布式队列——这些是演示型数据，跨端要同步的仍是档案收藏与笔记。
export class StudioStore {
  private static readonly inst: StudioStore = new StudioStore();
  static get(): StudioStore {
    return StudioStore.inst;
  }

  profile: Profile = { nick: '', avatar: 0, bio: '黄河岸边，一路捡旧物', joinedAt: 0 };
  accounts: AccountRec[] = [];
  likes: string[] = [];
  cart: string[] = [];
  // 清单里每件的数量。cart 仍是「在不在清单」的准，这条只挂数量，
  // 老数据没有这一行的按 1 件算
  cartLines: CartLine[] = [];
  chars: string[] = [];
  checkins: string[] = [];
  works: WorkRec[] = [];
  readPosts: string[] = [];
  followed: string[] = [];
  postComments: LocalComment[] = [];
  // 本机自己发的动态：随包 posts 是只读的，发的东西另存一张表，读的时候再并回去
  userPosts: Post[] = [];
  guideSeen: boolean = false;
  // 默认就落最大档：现场演示离屏幕有距离，进去第一屏就得读得清
  scaleStep: number = SCALE_DEFAULT;
  siteCheckins: CheckinRec[] = [];
  quizRuns: QuizRun[] = [];

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
      // 验证码功能上线之前注册的账号没有 phone，补成空串，别留 undefined
      a.phone = a.phone ?? '';
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

  // flush 慢，攒一批后台落盘，别卡在点击上
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

  // 边侧栏「重看引河」：只清首启标记，收藏笔记作品一律不动
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

  // ---- 本机账号：口令只存摘要，不存明文，也不出这台设备 ----

  // 两段不同初值的散列拼起来，够挡住「翻 preferences 直接看到口令」这一步
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

  // 返回 '' 表示成功，否则是能直接弹给用户的中文原因
  // 验证码放在最后一道：它校验通过就作废，前面任何一条先失败都不会白白烧掉一条码
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
    // 签名不在注册这一步问，进「我的」再改
    this.applySession(rec);
    return '';
  }

  login(nick: string, pwd: string): string {
    let rec = this.accountOf(nick);
    if (rec === undefined) {
      return this.accounts.length === 0 ? '这台设备还没有账号，先注册一个' : `本机没有「${nick.trim()}」这个账号`;
    }
    if (rec.digest !== StudioStore.digest(rec.nick, pwd)) {
      return '口令不对，再想想';
    }
    rec.lastAt = Date.now();
    this.save('accounts', this.accounts);
    this.applySession(rec);
    return '';
  }

  private applySession(rec: AccountRec): void {
    this.profile = { nick: rec.nick, avatar: rec.avatar, bio: this.profile.bio, joinedAt: Date.now() };
    this.save('profile', this.profile);
  }

  // 退出只关掉这次会话：账号、收藏、笔记、作品都原样留在这台设备上，
  // 重新登录（或换个账号）接着用
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

  // 数量减到 0 就是撤出清单，不留下 n=0 的僵尸行
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

  // 商品包换过一批时，本机存的旧 id 已经点不到东西，却还在清单数字里凑数。
  // 启动时拿现在的商品表过一遍，对不上的直接抹掉。
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

  // 首页邮件角标：点进去就把整条动态流一次标完，只落一次盘，不一条条写
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

  // ---- 本机补的评论：随包评论只读，自己回的写这台设备 ----
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

  // ---- 本机发的动态：只存这台设备，读的时候和随包动态按时间并排 ----
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

  // 删本机动态：连带这条底下的本机评论一起清掉，别留孤儿评论
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

  // ---- 字号三档 ----
  setScaleStep(i: number): void {
    this.scaleStep = this.clampStep(i);
    AppStorage.setOrCreate('textScale', SCALE_STEPS[this.scaleStep]);
    if (this.p !== null) {
      this.p.put('scaleStep', this.scaleStep);
      this.scheduleFlush();
    }
    StudioStore.rev();
  }

  // ---- 到遗址现场打卡（本机数据） ----
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

  // ---- 趣味测试记录 ----
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
