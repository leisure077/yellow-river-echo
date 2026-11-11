import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

// 地图页的资源全在 rawfile 里，Web 的每个子请求都要在 onInterceptRequest 里同步读一遍：
// atlas.png 单张 3.9MB，四季瓦片加起来 9.5MB。读一次卡一次，页面又没有加载态，
// 表现出来就是"点进地图先白一下"。这一层把读过的字节按路径留在内存里，
// 第二次进地图直接命中；首页空闲时再预热核心那几张，第一次进也不卡在白屏上。
const CACHE_MAX: number = 16 * 1024 * 1024;

// 一个地图会话的活跃集：核心那批约 5.5MB（含 3.9MB 底图）+ 当季瓦片约 2.4MB，
// 8MB 上下。16MB 的上限留了一倍余量，不至于把刚读进来的瓦片挤出去来回重读。
const cache: Map<string, ArrayBuffer> = new Map<string, ArrayBuffer>();
let cacheBytes: number = 0;

// 预热清单：地图首帧必须到位的那几个，瓦片不在此列（按需加载，单张几十 KB）
const CORE: string[] = [
  'index.html', 'atlas.css', 'atlas-data.js', 'atlas.js',
  'season-layout.js', 'offline-tiles.js', 'atlas.png'
];

let warmed: boolean = false;

export function mapAssetFromCache(name: string): ArrayBuffer | null {
  let hit = cache.get(name);
  return hit === undefined ? null : hit;
}

export function putMapAsset(name: string, buf: ArrayBuffer): void {
  if (cache.has(name)) {
    return;
  }
  if (cacheBytes + buf.byteLength > CACHE_MAX) {
    cache.clear();
    cacheBytes = 0;
  }
  cache.set(name, buf);
  cacheBytes += buf.byteLength;
}

// 走异步读，别把预热的 4MB 压在首页的滚动帧上。失败就跳过，
// 地图页里还有一次同步读兜底，预热只是让它少白一下。
export function warmMapAssets(ctx: common.UIAbilityContext): void {
  if (warmed) {
    return;
  }
  warmed = true;
  let rm = ctx.resourceManager;
  for (let name of CORE) {
    rm.getRawFileContent('experience/' + name).then((data: Uint8Array): void => {
      putMapAsset(name, data.buffer as ArrayBuffer);
    }).catch((e: BusinessError): void => {
      // 预热读不到就算了，地图页里还有一次同步读兜底；这一层不该把异常冒到 UI 上
      console.warn('map warm ' + name + ': ' + e.message);
    });
  }
}
