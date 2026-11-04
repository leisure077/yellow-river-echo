import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

/*
 * 转台序列帧的读取与缓存。
 *
 * 帧是烘好的 3D 灰模（rawfile/pottery/turntable/<器型>/<帧号>.webp，5 器型 × 24 帧），
 * 映射表 index.json 由 tools/bake_pottery_frames.mjs 生成，里面记了每种器型的
 * topPx/botPx/maxHalfPx/band —— App 端罩釉色、按弧度贴纹样全靠这几个数，
 * 改了烘帧脚本就得重跑，表和帧不一致的话纹样会贴到器外去。
 *
 * 解码一律走异步 createPixelMap：ImageSource.createPixelMapSync 文档里点名不要在主线程调用，
 * 一帧 512×640 RGBA 解出来 1.3 MB，同步解 24 帧会把滑动直接卡死。
 * 读 rawfile 同理走 getRawFileContent（异步版）：getRawFileContentSync 是把文件读压在 UI 线程上，
 * 命中缓存时看不见，一次 miss 就是一次主线程阻塞 —— 换设备、换存储速度时它就是「隔几笔跳一笔」。
 *
 * 这里要说清实测结论，别把注释当结论写：模拟器 A/B（同一份代码只切预取和缓存上限）
 * 量到自动转台 40 笔、拖动 68 笔全部命中缓存、单笔 paint 平均 1.9ms，
 * 也就是说**这一版的取帧链路不是「卡」的原因**（改动前后的节拍都是 p50≈17ms）。
 * 那还改它做什么：因为同步文件读是文档点名的主线程禁忌，且它只在「这一台设备这一轮」
 * 侥幸没露出来；换成异步 + 整套预取之后，miss 的代价从 UI 线程挪到工作线程，
 * 上限按帧数放大也让一圈 24 帧全部常驻，不再靠运气。
 *
 * 缓存上限按映射表的帧数取（一整套 + 2 帧过渡）：24 帧的循环配 14 帧的 LRU，
 * 只要相邻预取慢一步就会开始淘汰重解；换器型时把上一件那套整批放掉，
 * 峰值内存锁在「一件器物 + 一点余量」。
 */

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
// 兜底下限。真正的上限在 loadIndex 里按映射表的帧数取——一套序列必须全进缓存，
// 见文件头那段「24 帧配 14 帧 LRU 一定崩」。
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
  // 后台整批预取的中止凭据：换器型 / 离页时 +1，正在排的链子发现自己过期就停手
  private preloadToken: number = 0;

  // 读表是同步的：一次 1 KB 出头的 rawfile，比等一个 Promise 再决定画什么好办
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
      // 上限 = 一整套序列 + 2 帧过渡：转台一圈就是 idx.frames 帧，上限低于它就意味着
      // 每一圈都要淘汰并重解若干帧（省下的那点内存，代价是 native 解码重复跑）。
      this.cacheMax = Math.max(CACHE_MIN, idx.frames + 2);
      return idx;
    } catch (e) {
      console.warn('turntable index missing');
      return null;
    }
  }

  // 页面里的器型是中文名（罐/盆/壶/瓶/鼎式），表里的键是拼音，靠 label 对接
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

  // 已在缓存里就直接给，不等 Promise：拖动时每帧都要走这条路
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

  // 只入缓存，不回调：拖动前把左右两帧先解好，手指才不会“等图”
  prefetch(key: string, frame: number): void {
    let k = key + '#' + frame;
    if (this.cache.has(k) || this.loading.has(k)) {
      return;
    }
    this.frame(key, frame).then((): void => {});
  }

  /* 整批预取：从当前帧起一帧解完再排下一帧，让「等图」这件事只可能出现在进页那一瞬，
     不落在拖动和转台的每一笔上。文物工坊那套顺的地方就在这里——不是它转得快
     （它 170ms 一档，比这里还慢），而是它一次 preload 24 张 Image，paint() 只是换 src。
     这里串行而不是 24 个并发：并发会把 native 内存一次性顶到整套的峰值（24×1.31 MB），
     还得排队抢 ImageKit 的工作线程；串行排在空闲里铺，转到的那一帧总是先命中的。 */
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

  // 换器型时把上一件那套帧整批放掉：留着只会挤占新帧的缓存位，白占 31 MB
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
    /* 读文件和解码都挂在异步链上：一帧 13 KB 的 webp，读 + 解出 512×640 RGBA，
       串到 Promise 里让系统去排工作线程。原来的 getRawFileContentSync 是把这次文件读
       压在 UI 线程上——模拟器实测这一版 miss=0（68 笔拖动全命中），所以它没在这台机器上
       露出来，但那是「没 miss」而不是「miss 了也不卡」：同步文件读是文档点名的主线程禁忌。 */
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

  // 离开页面时调用：PixelMap 是 native 内存，只靠 GC 收会一直占着
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
