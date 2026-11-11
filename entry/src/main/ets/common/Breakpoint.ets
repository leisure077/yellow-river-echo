import { deviceInfo } from '@kit.BasicServicesKit';

// 平板适配的总闸。断点按系统口径分四档（单位 vp）：sm<600、md 600~840、lg 840~1440、xl≥1440。
//
// 这一层只服务宽屏：所有函数都收着「手机上今天用的那个值」当入参，窄屏一律原样返回，
// 所以手机渲染结果不会因为适配被动到任何一个像素。默认档取 sm，也就是万一窗口宽度
// 没读到，页面退回的是手机布局，不是错排成宽屏。

// 大屏手机横屏能越过 840vp 这道线，所以设备类型再兜一道：
// phone 设备无论多宽都走窄屏，只有平板这类设备才进宽屏分支。
function wideAt(wVp: number): boolean {
  if (deviceInfo.deviceType === 'phone') {
    return false;
  }
  return wVp >= 840;
}

export function bpOf(wVp: number): string {
  if (!wideAt(wVp)) {
    return wVp >= 600 ? 'md' : 'sm';
  }
  return wVp >= 1440 ? 'xl' : 'lg';
}

export function isWide(bp: string): boolean {
  return bp === 'lg' || bp === 'xl';
}

// 只在档位真的换了时才写 AppStorage：窗口每变一次像素都广播一遍，四个 tab 页会整页重画，
// 旋转过程中反而多一次卡顿。同一档位内（比如平板小窗拖动）布局不变，不用惊动任何人。
let lastBp: string = '';

export function pushBp(wVp: number): void {
  let next = bpOf(wVp);
  if (next === lastBp) {
    return;
  }
  lastBp = next;
  AppStorage.setOrCreate('bp', next);
}

// 页面左右留白：宽屏按档加宽，窄屏返回手机原值
export function padX(bp: string, phone: number): number {
  if (bp === 'xl') {
    return phone + 10;
  }
  if (bp === 'lg') {
    return phone + 6;
  }
  return phone;
}

// 按档放大的数值（图件高度、抽屉宽度）：宽屏抬一档，窄屏一律返回手机原值
export function wideH(bp: string, phone: number, lg: number, xl: number): number {
  if (bp === 'xl') {
    return xl;
  }
  if (bp === 'lg') {
    return lg;
  }
  return phone;
}

// 需要收在中间的一段横条（底栏、弹层内容）：宽屏给一个百分比宽度，父容器默认居中；
// 窄屏返回手机原来那句 '100%'。
export function wideW(bp: string, phone: string, lg: string, xl: string): string {
  if (bp === 'xl') {
    return xl;
  }
  if (bp === 'lg') {
    return lg;
  }
  return phone;
}

// Grid / WaterFlow 的列模板。手机给几列就是几列，宽屏按档加列。
export function frTemplate(bp: string, phoneCols: number): string {
  let n = phoneCols;
  if (bp === 'xl') {
    n = phoneCols + 2;
  } else if (bp === 'lg') {
    n = phoneCols + 1;
  }
  let out: string = '1fr';
  for (let i = 1; i < n; i++) {
    out = out + ' 1fr';
  }
  return out;
}

// Flex 换行卡片实际是几列（和 frTemplate 同一套递增）
export function cellCols(bp: string, phoneCols: number): number {
  if (bp === 'xl') {
    return phoneCols + 2;
  }
  if (bp === 'lg') {
    return phoneCols + 1;
  }
  return phoneCols;
}

// 卡片宽度百分比：(100 - 间距×(列数-1)) / 列数。
// 手机两列、间距 4 代进去正好是今天写死的 48%，所以窄屏这条路径和旧值完全重合。
// 只能往下取整：四列时 21.25% 若进位成 21.3%，一整行就顶到 100.2%，Flex 会把最后一枚挤到下一行。
export function cellWidthPct(bp: string, phoneCols: number, gap: number): string {
  let n = cellCols(bp, phoneCols);
  let w = Math.floor(((100 - gap * (n - 1)) / n) * 100) / 100;
  return `${w}%`;
}

// 该行最后一格不加右边距，否则整行会顶出容器
export function isLastInRow(bp: string, phoneCols: number, i: number): boolean {
  return (i + 1) % cellCols(bp, phoneCols) === 0;
}

// 一屏想凑满几行几列：手机 2×2=4 张，宽屏按列数扩到 6/8 张，别让最后一行只剩一张
export function gridCount(bp: string, phoneCols: number, rows: number): number {
  return cellCols(bp, phoneCols) * rows;
}

// 「我的」那种手工分行：每行几个
export function rowSize(bp: string, phone: number): number {
  if (bp === 'xl') {
    return phone + 2;
  }
  if (bp === 'lg') {
    return phone + 1;
  }
  return phone;
}

// 首页八枚功能印章：手机两排四枚，宽屏一排铺开八枚
export function tileWidthPct(bp: string): string {
  return isWide(bp) ? '12.5%' : '25%';
}
