import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

export interface ShapeMeta {
  key: string;
  label: string;
  frames: number;
  symmetric: boolean;
  topPx: number;
  botPx: number;
  maxHalfPx: number;
  rimHalfPx: number;
  band: number[];
  ms: number;
}

export interface TurntableIndex {
  frames: number;
  canvas: number[];
  degStep: number;
  ext: string;
  enc: string;
  shapes: Record<string, ShapeMeta>;
  totalBytes: number;
}

const DIR = 'pottery/turntable/';

const CACHE_MIN: number = 14;

export class TurntableFrames {
  private static readonly inst: TurntableFrames = new TurntableFrames();

  static get(): TurntableFrames {
    return TurntableFrames.inst;
  }

  index: TurntableIndex | null = null;
  private cache: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  private order: string[] = [];
  private loading: Map<string, Promise<image.PixelMap | null>> =
    new Map<string, Promise<image.PixelMap | null>>();
  private ctx: common.UIAbilityContext | null = null;
  private cacheMax: number = CACHE_MIN;
  
  private preloadToken: number = 0;

  loadIndex(ctx: common.UIAbilityContext): TurntableIndex | null {
    if (this.index !== null) {
      return this.index;
    }
    try {
      this.ctx = ctx;
      let bytes = ctx.resourceManager.getRawFileContentSync(DIR + 'index.json');
      let dec = util.TextDecoder.create('utf-8');
      let idx = JSON.parse(dec.decodeToString(bytes)) as TurntableIndex;
      if (idx.canvas.length !== 2 || idx.canvas[0] <= 0 || idx.canvas[1] <= 0 || idx.frames <= 0) {
        console.warn('turntable index malformed');
        return null;
      }
      this.index = idx;
      
      this.cacheMax = Math.max(CACHE_MIN, idx.frames + 2);
      return idx;
    } catch (e) {
      console.warn('turntable index missing');
      return null;
    }
  }

  metaOf(label: string): ShapeMeta | null {
    let idx = this.index;
    if (idx === null) {
      return null;
    }
    let keys = Object.keys(idx.shapes);
    for (let i = 0; i < keys.length; i++) {
      let m = idx.shapes[keys[i]];
      if (m !== undefined && m.label === label) {
        return m;
      }
    }
    return null;
  }

  frameCount(m: ShapeMeta): number {
    return m.frames > 0 ? m.frames : 24;
  }

  peek(key: string, frame: number): image.PixelMap | null {
    let k = key + '#' + frame;
    let pm = this.cache.get(k);
    if (pm !== undefined) {
      this.touch(k);
      return pm;
    }
    return null;
  }

  frame(key: string, frame: number): Promise<image.PixelMap | null> {
    let k = key + '#' + frame;
    let hit = this.cache.get(k);
    if (hit !== undefined) {
      this.touch(k);
      return Promise.resolve<image.PixelMap | null>(hit);
    }
    let go = this.loading.get(k);
    if (go !== undefined) {
      return go;
    }
    let task = this.decode(key, frame).then((pm: image.PixelMap | null): image.PixelMap | null => {
      this.loading.delete(k);
      if (pm !== null) {
        this.cache.set(k, pm);
        this.order.push(k);
        this.trim();
      }
      return pm;
    }).catch((): image.PixelMap | null => {
      this.loading.delete(k);
      return null;
    });
    this.loading.set(k, task);
    return task;
  }

  prefetch(key: string, frame: number): void {
    let k = key + '#' + frame;
    if (this.cache.has(k) || this.loading.has(k)) {
      return;
    }
    this.frame(key, frame).then((): void => {});
  }

  preloadFrom(key: string, start: number, count: number): void {
    this.preloadStep(key, start, count, 0, ++this.preloadToken);
  }

  private preloadStep(key: string, start: number, count: number, i: number,
    token: number): void {
    if (i >= count || token !== this.preloadToken) {
      return;
    }
    let f = ((start + i) % count + count) % count;
    this.frame(key, f).then((): void => {
      this.preloadStep(key, start, count, i + 1, token);
    });
  }

  keepOnly(key: string): void {
    let prefix = key + '#';
    let dead: string[] = [];
    for (let k of this.cache.keys()) {
      if (!k.startsWith(prefix)) {
        dead.push(k);
      }
    }
    for (let i = 0; i < dead.length; i++) {
      let k = dead[i];
      let pm = this.cache.get(k);
      if (pm !== undefined) {
        this.cache.delete(k);
        pm.release().then((): void => {});
      }
      let j = this.order.indexOf(k);
      if (j >= 0) {
        this.order.splice(j, 1);
      }
    }
  }

  private decode(key: string, frame: number): Promise<image.PixelMap | null> {
    let ctx = this.ctx;
    let idx = this.index;
    if (ctx === null || idx === null) {
      return Promise.resolve<image.PixelMap | null>(null);
    }
    let path = DIR + key + '/' + frame + '.' + idx.ext;
    
    return ctx.resourceManager.getRawFileContent(path)
      .then((bytes: Uint8Array): Promise<image.PixelMap | null> => {
        let src = image.createImageSource(bytes.buffer as ArrayBuffer);
        return src.createPixelMap().then((pm: image.PixelMap): image.PixelMap | null => {
          src.release().then((): void => {});
          return pm;
        });
      })
      .catch((): image.PixelMap | null => {
        console.warn('frame decode failed: ' + path);
        return null;
      });
  }

  private touch(k: string): void {
    let i = this.order.indexOf(k);
    if (i >= 0) {
      this.order.splice(i, 1);
    }
    this.order.push(k);
  }

  private trim(): void {
    while (this.order.length > this.cacheMax) {
      let oldest = this.order.shift();
      if (oldest === undefined) {
        return;
      }
      let pm = this.cache.get(oldest);
      if (pm !== undefined) {
        this.cache.delete(oldest);
        pm.release().then((): void => {});
      }
    }
  }

  releaseAll(): void {
    this.preloadToken++;
    for (let k of this.cache.keys()) {
      let pm = this.cache.get(k);
      if (pm !== undefined) {
        pm.release().then((): void => {});
      }
    }
    this.cache.clear();
    this.order = [];
    this.loading.clear();
  }
}
