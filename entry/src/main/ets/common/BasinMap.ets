import { util } from '@kit.ArkTS';
import { SiteRepo } from '../service/SiteRepo';
import { StudioStore } from '../service/StudioStore';
import { fs, WATER_FLOW, WATER_OFF } from '../common/Theme';
import { effectiveWaterMode } from '../common/River';


const TAU: number = Math.PI * 2;
const FRAME_MS: number = 40;
const DEG: number = Math.PI / 180;

const LON0: number = 95.6;
const LON1: number = 120.4;
const LAT0: number = 31.9;
const LAT1: number = 42.0;
const COS: number = Math.cos(37.2 * DEG);
const STR: number = 1.35;
const FIT_PAD: number = 12;
const MAX_ZOOM: number = 9;
const SITE_ZOOM: number = 1.55;
const HIT_RIVER: number = 15;
const HIT_SITE: number = 19;
const FLOW_VP: number = 15;

interface Chain {
  name: string;
  pts: number[];
  big: boolean;
}

interface RiverReach {
  order: number;
  pts: number[];
}
interface RiverNetwork {
  main: number[];
  reaches: RiverReach[];
}
interface BasinLabel {
  name: string;
  lon: number;
  lat: number;
  dx: number;
  dy: number;
}
const BASIN_LABELS: BasinLabel[] = [
  { name: '青海源区', lon: 96.34, lat: 34.53, dx: 0, dy: -38 },
  { name: '兰州', lon: 103.83, lat: 36.06, dx: -42, dy: -30 },
  { name: '河套平原', lon: 107.4, lat: 40.7, dx: -20, dy: -40 },
  { name: '壶口瀑布', lon: 110.45, lat: 36.15, dx: 14, dy: -35 },
  { name: '东营入海口', lon: 119.17, lat: 37.77, dx: -65, dy: -38 }
];
interface City {
  name: string;
  lon: number;
  lat: number;
  lv: number;
}

interface Lake {
  name: string;
  lon: number;
  lat: number;
  rx: number;
  ry: number;
  label: boolean;
}

interface Geo {
  id: string;
  lon: number;
  lat: number;
}

interface Drop {
  x: number;
  y: number;
  vx: number;
  vy: number;
  r: number;
  life: number;
  max: number;
  hue: number;
}

interface Halo {
  x: number;
  y: number;
  life: number;
  max: number;
  big: boolean;
}

interface Flash {
  x: number;
  y: number;
  life: number;
  max: number;
}



const TRIB: Chain[] = [
  { name: '渭河', big: true, pts: [104.32, 34.82, 105.1, 34.85, 105.75, 34.62, 106.6, 34.55,
    107.6, 34.36, 108.7, 34.35, 109.6, 34.5, 110.2, 34.56] },
  { name: '泾河', big: true, pts: [106.35, 35.45, 107.0, 35.52, 107.8, 35.2, 108.3, 34.95,
    108.85, 34.62, 109.1, 34.45] },
  { name: '北洛河', big: true, pts: [107.6, 37.3, 108.4, 36.8, 109.0, 36.2, 109.4, 35.6,
    109.65, 35.0, 109.95, 34.8, 110.15, 34.72] },
  { name: '汾河', big: true, pts: [111.95, 38.95, 112.6, 38.4, 112.55, 37.85, 112.3, 37.15,
    111.75, 36.4, 111.35, 35.75, 110.62, 35.42] },
  { name: '沁河', big: true, pts: [112.35, 36.85, 112.7, 36.2, 112.95, 35.5, 112.8, 35.1,
    113.05, 34.92] },
  { name: '无定河', big: true, pts: [107.3, 37.35, 108.3, 37.55, 109.2, 37.85, 110.0, 37.6,
    110.3, 37.15, 110.44, 36.78] },
  { name: '洮河', big: true, pts: [103.05, 34.35, 103.7, 34.85, 103.95, 35.35, 103.6, 35.7,
    103.4, 35.92] },
  { name: '湟水', big: true, pts: [101.0, 36.62, 101.75, 36.65, 102.4, 36.5, 103.0, 36.2,
    103.3, 35.98] },
  { name: '洛河', big: true, pts: [109.9, 34.15, 110.6, 34.05, 111.35, 34.2, 111.9, 34.4,
    112.45, 34.62, 112.72, 34.66, 113.05, 34.84] },
  { name: '延河', big: false, pts: [108.85, 36.75, 109.5, 36.6, 110.0, 36.62, 110.36, 36.6] },
  { name: '窟野河', big: false, pts: [109.6, 39.8, 110.3, 39.5, 110.97, 39.05] },
  { name: '大黑河', big: false, pts: [112.6, 41.05, 111.9, 40.85, 111.45, 40.5, 111.32, 40.24] },
  { name: '浑河', big: false, pts: [113.0, 40.5, 112.4, 40.6, 111.95, 40.82] },
  { name: '清水河', big: false, pts: [106.25, 35.9, 106.1, 36.7, 105.95, 37.4, 105.95, 37.85] },
  { name: '苦水河', big: false, pts: [105.7, 36.5, 105.5, 36.95, 105.25, 37.28] },
  { name: '祖厉河', big: false, pts: [104.5, 35.65, 104.85, 36.15, 104.4, 36.58] },
  { name: '葫芦河', big: false, pts: [105.85, 35.15, 106.5, 35.3, 107.0, 35.35, 107.4, 35.4] },
  { name: '环江', big: false, pts: [107.35, 36.6, 107.6, 36.0, 107.5, 35.45] },
  { name: '伊河', big: false, pts: [111.65, 34.05, 112.15, 34.35, 112.45, 34.58, 112.72, 34.66] },
  { name: '涑水河', big: false, pts: [111.6, 35.1, 111.0, 35.02, 110.66, 34.62] },
  { name: '大汶河', big: false, pts: [118.0, 36.2, 117.3, 36.15, 116.7, 36.0, 116.35, 35.88] },
  { name: '黑河', big: false, pts: [102.75, 34.0, 102.6, 33.6, 102.48, 33.42] },
  { name: '白河', big: false, pts: [101.9, 33.7, 102.25, 33.5, 102.45, 33.4] }
];

const LAKES: Lake[] = [
  { name: '扎陵湖', lon: 97.15, lat: 34.93, rx: 0.42, ry: 0.16, label: false },
  { name: '鄂陵湖', lon: 97.85, lat: 34.86, rx: 0.44, ry: 0.2, label: false },
  { name: '乌梁素海', lon: 108.42, lat: 40.88, rx: 0.3, ry: 0.22, label: true },
  { name: '东平湖', lon: 116.18, lat: 35.93, rx: 0.3, ry: 0.24, label: false }
];

const CITIES: City[] = [
  { name: '兰州', lon: 103.83, lat: 36.06, lv: 1 },
  { name: '洛阳', lon: 112.45, lat: 34.62, lv: 1 },
  { name: '郑州', lon: 113.63, lat: 34.75, lv: 1 },
  { name: '济南', lon: 117.0, lat: 36.65, lv: 1 },
  { name: '西宁', lon: 101.78, lat: 36.62, lv: 2 },
  { name: '银川', lon: 106.28, lat: 38.47, lv: 2 },
  { name: '呼和浩特', lon: 111.75, lat: 40.84, lv: 2 },
  { name: '包头', lon: 109.84, lat: 40.66, lv: 2 },
  { name: '西安', lon: 108.94, lat: 34.34, lv: 2 },
  { name: '太原', lon: 112.55, lat: 37.87, lv: 2 },
  { name: '开封', lon: 114.35, lat: 34.79, lv: 2 },
  { name: '东营', lon: 118.55, lat: 37.45, lv: 2 },
  { name: '乌海', lon: 106.8, lat: 39.67, lv: 3 },
  { name: '石嘴山', lon: 106.37, lat: 39.01, lv: 3 },
  { name: '中卫', lon: 105.19, lat: 37.51, lv: 3 },
  { name: '吴忠', lon: 106.1, lat: 37.8, lv: 3 },
  { name: '天水', lon: 105.72, lat: 34.58, lv: 3 },
  { name: '宝鸡', lon: 107.18, lat: 34.36, lv: 3 },
  { name: '延安', lon: 109.5, lat: 36.6, lv: 3 },
  { name: '临汾', lon: 111.52, lat: 36.09, lv: 3 },
  { name: '运城', lon: 111.01, lat: 35.03, lv: 3 },
  { name: '三门峡', lon: 111.2, lat: 34.77, lv: 3 },
  { name: '濮阳', lon: 115.03, lat: 35.76, lv: 3 },
  { name: '菏泽', lon: 115.47, lat: 35.26, lv: 3 }
];

const SITE_GEO: Geo[] = [
  { id: 's01', lon: 111.75, lat: 34.78 },
  { id: 's02', lon: 110.9, lat: 34.46 },
  { id: 's03', lon: 111.2, lat: 34.77 },
  { id: 's04', lon: 112.68, lat: 34.6 },
  { id: 's05', lon: 112.72, lat: 34.72 },
  { id: 's06', lon: 112.45, lat: 34.67 },
  { id: 's07', lon: 112.62, lat: 34.68 },
  { id: 's08', lon: 112.47, lat: 34.47 },
  { id: 's09', lon: 113.06, lat: 34.36 },
  { id: 's10', lon: 113.66, lat: 34.75 },
  { id: 's11', lon: 113.0, lat: 34.75 },
  { id: 's12', lon: 113.0, lat: 34.46 },
  { id: 's13', lon: 113.55, lat: 34.92 },
  { id: 's14', lon: 114.35, lat: 34.78 },
  { id: 's15', lon: 114.31, lat: 34.76 },
  { id: 's16', lon: 114.38, lat: 34.81 },
  { id: 's17', lon: 114.31, lat: 34.8 },
  { id: 's18', lon: 115.03, lat: 35.72 },
  { id: 's19', lon: 115.0, lat: 35.76 },
  { id: 's20', lon: 115.18, lat: 35.74 }
];

interface ViewPreset {
  key: string;
  label: string;
  lon: number;
  lat: number;
  zoom: number;
}

const PRESETS: ViewPreset[] = [
  { key: 'all', label: '全流域', lon: 108.0, lat: 37.4, zoom: 1 },
  { key: 'hetou', label: '几字弯', lon: 108.6, lat: 39.4, zoom: 2.3 },
  { key: 'jinsaan', label: '晋陕峡谷', lon: 110.6, lat: 37.6, zoom: 2.6 },
  { key: 'henan', label: '河南流域', lon: 112.9, lat: 34.85, zoom: 3.6 }
];

function geoOf(id: string): Geo | undefined {
  for (let g of SITE_GEO) {
    if (g.id === id) {
      return g;
    }
  }
  return undefined;
}

@Component
export struct BasinMap {
  @StorageLink('textScale') ts: number = 1;
  @Prop activeId: string = '';
  @Prop mapHeight: number = 264;
  @Watch('onFlashReq') @Prop flashReq: string = '';
  @StorageLink('studioRev') @Watch('refresh') rev: number = 0;
  onSitePick: (id: string) => void = (): void => {
  };
  onMiss: (x: number, y: number) => void = (): void => {
  };
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private timer: number = -1;
  private lastTick: number = 0;
  private time: number = 0;
  private phase: number = 0;
  private zoom: number = 1;
  private clon: number = 108.0;
  private clat: number = 37.4;
  private k: number = 1;
  private w: number = 0;
  private h: number = 0;
  private fitK: number = 1;
  private pStart: number = 1;
  private pax: number = 0;
  private pay: number = 0;
  private panFromLon: number = 0;
  private panFromLat: number = 0;
  private target: ViewPreset | undefined = undefined;
  private from: ViewPreset | undefined = undefined;
  private glide: number = 0;
  private drops: Drop[] = [];
  private halos: Halo[] = [];
  private flashes: Flash[] = [];
  private alive: boolean = true;
  private main: number[] = [];
  private reaches: RiverReach[] = [];
  private riverPaths: Path2D[] = [];
  private networkStatus: string = '正在读取离线河网…';
  private terrainCache: ImageData | undefined = undefined;
  private terrainKey: string = "";

  aboutToAppear(): void {
    this.alive = true;
    this.loadNetwork();
  }

  private loadNetwork(): void {
    try {
      let bytes = getContext(this).resourceManager.getRawFileContentSync('basin-network.json');
      let data = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(bytes)) as RiverNetwork;
      if (!this.alive) { return; }
      this.main = data.main;
      this.reaches = data.reaches;
      this.networkStatus = 'HydroRIVERS · 放大查看细支流';
      this.terrainKey = '';
      this.paint();
    } catch (e) {
      this.networkStatus = '河网读取失败，请重新进入';
      this.paint();
    }
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.stop();
  }

  refresh(): void {
    this.stop();
    this.paint();
    this.ensureTimer();
  }

  private fitScale(): number {
    let dw = (LON1 - LON0) * COS;
    let dh = (LAT1 - LAT0) * STR;
    let a = (this.w - FIT_PAD * 2) / dw;
    let b = (this.h - FIT_PAD * 2) / dh;
    return a < b ? a : b;
  }

  private X(lon: number): number {
    return (lon - this.clon) * COS * this.k + this.w * 0.5;
  }

  private Y(lat: number, lon: number = 108): number {
    return (this.clat - lat) * STR * this.k + this.h * 0.48;
  }

  private invLon(x: number): number {
    return (x - this.w * 0.5) / (COS * this.k) + this.clon;
  }

  private invLat(y: number): number {
    return this.clat - (y - this.h * 0.48) / (STR * this.k);
  }

  private clampView(): void {
    if (this.zoom < 1) {
      this.zoom = 1;
    } else if (this.zoom > MAX_ZOOM) {
      this.zoom = MAX_ZOOM;
    }
    if (this.zoom <= 1.02) {
      this.clon = 108.0;
      this.clat = 37.4;
      return;
    }
    let hw = this.w * 0.5 / (COS * this.k);
    let hh = this.h * 0.5 / (STR * this.k);
    let s = 0.85;
    if (this.clon - hw * s < LON0) {
      this.clon = LON0 + hw * s;
    }
    if (this.clon + hw * s > LON1) {
      this.clon = LON1 - hw * s;
    }
    if (this.clat - hh * s < LAT0) {
      this.clat = LAT0 + hh * s;
    }
    if (this.clat + hh * s > LAT1) {
      this.clat = LAT1 - hh * s;
    }
  }

  ensureTimer(): void {
    if (this.timer >= 0) {
      return;
    }
    let busy = this.target !== undefined ||
      this.drops.length > 0 || this.halos.length > 0 || this.flashes.length > 0;
    if (!busy && effectiveWaterMode() !== WATER_FLOW) {
      return;
    }
    this.lastTick = Date.now();
    this.timer = setInterval((): void => {
      this.tick();
    }, FRAME_MS);
  }

  stop(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  tick(): void {
    let now = Date.now();
    let dt = (now - this.lastTick) / 1000;
    this.lastTick = now;
    if (dt > 0.2) {
      dt = 0.2;
    }
    let mode = effectiveWaterMode();
    if (mode === WATER_FLOW) {
      this.time = this.time + dt;
      this.phase = (this.phase + dt * FLOW_VP) % 4096;
    }
    this.stepGlide(dt);
    this.stepFx(dt);
    this.paint();
    let busy = this.target !== undefined ||
      this.drops.length > 0 || this.halos.length > 0 || this.flashes.length > 0;
    if (!busy && mode !== WATER_FLOW) {
      this.stop();
    }
  }

  stepGlide(dt: number): void {
    let tg = this.target;
    if (tg === undefined) {
      return;
    }
    this.glide = this.glide + dt / 0.62;
    let f = this.glide > 1 ? 1 : this.glide;
    let e = 1 - Math.pow(1 - f, 3);
    let fr = this.from;
    if (fr === undefined) {
      this.clon = tg.lon;
      this.clat = tg.lat;
      this.zoom = tg.zoom;
      this.target = undefined;
      return;
    }
    this.clon = fr.lon + (tg.lon - fr.lon) * e;
    this.clat = fr.lat + (tg.lat - fr.lat) * e;
    this.zoom = fr.zoom * Math.pow(tg.zoom / fr.zoom, e);
    if (f >= 1) {
      this.target = undefined;
    }
  }

  go(p: ViewPreset): void {
    this.from = { key: p.key, label: p.label, lon: this.clon, lat: this.clat, zoom: this.zoom };
    this.target = p;
    this.glide = 0;
    this.ensureTimer();
  }

  zoomTo(z1: number, ax: number, ay: number): void {
    if (z1 < 1) {
      z1 = 1;
    } else if (z1 > MAX_ZOOM) {
      z1 = MAX_ZOOM;
    }
    if (z1 === this.zoom) {
      return;
    }
    if (this.w > 0) {
      let gl0 = this.invLon(ax);
      let gg0 = this.invLat(ay);
      this.zoom = z1;
      this.k = this.fitScale() * this.zoom;
      this.clon = gl0 - (ax - this.w * 0.5) / (COS * this.k);
      this.clat = gg0 + (ay - this.h * 0.48) / (STR * this.k);
    } else {
      this.zoom = z1;
    }
    this.target = undefined;
    this.clampView();
    this.paint();
  }

  private nearestOnChain(pts: number[], x: number, y: number): number {
    let best = 1e9;
    let n = Math.floor(pts.length / 2);
    for (let i = 0; i < n - 1; i++) {
      let ax = this.X(pts[i * 2]);
      let ay = this.Y(pts[i * 2 + 1], pts[i * 2]);
      let bx = this.X(pts[i * 2 + 2]);
      let by = this.Y(pts[i * 2 + 3], pts[i * 2 + 2]);
      let dx = bx - ax;
      let dy = by - ay;
      let len = dx * dx + dy * dy;
      let t = len < 0.0001 ? 0 : ((x - ax) * dx + (y - ay) * dy) / len;
      if (t < 0) {
        t = 0;
      } else if (t > 1) {
        t = 1;
      }
      let px = ax + dx * t - x;
      let py = ay + dy * t - y;
      let d = px * px + py * py;
      if (d < best) {
        best = d;
      }
    }
    return Math.sqrt(best);
  }

  private onWater(x: number, y: number): boolean {
    if (this.nearestOnChain(this.main, x, y) <= HIT_RIVER) {
      return true;
    }
    for (let c of this.reaches) {
      if (this.nearestOnChain(c.pts, x, y) <= HIT_RIVER) {
        return true;
      }
    }
    return false;
  }

  tap(x: number, y: number): void {
    if (this.w <= 0) {
      return;
    }
    if (this.zoom >= SITE_ZOOM) {
      let best: Geo | undefined = undefined;
      let bestD = HIT_SITE * HIT_SITE;
      for (let g of SITE_GEO) {
        let dx = this.X(g.lon) - x;
        let dy = this.Y(g.lat, g.lon) - y;
        let d = dx * dx + dy * dy;
        if (d <= bestD) {
          bestD = d;
          best = g;
        }
      }
      if (best !== undefined) {
        this.burst(this.X(best.lon), this.Y(best.lat, best.lon), false);
        this.onSitePick(best.id);
        return;
      }
    }
    let onRiver = this.onWater(x, y);
    this.burst(x, y, false);
    if (!onRiver) {
      this.onMiss(x, y);
    }
  }

  onFlashReq(): void {
    let a = this.flashReq.split('|');
    if (a.length < 2) {
      return;
    }
    let g = geoOf(a[0]);
    if (g === undefined || this.w <= 0) {
      return;
    }
    this.burst(this.X(g.lon), this.Y(g.lat, g.lon), true);
    this.ensureTimer();
    if (this.timer < 0) {
      this.paint();
    }
  }

  burst(x: number, y: number, big: boolean): void {
    let n = big ? 26 : 15;
    for (let i = 0; i < n; i++) {
      let an = -Math.PI / 2 + (Math.random() - 0.5) * 2.3;
      let sp = (big ? 96 : 62) + Math.random() * (big ? 200 : 128);
      let d: Drop = {
        x: x, y: y,
        vx: Math.cos(an) * sp,
        vy: Math.sin(an) * sp,
        r: 0.8 + Math.random() * (big ? 2.6 : 1.7),
        life: 0,
        max: 0.42 + Math.random() * 0.5,
        hue: Math.random()
      };
      this.drops.push(d);
    }
    this.halos.push({ x: x, y: y, life: 0, max: big ? 1.05 : 0.8, big: big });
    if (big) {
      this.halos.push({ x: x, y: y, life: -0.2, max: 1.25, big: false });
    }
    this.flashes.push({ x: x, y: y, life: 0, max: 0.34 });
    while (this.drops.length > 240) {
      this.drops.shift();
    }
    this.ensureTimer();
  }

  stepFx(dt: number): void {
    let g = 300;
    let i = this.drops.length;
    while (i > 0) {
      i = i - 1;
      let p = this.drops[i];
      p.life = p.life + dt;
      if (p.life >= p.max) {
        this.drops.splice(i, 1);
        continue;
      }
      p.vy = p.vy + g * dt;
      p.vx = p.vx * 0.99;
      p.x = p.x + p.vx * dt;
      p.y = p.y + p.vy * dt;
    }
    let j = this.halos.length;
    while (j > 0) {
      j = j - 1;
      let r = this.halos[j];
      r.life = r.life + dt;
      if (r.life >= r.max) {
        this.halos.splice(j, 1);
      }
    }
    let m = this.flashes.length;
    while (m > 0) {
      m = m - 1;
      let f = this.flashes[m];
      f.life = f.life + dt;
      if (f.life >= f.max) {
        this.flashes.splice(m, 1);
      }
    }
  }

  private trace(c: CanvasRenderingContext2D, pts: number[], i0: number, i1: number): void {
    c.beginPath();
    for (let i = i0; i <= i1; i++) {
      let x = this.X(pts[i * 2]);
      let y = this.Y(pts[i * 2 + 1], pts[i * 2]);
      if (i === i0) {
        c.moveTo(x, y);
      } else {
        c.lineTo(x, y);
      }
    }
  }

  private paintSky(c: CanvasRenderingContext2D): void {
    c.fillStyle = '#080D13';
    c.fillRect(0, 0, this.w, this.h);
  }

  private paintNetwork(c: CanvasRenderingContext2D, dim: boolean): void {
    let key = `${this.w}|${this.h}|${this.k}|${this.clon}|${this.clat}|${dim}|${this.main.length}`;
    if (key === this.terrainKey && this.terrainCache !== undefined) {
      c.putImageData(this.terrainCache, 0, 0); return;
    }
    this.paintSky(c);
    let minOrder = this.zoom < 1.65 ? 3 : (this.zoom < 3.1 ? 2 : 1);
    let palette: string[] = ['#A4ACBC', '#BBC8DC', '#CBD6E6', '#D8D7E8', '#DADDED', '#E4E9EE', '#E8EEF2', '#EDF3F6'];
    c.lineCap = 'round'; c.lineJoin = 'round';
    for (let order = minOrder; order <= 8; order++) {
      c.beginPath();
      for (let reach of this.reaches) {
        if (reach.order !== order) { continue; }
        for (let i = 0; i < reach.pts.length; i += 2) {
          let x = this.X(reach.pts[i]); let y = this.Y(reach.pts[i + 1]);
          if (i === 0) { c.moveTo(x, y); } else { c.lineTo(x, y); }
        }
      }
      c.strokeStyle = palette[order - 1]; c.globalAlpha = dim ? 0.4 : 0.8;
      c.lineWidth = Math.min(2.1, (0.23 + order * 0.15) * Math.pow(this.zoom, 0.22));
      c.stroke();
    }
    c.globalAlpha = 1;
    this.paintLakes(c);
    if (this.zoom >= 1.8) {
      c.font = '9px sans-serif'; c.fillStyle = '#AEBACC';
      for (let ch of TRIB) {
        if (!ch.big && this.zoom < 3) { continue; }
        let mid = Math.floor(ch.pts.length / 4);
        let x = this.X(ch.pts[mid * 2]); let y = this.Y(ch.pts[mid * 2 + 1]);
        c.strokeStyle = '#080D13'; c.lineWidth = 3;
        c.strokeText(ch.name, x + 4, y - 4); c.fillText(ch.name, x + 4, y - 4);
      }
    }
    this.terrainCache = c.getImageData(0, 0, this.w, this.h);
    this.terrainKey = key;
  }

  private paintLakes(c: CanvasRenderingContext2D): void {
    for (let lk of LAKES) {
      let x = this.X(lk.lon);
      let y = this.Y(lk.lat, lk.lon);
      let rx = lk.rx * COS * this.k;
      let ry = lk.ry * STR * this.k;
      c.beginPath();
      c.ellipse(x, y, rx, ry, 0, 0, TAU);
      c.fillStyle = 'rgba(187,203,222,0.6)';
      c.fill();
      c.strokeStyle = 'rgba(219,231,241,0.72)';
      c.lineWidth = 0.9;
      c.stroke();
      if (lk.label && this.zoom >= 1.7) {
        c.font = '9px sans-serif';
        c.fillStyle = 'rgba(150,206,216,0.55)';
        c.fillText(lk.name, x + rx + 3, y + 3);
      }
    }
  }

  private paintMain(c: CanvasRenderingContext2D, flow: boolean, glowOn: boolean): void {
    if (this.main.length < 4) { return; }
    let n = Math.floor(this.main.length / 2) - 1;
    let chunks = 7;
    let bw = Math.max(1.0, Math.min(3.2, 1.25 * Math.sqrt(this.zoom)));
    c.lineJoin = 'round';
    c.lineCap = 'round';
    let breathe = glowOn ? 1 + 0.1 * Math.sin(this.time * 0.55) : 1;
    for (let ch = 0; ch < chunks; ch++) {
      let i0 = Math.floor(ch * n / chunks);
      let i1 = Math.floor((ch + 1) * n / chunks);
      if (i1 <= i0) {
        continue;
      }
      let wid = bw * (0.6 + 0.95 * (ch + 0.5) / chunks);
      this.trace(c, this.main, i0, i1);
      c.strokeStyle = 'rgba(206,164,104,0.15)';
      c.lineWidth = wid * 6.2;
      c.stroke();
    }
    for (let pass = 0; pass < 4; pass++) {
      for (let ch = 0; ch < chunks; ch++) {
        let i0 = Math.floor(ch * n / chunks);
        let i1 = Math.floor((ch + 1) * n / chunks);
        if (i1 <= i0) {
          continue;
        }
        let f = (ch + 0.5) / chunks;
        this.trace(c, this.main, i0, i1);
        let wid = bw * (0.6 + 0.95 * f);
        if (pass === 0 && glowOn) {
          c.strokeStyle = `rgba(255,170,52,${(0.085 * breathe).toFixed(3)})`;
          c.lineWidth = wid * 8.5;
          c.stroke();
        } else if (pass === 1 && glowOn) {
          c.strokeStyle = `rgba(255,200,84,${(0.19 * breathe).toFixed(3)})`;
          c.lineWidth = wid * 4.2;
          c.stroke();
        } else if (pass === 2) {
          c.strokeStyle = glowOn ? 'rgba(255,228,146,0.86)' : 'rgba(206,178,120,0.5)';
          c.lineWidth = glowOn ? wid * 1.9 : wid * 1.3;
          c.stroke();
        } else if (pass === 3) {
          c.strokeStyle = glowOn ? 'rgba(255,250,222,0.95)' : 'rgba(226,206,170,0.42)';
          c.lineWidth = wid * 0.85;
          c.stroke();
        }
      }
    }
    if (glowOn) {
      c.save();
      c.setLineDash([12, 18]);
      c.lineDashOffset = -(this.phase % 30);
      for (let ch = 0; ch < chunks; ch++) {
        let i0 = Math.floor(ch * n / chunks);
        let i1 = Math.floor((ch + 1) * n / chunks);
        if (i1 <= i0) {
          continue;
        }
        let f = (ch + 0.5) / chunks;
        this.trace(c, this.main, i0, i1);
        c.strokeStyle = flow ? 'rgba(255,255,236,0.72)' : 'rgba(255,244,200,0.5)';
        c.lineWidth = bw * (0.6 + 0.95 * f) * 0.95;
        c.stroke();
      }
      c.restore();
      c.setLineDash([]);
    }
    if (this.zoom < 2.4) {
      c.font = `${Math.round(10 + Math.min(4, this.zoom))}px sans-serif`;
      c.fillStyle = 'rgba(255,224,150,0.5)';
      let mi = Math.floor(n * 0.62);
      c.fillText('黄河', this.X(this.main[mi * 2]) - 8, this.Y(this.main[mi * 2 + 1], this.main[mi * 2]) - 12);
    }
  }

  private paintCities(c: CanvasRenderingContext2D): void {
    if (this.zoom < 1.6) { return; }
    let lv = this.zoom < 1.5 ? 1 : (this.zoom < 2.4 ? 2 : 3);
    let r = this.zoom > 3 ? 2.4 : 1.9;
    c.font = `${Math.round(this.zoom > 2.4 ? 10 : 9)}px sans-serif`;
    for (let ct of CITIES) {
      if (ct.name === '兰州') { continue; }
      if (ct.lv > lv) {
        continue;
      }
      let x = this.X(ct.lon);
      let y = this.Y(ct.lat, ct.lon);
      if (x < -20 || x > this.w + 20 || y < -20 || y > this.h + 20) {
        continue;
      }
      c.beginPath();
      c.moveTo(x, y - r - 3.4);
      c.lineTo(x, y - r - 0.6);
      c.strokeStyle = 'rgba(240,236,226,0.5)';
      c.lineWidth = 1;
      c.stroke();
      c.beginPath();
      c.arc(x, y, r, 0, TAU);
      c.fillStyle = 'rgba(244,240,230,0.9)';
      c.fill();
      c.beginPath();
      c.arc(x, y, r + 2.6, 0, TAU);
      c.strokeStyle = 'rgba(244,240,230,0.22)';
      c.lineWidth = 1;
      c.stroke();
      c.fillStyle = ct.lv === 1 ? 'rgba(240,236,224,0.85)' : 'rgba(216,212,202,0.62)';
      c.fillText(ct.name, x + 4, y - 3.5);
    }
  }

  private paintBasinLabels(c: CanvasRenderingContext2D): void {
    c.save();
    c.font = `${vp2px(fs(this.ts, 10))}px sans-serif`;
    c.textBaseline = 'middle';
    for (let mark of BASIN_LABELS) {
      let x = this.X(mark.lon); let y = this.Y(mark.lat);
      if (x < 5 || x > this.w - 5 || y < 58 || y > this.h - 64) { continue; }
      let bw = c.measureText(mark.name).width + 16;
      let bh = 24;
      let bx = Math.max(8, Math.min(this.w - bw - 8, x + mark.dx));
      let by = Math.max(55, Math.min(this.h - 88, y + mark.dy));
      c.beginPath(); c.moveTo(x, y);
      c.lineTo(Math.max(bx + 8, Math.min(bx + bw - 8, x)), by + bh);
      c.lineWidth = 0.7; c.strokeStyle = 'rgba(242,219,164,0.65)'; c.stroke();
      c.fillStyle = 'rgba(16,23,31,0.60)';
      c.fillRect(bx, by, bw, bh);
      c.strokeStyle = 'rgba(239,214,159,0.48)'; c.lineWidth = 0.6;
      c.strokeRect(bx, by, bw, bh);
      c.fillStyle = '#F3E2B5'; c.fillText(mark.name, bx + 8, by + bh / 2);
      c.beginPath(); c.arc(x, y, 2, 0, TAU); c.fillStyle = '#FFF2C9'; c.fill();
    }
    c.restore();
  }

  private paintSites(c: CanvasRenderingContext2D): void {
    if (this.zoom < SITE_ZOOM) {
      let x = this.X(112.9);
      let y = this.Y(34.85, 112.9);
      c.beginPath();
      c.arc(x, y, 6.5, 0, TAU);
      c.strokeStyle = 'rgba(255,222,150,0.75)';
      c.lineWidth = 1.4;
      c.stroke();
      c.beginPath();
      c.arc(x, y, 2.4, 0, TAU);
      c.fillStyle = 'rgba(255,232,170,0.95)';
      c.fill();
      c.font = '10px sans-serif';
      c.fillStyle = 'rgba(255,226,164,0.8)';
      c.fillText('河南流域 · 20 处（放大看）', x + 10, y + 4);
      return;
    }
    let checked = StudioStore.get().checkedSiteIds();
    let names: Map<string, string> = new Map();
    for (let s of SiteRepo.get().sites) {
      names.set(s.id, s.name);
    }
    let big = this.zoom > 2.6;
    for (let g of SITE_GEO) {
      let x = this.X(g.lon);
      let y = this.Y(g.lat, g.lon);
      if (x < -30 || x > this.w + 30 || y < -30 || y > this.h + 30) {
        continue;
      }
      let on = checked.indexOf(g.id) >= 0;
      let active = g.id === this.activeId;
      let r = active ? 5.2 : (on ? 4.2 : 3.4);
      if (on) {
        c.beginPath();
        c.arc(x, y, r + 6, 0, TAU);
        c.fillStyle = 'rgba(255,168,72,0.16)';
        c.fill();
      }
      c.beginPath();
      c.arc(x, y, r, 0, TAU);
      c.fillStyle = on ? 'rgba(216,116,72,0.95)' : 'rgba(255,240,200,0.22)';
      c.fill();
      c.beginPath();
      c.arc(x, y, r, 0, TAU);
      c.strokeStyle = active ? 'rgba(255,248,222,1)' : 'rgba(255,236,190,0.85)';
      c.lineWidth = active ? 2 : 1.2;
      c.stroke();
      if (on) {
        c.beginPath();
        c.moveTo(x - 2.2, y);
        c.lineTo(x - 0.4, y + 2);
        c.lineTo(x + 2.4, y - 2.1);
        c.strokeStyle = 'rgba(255,250,240,0.95)';
        c.lineWidth = 1.3;
        c.stroke();
      }
      if (active || (big && (on || this.zoom > 4))) {
        let nm = names.get(g.id);
        if (nm !== undefined) {
          c.font = '9.5px sans-serif';
          c.fillStyle = active ? 'rgba(255,248,226,0.95)' : 'rgba(236,226,206,0.7)';
          c.fillText(nm, x + r + 3, y + 3.4);
        }
      }
    }
  }

  private paintFx(c: CanvasRenderingContext2D): void {
    for (let f of this.flashes) {
      let k = f.life / f.max;
      let rad = 4 + k * 42;
      let al = (1 - k) * 0.85;
      let gr = c.createRadialGradient(f.x, f.y, 0, f.x, f.y, rad);
      gr.addColorStop(0, `rgba(255,252,224,${(al).toFixed(3)})`);
      gr.addColorStop(0.35, `rgba(255,208,96,${(al * 0.62).toFixed(3)})`);
      gr.addColorStop(0.75, `rgba(255,146,40,${(al * 0.3).toFixed(3)})`);
      gr.addColorStop(1, 'rgba(255,120,30,0)');
      c.beginPath();
      c.arc(f.x, f.y, rad, 0, TAU);
      c.fillStyle = gr;
      c.fill();
    }
    for (let h of this.halos) {
      if (h.life < 0) {
        continue;
      }
      let k = h.life / h.max;
      let rad = (h.big ? 9 : 6) + k * (h.big ? 74 : 50);
      c.save();
      c.translate(h.x, h.y);
      c.scale(1, 0.46);
      c.beginPath();
      c.arc(0, 0, rad, 0, TAU);
      c.strokeStyle = `rgba(255,214,120,${(0.7 * (1 - k)).toFixed(3)})`;
      c.lineWidth = 2.4 * (1 - k) + 0.4;
      c.stroke();
      c.beginPath();
      c.arc(0, 0, rad * 0.66, 0, TAU);
      c.strokeStyle = `rgba(255,152,54,${(0.42 * (1 - k)).toFixed(3)})`;
      c.lineWidth = 1.4 * (1 - k) + 0.3;
      c.stroke();
      c.beginPath();
      c.arc(0, 0, rad * 1.12, 0, TAU);
      c.strokeStyle = `rgba(255,120,40,${(0.2 * (1 - k)).toFixed(3)})`;
      c.lineWidth = 1;
      c.stroke();
      c.restore();
    }
    for (let p of this.drops) {
      let k = p.life / p.max;
      let a = (1 - k) * 0.94;
      let rr = Math.round(255);
      let rg = Math.round(236 - 106 * (k * 0.7 + p.hue * 0.3));
      let rb = Math.round(176 - 156 * (k * 0.7 + p.hue * 0.3));
      c.beginPath();
      c.arc(p.x, p.y, p.r, 0, TAU);
      c.fillStyle = `rgba(${rr},${rg},${rb},${a.toFixed(3)})`;
      c.fill();
      if (p.r > 1.8) {
        c.beginPath();
        c.arc(p.x, p.y, p.r * 2.1, 0, TAU);
        c.fillStyle = `rgba(255,168,60,${(a * 0.2).toFixed(3)})`;
        c.fill();
      }
    }
  }

  private paintHud(c: CanvasRenderingContext2D): void {
    let w = this.w;
    c.font = '9px sans-serif';
    c.fillStyle = 'rgba(226,220,206,0.5)';
    c.fillText('N', 14, 18);
    c.beginPath();
    c.moveTo(16.5, 30);
    c.lineTo(16.5, 21);
    c.strokeStyle = 'rgba(226,220,206,0.4)';
    c.lineWidth = 1;
    c.stroke();
    c.beginPath();
    c.moveTo(16.5, 20);
    c.lineTo(14.6, 24);
    c.lineTo(18.4, 24);
    c.closePath();
    c.fillStyle = 'rgba(226,220,206,0.45)';
    c.fill();
    c.font = '9.5px sans-serif';
    c.fillStyle = 'rgba(226,220,206,0.45)';
    c.fillText(this.networkStatus, 13, 44);
    let vn = '全流域';
    if (this.zoom > 1.12) {
      if (this.clon < 102.5) {
        vn = '黄河源 · 青藏高原';
      } else if (this.clon < 106.6) {
        vn = '上游 · 陇青峡谷';
      } else if (this.clat > 38.4) {
        vn = '河套 · 几字弯';
      } else if (this.clat > 36.4 && this.clon > 109) {
        vn = '晋陕峡谷';
      } else if (this.clon > 116.2) {
        vn = '下游 · 山东入海';
      } else if (this.zoom > 2.2 && this.clat < 35.6) {
        vn = '河南流域';
      } else {
        vn = '中游 · 关中—洛阳';
      }
    }
    c.font = '10.5px sans-serif';
    c.fillStyle = 'rgba(255,228,168,0.72)';
    let tw2 = c.measureText(vn).width;
    c.fillText(vn, w - tw2 - 14, 22);
    let kmPerVp = 111 / (STR * this.k);
    let opts: number[] = [50, 100, 200, 300, 500, 1000];
    let pickKm = opts[opts.length - 1];
    for (let o of opts) {
      if (o / kmPerVp <= 92) {
        pickKm = o;
        break;
      }
    }
    let len = pickKm / kmPerVp;
    let x0 = 14;
    let y0 = this.h - 48;
    c.beginPath();
    c.moveTo(x0, y0 - 4);
    c.lineTo(x0, y0);
    c.lineTo(x0 + len, y0);
    c.lineTo(x0 + len, y0 - 4);
    c.moveTo(x0 + len / 2, y0);
    c.lineTo(x0 + len / 2, y0 - 3);
    c.strokeStyle = 'rgba(232,226,212,0.5)';
    c.lineWidth = 1;
    c.stroke();
    c.font = '8.5px sans-serif';
    c.fillStyle = 'rgba(232,226,212,0.55)';
    c.fillText(`0 / ${pickKm} 千米`, x0 + len + 6, y0);
  }

  private paint(): void {
    let c = this.ctx;
    let w = c.width;
    let h = c.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    this.w = w;
    this.h = h;
    this.fitK = this.fitScale();
    this.k = this.fitK * this.zoom;
    let mode = effectiveWaterMode();
    let dim = mode === WATER_OFF;
    let flow = mode === WATER_FLOW && !dim;
    c.clearRect(0, 0, w, h);
    this.paintNetwork(c, dim);
    this.paintMain(c, flow, !dim);
    this.paintCities(c);
    this.paintSites(c);
    this.paintBasinLabels(c);
    if (this.halos.length > 0 || this.drops.length > 0 || this.flashes.length > 0) {
      this.paintFx(c);
    }
    this.paintHud(c);
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Canvas(this.ctx)
        .width('100%')
        .height('100%')
        .onReady((): void => {
          this.paint();
          this.ensureTimer();
        })
      Row({ space: 6 }) {
        ForEach(PRESETS, (p: ViewPreset): void => {
          Text(p.label)
            .fontSize(fs(this.ts, 11))
            .fontColor('rgba(255,236,190,0.92)')
            .padding({ left: 9, right: 9, top: 4, bottom: 4 })
            .backgroundColor('rgba(38,32,26,0.55)')
            .border({ width: 0.8, color: 'rgba(255,214,140,0.35)' })
            .borderRadius(12)
            .onClick((): void => {
              this.go(p);
            })
        }, (p: ViewPreset): string => p.key)
        Text('−')
          .fontSize(fs(this.ts, 14))
          .fontColor('rgba(255,236,190,0.92)')
          .width(24)
          .height(24)
          .textAlign(TextAlign.Center)
          .backgroundColor('rgba(38,32,26,0.55)')
          .border({ width: 0.8, color: 'rgba(255,214,140,0.35)' })
          .borderRadius(12)
          .onClick((): void => {
            this.zoomTo(this.zoom / 1.4, this.w / 2, this.h / 2);
          })
        Text('+')
          .fontSize(fs(this.ts, 14))
          .fontColor('rgba(255,236,190,0.92)')
          .width(24)
          .height(24)
          .textAlign(TextAlign.Center)
          .backgroundColor('rgba(38,32,26,0.55)')
          .border({ width: 0.8, color: 'rgba(255,214,140,0.35)' })
          .borderRadius(12)
          .onClick((): void => {
            this.zoomTo(this.zoom * 1.4, this.w / 2, this.h / 2);
          })
      }
      .margin({ right: 10, bottom: 10 })
    }
    .width('100%')
    .height(this.mapHeight)
    .borderRadius(14)
    .clip(true)
    .onClick((e: ClickEvent): void => {
      this.tap(e.x, e.y);
    })
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        PinchGesture({ fingers: 2 })
          .onActionStart((ev: GestureEvent): void => {
            this.pStart = this.zoom;
            this.pax = ev.pinchCenterX;
            this.pay = ev.pinchCenterY;
            this.target = undefined;
          })
          .onActionUpdate((ev: GestureEvent): void => {
            this.zoomTo(this.pStart * ev.scale, this.pax, this.pay);
          })
          .onActionEnd((): void => {
            this.ensureTimer();
          }),
        PanGesture({ fingers: 1, distance: 8 })
          .onActionStart((): void => {
            this.panFromLon = this.clon;
            this.panFromLat = this.clat;
            this.target = undefined;
          })
          .onActionUpdate((ev: GestureEvent): void => {
            this.clon = this.panFromLon - ev.offsetX / (COS * this.k);
            this.clat = this.panFromLat + ev.offsetY / (STR * this.k);
            this.clampView();
            this.paint();
          })
          .onActionEnd((): void => {
            this.ensureTimer();
          })
      )
    )
  }
}
