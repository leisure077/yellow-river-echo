import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ChatTurn, Citation } from '../model/AiModels';
import { MemoryStore } from './MemoryStore';

export class AiStore {
  private static readonly inst: AiStore = new AiStore();
  static get(): AiStore {
    return AiStore.inst;
  }

  baseUrl: string = '';
  appKey: string = '';
  personalOn: boolean = false;
  conversationId: string = '';
  turns: ChatTurn[] = [];
  
  lastFail: string = '';
  
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
    
    this.turns = this.turns.filter((t: ChatTurn): boolean =>
      !(t.role === 'ai' && t.failed === true));
    for (let t of this.turns) {
      if (t.citations === undefined) {
        t.citations = [];
      }
      
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
