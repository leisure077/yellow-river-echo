import { router } from '@kit.ArkUI';
import { ContentRepo } from '../service/ContentRepo';

export interface RouteParam {
  id?: string;
  kw?: string;
  era?: string;
  city?: string;
  type?: string;
  siteId?: string;
  noteId?: string;
  goodsId?: string;
  courseId?: string;
  eventId?: string;
  tab?: number;
  relic?: number;
  from?: string;
}

export function goAssistant(): void {
  router.pushUrl({ url: 'pages/AssistantPage' });
}

// 半屏助手卡片的唯一开关：首页右上角「问」和右下角悬浮球改的是同一个状态，
// 弹出的是同一个 FloatingAssistant，所以从哪儿进都看得到同一份记录。
export function openAssistantSheet(): void {
  AppStorage.setOrCreate('assistantSheet', true);
}

export function closeAssistantSheet(): void {
  AppStorage.setOrCreate('assistantSheet', false);
}

// 首页和地图页各挂了一个悬浮助手实例，同一时刻只让"当前页"那个弹卡片。
export function claimAssistant(tag: string): void {
  AppStorage.setOrCreate('assistantOwner', tag);
  AppStorage.setOrCreate('assistantSheet', false);
}

export function goDetail(id: string): void {
  let p: RouteParam = { id: id };
  router.pushUrl({ url: 'pages/DetailPage', params: p });
}

export function goList(kw: string, era: string, city: string, type: string): void {
  let p: RouteParam = { kw: kw, era: era, city: city, type: type };
  router.pushUrl({ url: 'pages/ListPage', params: p });
}

export function goNote(siteId: string, noteId: string): void {
  let p: RouteParam = { siteId: siteId, noteId: noteId };
  router.pushUrl({ url: 'pages/NoteEditPage', params: p });
}

export function goArchive(tab: number): void {
  let p: RouteParam = { tab: tab };
  router.pushUrl({ url: 'pages/ArchivePage', params: p });
}

export function goGoods(id: string): void {
  let p: RouteParam = { goodsId: id };
  router.pushUrl({ url: 'pages/GoodsDetailPage', params: p });
}

// 文创右上角「清单」点进来：按品类分组、能勾选改数量的喜欢清单
export function goWishlist(): void {
  router.pushUrl({ url: 'pages/WishlistPage' });
}

export function goCourses(): void {  router.pushUrl({ url: 'pages/CoursePage' });
}

export function goPlayer(courseId: string): void {
  let p: RouteParam = { courseId: courseId };
  router.pushUrl({ url: 'pages/PlayerPage', params: p });
}

export function goPottery(): void {
  router.pushUrl({ url: 'pages/PotteryPage' });
}

export function goActivity(eventId: string): void {
  let p: RouteParam = { eventId: eventId };
  router.pushUrl({ url: 'pages/ActivityPage', params: p });
}

export function goSync(): void {
  router.pushUrl({ url: 'pages/SyncPage' });
}

// 退出登录后回登录页：用 replace，别留一层能按返回键摸回主界面
export function goLogin(): void {
  router.replaceUrl({ url: 'pages/LoginPage' });
}

// 社群动态详情：整卡点开看全文、看评论、点赞关注
export function goPost(postId: string): void {
  let p: RouteParam = { id: postId };
  router.pushUrl({ url: 'pages/PostPage', params: p });
}

// 社群「发动态」：写完落到本机动态表，回社群页置顶显示
export function goCompose(): void {
  router.pushUrl({ url: 'pages/ComposePage' });
}

// 首页「签到」：河道示意图上点一个点盖一个章
export function goCheckin(): void {
  router.pushUrl({ url: 'pages/CheckinPage' });
}

// 行程规划页入口：首页宫格「行程规划」与长卷「＋ 创建我的行程」都走这里；
// 选年代/城市，把遗址顺河排成一条线
export function goRoute(): void {
  router.pushUrl({ url: 'pages/RoutePage' });
}

// 数字文物：tab 0 观文物 / 1 创意坊（展台 + 工坊入口）/ 2 选教程
export function goStudio(tab: number): void {
  let p: RouteParam = { tab: tab };
  router.pushUrl({ url: 'pages/StudioPage', params: p });
}

// 创意坊 →「3D工坊」：relic 是六件扫描文物的顺序，缺省 0
// （0 舞者砖 · 1 双龙耳瓶 · 2 青铜镈钟 · 3 青铜方彝 · 4 安特生陶罐 · 5 三彩马，
//   与 relic.js 里的 RELICS、rawfile/relic/turntable/<序号>/ 一一对应）
export function goRelic(id: number): void {
  let p: RouteParam = { relic: id };
  router.pushUrl({ url: 'pages/RelicPage', params: p });
}

// 「黄河沙盘」：纯前端 Canvas 时间轴推演（大禹治水 / 汉唐漕运 / 宋元夺淮 / 当代安澜）
// 入口与页内标题都用「黄河沙盘」，地图上的水印副标题保留主题名「黄河地理与文明」
export function goSandtable(): void {
  router.pushUrl({ url: 'pages/SandtablePage' });
}

// 地图导览：ArkWeb 承载的手绘导览。type 取 map / travel / model / footprints，
// 缺省 map；地图页内保留发现·建筑·展览·打卡·餐饮·文创·卫生间·游客服务八类筛选
export function goExperience(type: string): void {
  let p: RouteParam = { type: type };
  router.pushUrl({ url: 'pages/ExperiencePage', params: p });
}

// 彩蛋：连点头像 5 次后出现的「河工面板」，把同步状态机和各表行数摊开看
export function goEngineer(): void {
  router.pushUrl({ url: 'pages/EngineerPage' });
}

// 边侧栏「重看引河」：guideSeen 已由 StudioStore.redoGuide() 清掉
export function goGuide(): void {
  router.pushUrl({ url: 'pages/GuidePage' });
}

export function goTopic(): void {
  router.pushUrl({ url: 'pages/TopicPage' });
}

// from 记录来源，结果页据此决定返回后露出哪个入口
export function goQuiz(from: string): void {
  let p: RouteParam = { from: from };
  router.pushUrl({ url: 'pages/QuizPage', params: p });
}

export function goBack(): void {
  router.back();
}

// 专题类引用（文创 / 课程 / 活动）的落点：
// 文创市集在首页的「文创」页签，课程有独立页，活动没有列表页就跳最近一场排期。
// type 由 AiService 按知识库文档名前缀判定，遗址类不走这里。
export function goTopicSection(type: string): void {
  if (type === 'courses') {
    goCourses();
    return;
  }
  if (type === 'events') {
    let next = ContentRepo.get().upcomingEvents(1);
    if (next.length > 0) {
      goActivity(next[0].id);
    }
    return;
  }
  if (type === 'goods') {
    switchTab(1);
    // 从助手页/地图页跳过来时退回主框架，让「文创」页签露出来；已在首页则原地切换
    router.back({ url: 'pages/Index' });
  }
}

export function openDrawer(): void {
  AppStorage.setOrCreate('drawerOpen', true);
}

export function closeDrawer(): void {
  AppStorage.setOrCreate('drawerOpen', false);
}

export function switchTab(idx: number): void {
  AppStorage.setOrCreate('mainTab', idx);
}

// 退出登录的确认面板挂在 Index 上，跟侧栏、加号面板一个层级，才盖得住底栏
export function openSignOutAsk(): void {
  AppStorage.setOrCreate('signOutAsk', true);
}

export function closeSignOutAsk(): void {
  AppStorage.setOrCreate('signOutAsk', false);
}

export function params(): RouteParam {
  // 不带 params 的 pushUrl 会给出 undefined，直接读属性就是 jscrash（实测崩在 RoutePage）
  return (router.getParams() ?? {}) as RouteParam;
}
