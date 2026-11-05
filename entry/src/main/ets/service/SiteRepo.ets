import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { SiteInfo, Suggestion, ViewLog } from '../model/Models';

export class SiteRepo {
  private static readonly inst: SiteRepo = new SiteRepo();
  static get(): SiteRepo {
    return SiteRepo.inst;
  }

  sites: SiteInfo[] = [];
  loaded: boolean = false;
  private idMap: Map<string, SiteInfo> = new Map();

  async load(ctx: common.Context): Promise<void> {
    if (this.loaded) {
      return;
    }
    try {
      let buf = await ctx.resourceManager.getRawFileContent('huanghe_sites.json');
      let dec = util.TextDecoder.create('utf-8');
      let text = dec.decodeToString(buf);
      this.sites = JSON.parse(text) as SiteInfo[];
      for (let s of this.sites) {
        this.idMap.set(s.id, s);
      }
      this.loaded = true;
    } catch (e) {
      console.error('site pack load failed: ' + JSON.stringify(e));
    }
  }

  byId(id: string): SiteInfo | undefined {
    return this.idMap.get(id);
  }

  countByEra(era: string): number {
    let n = 0;
    for (let s of this.sites) {
      if (s.eras.indexOf(era) >= 0) {
        n++;
      }
    }
    return n;
  }

  countByCity(city: string): number {
    let n = 0;
    for (let s of this.sites) {
      if (s.city === city) {
        n++;
      }
    }
    return n;
  }

  query(kw: string, eras: string[], cities: string[], types: string[]): SiteInfo[] {
    let key = kw.trim();
    let out: SiteInfo[] = [];
    for (let s of this.sites) {
      if (key.length > 0 && !this.hit(s, key)) {
        continue;
      }
      if (eras.length > 0 && !SiteRepo.anyMatch(s.eras, eras)) {
        continue;
      }
      if (cities.length > 0 && cities.indexOf(s.city) < 0) {
        continue;
      }
      if (types.length > 0 && !SiteRepo.anyMatch(s.types, types)) {
        continue;
      }
      out.push(s);
    }
    return out;
  }

  private hit(s: SiteInfo, key: string): boolean {
    let hay = s.name + s.alias + s.summary + s.city + s.eras.join('') + s.types.join('');
    return hay.indexOf(key) >= 0;
  }

  private static anyMatch(src: string[], want: string[]): boolean {
    for (let w of want) {
      if (src.indexOf(w) >= 0) {
        return true;
      }
    }
    return false;
  }

  static queryShared(a: string[], b: string[]): boolean {
    return SiteRepo.anyMatch(a, b);
  }

  recommend(favIds: string[], views: ViewLog[], limit: number, excludeId: string): Suggestion[] {
    let base = this.sites.filter((s: SiteInfo): boolean =>
      favIds.indexOf(s.id) < 0 && s.id !== excludeId);
    if (base.length === 0) {
      return [];
    }
    if (favIds.length === 0) {
      
      let picks = ['s01', 's04', 's07', 's15'];
      let out: Suggestion[] = [];
      for (let id of picks) {
        let s = this.idMap.get(id);
        if (s !== undefined) {
          out.push({ site: s, reason: '黄河续响平台·精选入门', score: 0 });
        }
      }
      return out.slice(0, limit);
    }
    let favSites: SiteInfo[] = [];
    for (let id of favIds) {
      let s = this.idMap.get(id);
      if (s !== undefined) {
        favSites.push(s);
      }
    }
    let recentIds: string[] = views.slice(0, 5).map((v: ViewLog): string => v.siteId);
    let scored: Suggestion[] = [];
    for (let s of base) {
      let best = 0;
      let reason = '';
      for (let f of favSites) {
        let sc = 0;
        let why = '';
        if (SiteRepo.anyMatch(s.eras, f.eras)) {
          sc = 0.45;
          why = `与收藏的「${f.name}」同属${s.eras[0]}时期`;
        } else if (SiteRepo.anyMatch(s.types, f.types)) {
          sc = 0.3;
          why = `与收藏的「${f.name}」同为${s.types[0]}`;
        } else if (s.city === f.city) {
          sc = 0.2;
          why = `与收藏的「${f.name}」在同一条河湾（${s.city}）`;
        }
        if (sc > best) {
          best = sc;
          reason = why;
        }
      }
      if (recentIds.indexOf(s.id) >= 0) {
        best += 0.1;
      }
      if (best > 0) {
        scored.push({ site: s, reason: reason, score: best });
      }
    }
    scored.sort((a: Suggestion, b: Suggestion): number => b.score - a.score);
    if (scored.length === 0) {
      return base.slice(0, limit).map((s: SiteInfo): Suggestion =>
        ({ site: s, reason: '沿河其他遗存', score: 0 }));
    }
    return scored.slice(0, limit);
  }

  related(site: SiteInfo, limit: number): Suggestion[] {
    let out: Suggestion[] = [];
    for (let s of this.sites) {
      if (s.id === site.id) {
        continue;
      }
      let reason = '';
      if (SiteRepo.anyMatch(s.eras, site.eras)) {
        reason = `同一时期：${site.eras[0]}`;
      } else if (s.city === site.city) {
        reason = `同城可顺路：${site.city}`;
      } else if (SiteRepo.anyMatch(s.types, site.types)) {
        reason = `同类遗存：${site.types[0]}`;
      }
      if (reason.length > 0) {
        out.push({ site: s, reason: reason, score: 0 });
      }
    }
    return out.slice(0, limit);
  }
}
