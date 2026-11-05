import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { Goods, Course, EventInfo, Post } from '../model/Models';
import { StudioStore } from './StudioStore';

export class ContentRepo {
  private static readonly inst: ContentRepo = new ContentRepo();
  static get(): ContentRepo {
    return ContentRepo.inst;
  }

  goods: Goods[] = [];
  courses: Course[] = [];
  events: EventInfo[] = [];
  posts: Post[] = [];
  loaded: boolean = false;

  private async read<T>(ctx: common.Context, file: string): Promise<T[]> {
    try {
      let buf = await ctx.resourceManager.getRawFileContent(file);
      let dec = util.TextDecoder.create('utf-8');
      return JSON.parse(dec.decodeToString(buf)) as T[];
    } catch (e) {
      console.warn('pack missing: ' + file);
      return [];
    }
  }

  async load(ctx: common.Context): Promise<void> {
    if (this.loaded) {
      return;
    }
    this.goods = await this.read<Goods>(ctx, 'huanghe_goods.json');
    this.courses = await this.read<Course>(ctx, 'huanghe_courses.json');
    this.events = await this.read<EventInfo>(ctx, 'huanghe_events.json');
    this.posts = await this.read<Post>(ctx, 'huanghe_posts.json');
    this.posts.sort((a: Post, b: Post): number => b.at - a.at);
    this.loaded = true;
  }

  goodOf(id: string): Goods | undefined {
    for (let g of this.goods) {
      if (g.id === id) {
        return g;
      }
    }
    return undefined;
  }

  courseOf(id: string): Course | undefined {
    for (let c of this.courses) {
      if (c.id === id) {
        return c;
      }
    }
    return undefined;
  }

  postOf(id: string): Post | undefined {
    for (let p of this.feed()) {
      if (p.id === id) {
        return p;
      }
    }
    return undefined;
  }

  feed(): Post[] {
    let out = this.posts.slice();
    let mine = StudioStore.get().userPosts;
    for (let p of mine) {
      out.push(p);
    }
    out.sort((a: Post, b: Post): number => b.at - a.at);
    return out;
  }

  eventOf(id: string): EventInfo | undefined {
    for (let e of this.events) {
      if (e.id === id) {
        return e;
      }
    }
    return undefined;
  }

  goodsCats(): string[] {
    let out: string[] = [];
    for (let g of this.goods) {
      if (out.indexOf(g.cat) < 0) {
        out.push(g.cat);
      }
    }
    return out;
  }

  filterGoods(cat: string, kw: string): Goods[] {
    let key = kw.trim();
    return this.goods.filter((g: Goods): boolean => {
      if (cat.length > 0 && cat !== '全部' && g.cat !== cat) {
        return false;
      }
      if (key.length === 0) {
        return true;
      }
      return g.name.indexOf(key) >= 0 || g.sub.indexOf(key) >= 0
        || g.origin.indexOf(key) >= 0 || g.tags.join('').indexOf(key) >= 0;
    });
  }

  hotGoods(limit: number): Goods[] {
    let arr = this.goods.slice();
    arr.sort((a: Goods, b: Goods): number => b.likes - a.likes);
    return arr.slice(0, limit);
  }

  coursesOf(cat: string): Course[] {
    if (cat.length === 0 || cat === '全部') {
      return this.courses;
    }
    return this.courses.filter((c: Course): boolean => c.cat === cat);
  }

  upcomingEvents(limit: number): EventInfo[] {
    let arr = this.events.slice();
    arr.sort((a: EventInfo, b: EventInfo): number => a.date.localeCompare(b.date));
    return arr.slice(0, limit);
  }

  postsOfTopic(topic: string): Post[] {
    if (topic.length === 0) {
      return this.feed();
    }
    return this.feed().filter((p: Post): boolean => p.topic === topic);
  }

  topics(): string[] {
    let out: string[] = [];
    for (let p of this.posts) {
      if (p.topic.length > 0 && out.indexOf(p.topic) < 0) {
        out.push(p.topic);
      }
    }
    return out;
  }
}
