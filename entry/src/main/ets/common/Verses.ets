import { SiteRepo } from '../service/SiteRepo';

export interface Verse {
  text: string;
  from: string;
  real: boolean;
  siteId: string;
}

export const VERSES: Verse[] = [
  { text: '谁家玉笛暗飞声，散入春风满洛城。', from: '李白《春夜洛城闻笛》', real: true, siteId: 's07' },
  { text: '君不见黄河之水天上来，奔流到海不复回。', from: '李白《将进酒》', real: true, siteId: 's18' },
  { text: '仰韶村的土，一层彩陶一层人。', from: '拟咏', real: false, siteId: 's01' },
  { text: '北阳平的窑火，烧红过半条河湾。', from: '拟咏', real: false, siteId: 's02' },
  { text: '虢国墓的玉戈，凉在土里三千年。', from: '拟咏', real: false, siteId: 's03' },
  { text: '二里头的绿松石，还认得当年的王。', from: '拟咏', real: false, siteId: 's04' },
  { text: '偃师商城的墙，圈住一个王朝的开头。', from: '拟咏', real: false, siteId: 's05' },
  { text: '周王城的车辙，把土压成了路。', from: '拟咏', real: false, siteId: 's06' },
  { text: '卢舍那的月光，落过一千三百年。', from: '拟咏', real: false, siteId: 's08' },
  { text: '王城岗的夯土，量过夏代的一天。', from: '拟咏', real: false, siteId: 's09' },
  { text: '郑州商城的方鼎，沉得两个人抬。', from: '拟咏', real: false, siteId: 's10' },
  { text: '巩县窑的白瓷，装过西市的胡商。', from: '拟咏', real: false, siteId: 's11' },
  { text: '嵩岳寺塔的十二角，站了一千五百年。', from: '拟咏', real: false, siteId: 's12' },
  { text: '古荥的炉渣，比铁还沉。', from: '拟咏', real: false, siteId: 's13' },
  { text: '东京城的花灯，压在六米深的土下。', from: '拟咏', real: false, siteId: 's14' },
  { text: '州桥底下的泥，一层压着一层城。', from: '拟咏', real: false, siteId: 's15' },
  { text: '铁塔的琉璃，雨一淋就发青。', from: '拟咏', real: false, siteId: 's16' },
  { text: '相国寺的钟声，穿过整个北宋。', from: '拟咏', real: false, siteId: 's17' },
  { text: '西水坡的蚌壳，摆出最早的龙。', from: '拟咏', real: false, siteId: 's18' },
  { text: '戚城的台基，还留着会盟的位置。', from: '拟咏', real: false, siteId: 's19' },
  { text: '回銮碑立着，把一次盟誓刻成石。', from: '拟咏', real: false, siteId: 's20' }
];

function dayOfYear(ts: number): number {
  let d = new Date(ts);
  let start = new Date(d.getFullYear(), 0, 1);
  return Math.floor((d.getTime() - start.getTime()) / 86400000);
}

export function verseOf(ts: number): Verse {
  return VERSES[dayOfYear(ts) % VERSES.length];
}

export function verseSiteName(v: Verse): string {
  let s = SiteRepo.get().byId(v.siteId);
  return s === undefined ? '' : s.name;
}
