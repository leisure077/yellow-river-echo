import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ChatTurn, Citation } from '../model/AiModels';
import { MemoryStore } from './MemoryStore';

// 助手的本机配置与对话留档。
// App Key 只落在 preferences，不进源码、不进构建产物、也不参与跨端同步。
export class AiStore {
  private static readonly inst: AiStore = new AiStore();
  static get(): AiStore {
    return AiStore.inst;
  }

  // 地址不给默认值：换一台电脑、换一套 Dify，能通的地方的都不一样
  // （本机局域网 IP / 模拟器的 10.0.2.2 / 云端域名），预填一个反而会让人以为不用改。
  baseUrl: string = '';
  appKey: string = '';
  personalOn: boolean = false;
  conversationId: string = '';
  turns: ChatTurn[] = [];
  // 最近一次失败的「状态码 · 耗时 · 一句原因」，只在设置卡片里给排错的人看；
  // 不存 Key、不存问题、不存回答。
  lastFail: string = '';
  // 游客是否已经用过助手：没用过时，首页「问」挂红点、悬浮球挂引导气泡
  askSeen: boolean = false;

  private p: preferences.Preferences | null = null;
  private rev: number = 0;

  async init(ctx: common.Context): Promise<void> {
    if (this.p !== null) {
      return;
    }
    this.p = await preferences.getPreferences(ctx, 'hh_ai');
    this.baseUrl = (this.p.getSync('baseUrl', this.baseUrl) as string).trim();
    this.appKey = (this.p.getSync('appKey', '') as string).trim();
    this.personalOn = (this.p.getSync('personalOn', false) as boolean) === true;
    this.askSeen = (this.p.getSync('askSeen', false) as boolean) === true;
    AppStorage.setOrCreate('assistantSeen', this.askSeen);
    this.conversationId = this.p.getSync('conversationId', '') as string;
    this.lastFail = this.p.getSync('lastFail', '') as string;
    let raw = this.p.getSync('turns', '[]') as string;
    try {
      this.turns = JSON.parse(raw) as ChatTurn[];
    } catch (e) {
      this.turns = [];
    }
    // 旧版本把失败提示也当消息存过；读到就丢掉，只留正常问答
    this.turns = this.turns.filter((t: ChatTurn): boolean =>
      !(t.role === 'ai' && t.failed === true));
    for (let t of this.turns) {
      if (t.citations === undefined) {
        t.citations = [];
      }
      // 旧记录没有这个字段，补成 false，避免界面判断 undefined
      if (t.isAborted === undefined) {
        t.isAborted = false;
      }
      let kept: Citation[] = [];
      for (let c of t.citations) {
        let fixed = this.normalizeCitation(c);
        if (fixed !== undefined) {
          kept.push(fixed);
        }
      }
      t.citations = kept;
    }
  }

  // 老历史里没有 type 字段，按 siteId / 文档名回推分类；
  // 社区动态（posts）和认不出来源的引用一律不保留，界面就不会渲染 Chip
  private normalizeCitation(c: Citation): Citation | undefined {
    let name = (c.name ?? '').trim();
    if (name.endsWith('.md')) {
      name = name.substring(0, name.length - 3);
    }
    let low = name.toLowerCase();
    if (low.indexOf('posts') >= 0 || name.indexOf('社区动态') >= 0) {
      return undefined;
    }
    let siteId = (c.siteId ?? '').trim();
    let type = '';
    if (siteId.length > 0) {
      type = 'site';
    } else if (low.indexOf('goods') >= 0 || name.indexOf('文创') >= 0) {
      type = 'goods';
    } else if (low.indexOf('courses') >= 0 || name.indexOf('课程') >= 0) {
      type = 'courses';
    } else if (low.indexOf('events') >= 0 || name.indexOf('活动') >= 0) {
      type = 'events';
    } else {
      // 遗址号没解析出来的旧引用：既跳不了遗址，也跳不了专题，丢掉
      return undefined;
    }
    if (type !== 'site') {
      let dash = name.indexOf('-');
      if (dash > 0) {
        name = name.substring(dash + 1);
      }
    }
    c.name = name;
    c.siteId = siteId;
    c.type = type;
    return c;
  }

  configured(): boolean {
    return this.appKey.length > 0 && this.baseUrl.length > 0;
  }

  // Dify 的 user 字段只用来分会话，不需要真实身份
  userTag(): string {
    let sn = MemoryStore.get().deviceSn;
    return sn.length > 0 ? 'hh-' + sn : 'hh-guest';
  }

  async saveSettings(base: string, key: string): Promise<void> {
    let b = base.trim();
    this.baseUrl = b.length > 0 ? b : this.baseUrl;
    this.appKey = key.trim();
    await this.persist();
    this.bump();
  }

  async setPersonal(on: boolean): Promise<void> {
    this.personalOn = on;
    await this.persist();
    this.bump();
  }

  // 第一次打开助手卡片就把引导（红点、气泡）收掉，装得再多次也不再打扰
  markAskSeen(): void {
    if (this.askSeen) {
      return;
    }
    this.askSeen = true;
    AppStorage.setOrCreate('assistantSeen', true);
    if (this.p === null) {
      return;
    }
    this.p.put('askSeen', true).then((): void => {
      if (this.p !== null) {
        this.p.flush();
      }
    }).catch((e: Error): void => {
      console.warn('askSeen save: ' + e.message);
    });
  }

  async setConversation(id: string): Promise<void> {
    this.conversationId = id;
    await this.persist();
  }

  // 失败现场先改内存再落盘：设置卡片紧接着就要显示，不能等 flush。
  // note 只放 Dify 给的一句原因（截断），里面不会有 Key。
  markFail(code: number, ms: number, note: string): void {
    let head = code > 0 ? 'HTTP ' + code : '没拿到状态码';
    let tail = note.trim();
    if (tail.length > 60) {
      tail = tail.substring(0, 60) + '…';
    }
    this.lastFail = head + ' · ' + ms + 'ms' + (tail.length > 0 ? ' · ' + tail : '');
    if (this.p === null) {
      return;
    }
    this.p.put('lastFail', this.lastFail).then((): void => {
      if (this.p !== null) {
        this.p.flush();
      }
    }).catch((e: Error): void => {
      console.warn('lastFail save: ' + e.message);
    });
  }

  clearLastFail(): void {
    if (this.lastFail.length === 0) {
      return;
    }
    this.lastFail = '';
    if (this.p === null) {
      return;
    }
    this.p.put('lastFail', '').then((): void => {
      if (this.p !== null) {
        this.p.flush();
      }
    }).catch((e: Error): void => {
      console.warn('lastFail clear: ' + e.message);
    });
  }

  pushTurn(turn: ChatTurn): void {
    this.turns.push(turn);
    if (this.turns.length > 40) {
      this.turns = this.turns.slice(this.turns.length - 40);
    }
    this.saveTurns();
    this.bump();
  }

  async clearChat(): Promise<void> {
    this.turns = [];
    this.conversationId = '';
    await this.persist();
    this.bump();
  }

  private saveTurns(): void {
    if (this.p === null) {
      return;
    }
    this.p.put('turns', JSON.stringify(this.turns)).then((): void => {
      if (this.p !== null) {
        this.p.flush();
      }
    }).catch((e: Error): void => {
      console.warn('ai turns save: ' + e.message);
    });
  }

  private async persist(): Promise<void> {
    if (this.p === null) {
      return;
    }
    await this.p.put('baseUrl', this.baseUrl);
    await this.p.put('appKey', this.appKey);
    await this.p.put('personalOn', this.personalOn);
    await this.p.put('askSeen', this.askSeen);
    await this.p.put('conversationId', this.conversationId);
    await this.p.put('turns', JSON.stringify(this.turns));
    await this.p.flush();
  }

  private bump(): void {
    this.rev++;
    AppStorage.setOrCreate('aiRev', this.rev);
  }
}
