export const ERAS: string[] = ['仰韶', '龙山', '夏商', '周', '汉唐', '宋'];
export const CITIES: string[] = ['三门峡', '洛阳', '郑州', '开封', '濮阳'];
export const TYPES: string[] = ['都城遗址', '聚落遗址', '墓葬群', '窑址', '手工业遗址', '古建筑', '石窟寺'];

export const ERA_WORD: Map<string, string> = new Map([
  ['仰韶', '彩陶'], ['龙山', '黑陶'], ['夏商', '青铜'],
  ['周', '礼乐'], ['汉唐', '三彩'], ['宋', '雅韵']
]);

export const DEFAULT_TAG_NAMES: string[] = ['待实地探访', '已去过', '研究资料'];

export const INK = '#2B2622';
export const SUB = '#7A6E62';
export const LOESS = '#C8A160';
export const CLAY = '#A6553D';
export const RIVER = '#4A7B8C';
export const PAPER = '#F5EFE4';
export const LINE = '#E5DAC6';

export const WATER_FLOW: string = 'flow';
export const WATER_STILL: string = 'still';
export const WATER_OFF: string = 'off';

export const SCALE_STEPS: number[] = [0.85, 1, 1.20];
export const SCALE_LABELS: string[] = ['小', '标准', '大'];

export function fs(scale: number, base: number): number {
  let s = scale > 0 ? scale : 1;
  let v = base * s;
  return Math.round(v * 10) / 10;
}

export function coverOf(era: string): string {
  if (era === '龙山') {
    return 'era_longshan';
  }
  if (era === '夏商') {
    return 'era_xiashang';
  }
  if (era === '周') {
    return 'era_zhou';
  }
  if (era === '汉唐') {
    return 'era_hantang';
  }
  if (era === '宋') {
    return 'era_song';
  }
  return 'era_yangshao';
}

export function coverRes(name: string): Resource {
  if (name.indexOf('site_') === 0) {
    return $rawfile('sites/' + name.substring(5) + '.jpg');
  }
  switch (name) {
    case 'era_longshan':
      return $r('app.media.era_longshan');
    case 'era_xiashang':
      return $r('app.media.era_xiashang');
    case 'era_zhou':
      return $r('app.media.era_zhou');
    case 'era_hantang':
      return $r('app.media.era_hantang');
    case 'era_song':
      return $r('app.media.era_song');
    case 'hero_river':
      return $r('app.media.hero_river');
    case 'relic_caitao':
      return $r('app.media.relic_caitao');
    case 'relic_heitao':
      return $r('app.media.relic_heitao');
    case 'relic_qingtong':
      return $r('app.media.relic_qingtong');
    case 'relic_bianzhong':
      return $r('app.media.relic_bianzhong');
    case 'relic_sancai':
      return $r('app.media.relic_sancai');
    case 'relic_tianqing':
      return $r('app.media.relic_tianqing');
    default:
      return $r('app.media.era_yangshao');
  }
}

export function fmtTime(ts: number): string {
  if (ts <= 0) {
    return '从未';
  }
  let d = new Date(ts);
  let mm = d.getMonth() + 1;
  let dd = d.getDate();
  let hh = d.getHours();
  let mi = d.getMinutes();
  return `${d.getFullYear()}-${mm}-${dd} ` +
    `${hh < 10 ? '0' : ''}${hh}:${mi < 10 ? '0' : ''}${mi}`;
}

export function dayText(ts: number): string {
  let d = new Date(ts);
  return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`;
}

export interface Palette {
  base: string;
  deep: string;
  accent: string;
  ink: string;
  paper: string;
}

const PALETTES: Map<string, Palette> = new Map<string, Palette>([
  ['yangshao', { base: '#D9A173', deep: '#A6553D', accent: '#3A2A22', ink: '#F6E9DA', paper: '#F0DCC2' }],
  ['longshan', { base: '#5B5A57', deep: '#2E2D2C', accent: '#9C8A6E', ink: '#EDE7DC', paper: '#D8D2C6' }],
  ['xiashang', { base: '#7E9A7A', deep: '#46614C', accent: '#C8A160', ink: '#F1EEE2', paper: '#DDE3D6' }],
  ['zhou', { base: '#A8B3A0', deep: '#5F6E63', accent: '#B4894C', ink: '#F4F1E6', paper: '#E2E5DB' }],
  ['hantang', { base: '#D2A25C', deep: '#8E5A2B', accent: '#4A7B8C', ink: '#FBF0DC', paper: '#F0DCB8' }],
  ['song', { base: '#9FBFB6', deep: '#5C837B', accent: '#C08B5E', ink: '#F3F5F0', paper: '#DDE8E3' }]
]);

export function paletteOf(key: string): Palette {
  let p = PALETTES.get(key);
  return p === undefined ? (PALETTES.get('yangshao') as Palette) : p;
}

export interface ColorRow {
  key: string;
  name: string;
  era: string;
  saying: string;
}

const COLOR_ROWS: ColorRow[] = [
  { key: 'yangshao', name: '仰韶红', era: '仰韶', saying: '彩陶的底色，是黄河泥在窑火里烧出来的红。' },
  { key: 'longshan', name: '龙山黑', era: '龙山', saying: '黑陶靠渗碳烧成，黑得发亮，薄得透光。' },
  { key: 'xiashang', name: '夏商青绿', era: '夏商', saying: '青铜刚铸出来是亮的青绿，锈了才沉成现在这样。' },
  { key: 'zhou', name: '周玉色', era: '周', saying: '玉色是礼器的底子，温而不艳，压得住场面。' },
  { key: 'hantang', name: '汉唐赭黄', era: '汉唐', saying: '赭黄是三彩釉里的主色，铅釉在火里流得开。' },
  { key: 'song', name: '宋天青', era: '宋', saying: '天青是"雨过天晴云破处"的那一层青。' }
];

export function colorRowOf(key: string): ColorRow {
  for (let r of COLOR_ROWS) {
    if (r.key === key) {
      return r;
    }
  }
  return COLOR_ROWS[0];
}

export function withAlpha(hex: string, a: number): string {
  if (hex.length !== 7 || !hex.startsWith('#')) {
    return hex;
  }
  let r = parseInt(hex.substring(1, 3), 16);
  let g = parseInt(hex.substring(3, 5), 16);
  let b = parseInt(hex.substring(5, 7), 16);
  let al = Math.round(Math.max(0, Math.min(1, a)) * 1000) / 1000;
  return `rgba(${r},${g},${b},${al})`;
}

export function hexLum(hex: string): number {
  if (hex.length !== 7 || !hex.startsWith('#')) {
    return 128;
  }
  let r = parseInt(hex.substring(1, 3), 16);
  let g = parseInt(hex.substring(3, 5), 16);
  let b = parseInt(hex.substring(5, 7), 16);
  return 0.299 * r + 0.587 * g + 0.114 * b;
}

export function eraPalette(era: string): string {
  if (era === '龙山') {
    return 'longshan';
  }
  if (era === '夏商') {
    return 'xiashang';
  }
  if (era === '周') {
    return 'zhou';
  }
  if (era === '汉唐') {
    return 'hantang';
  }
  if (era === '宋') {
    return 'song';
  }
  return 'yangshao';
}

export function moneyText(n: number): string {
  return n % 1 === 0 ? `${n}` : n.toFixed(2);
}

export function agoText(ts: number): string {
  let gap = Date.now() - ts;
  if (gap < 0) {
    return '刚刚';
  }
  let min = Math.floor(gap / 60000);
  if (min < 1) {
    return '刚刚';
  }
  if (min < 60) {
    return `${min}分钟前`;
  }
  let hr = Math.floor(min / 60);
  if (hr < 24) {
    return `${hr}小时前`;
  }
  let day = Math.floor(hr / 24);
  return day <= 30 ? `${day}天前` : fmtTime(ts).substring(0, 10);
}

export function likeText(n: number): string {
  return n >= 1000 ? `${(n / 1000).toFixed(1)}k` : `${n}`;
}
