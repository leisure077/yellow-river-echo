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

export function openAssistantSheet(): void {
  AppStorage.setOrCreate('assistantSheet', true);
}

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

export function goLogin(): void {
  router.replaceUrl({ url: 'pages/LoginPage' });
}

export function goPost(postId: string): void {
  let p: RouteParam = { id: postId };
  router.pushUrl({ url: 'pages/PostPage', params: p });
}

export function goCompose(): void {
  router.pushUrl({ url: 'pages/ComposePage' });
}

export function goCheckin(): void {
  router.pushUrl({ url: 'pages/CheckinPage' });
}

export function goRoute(): void {
  router.pushUrl({ url: 'pages/RoutePage' });
}

export function goStudio(tab: number): void {
  let p: RouteParam = { tab: tab };
  router.pushUrl({ url: 'pages/StudioPage', params: p });
}

export function goRelic(id: number): void {
  let p: RouteParam = { relic: id };
  router.pushUrl({ url: 'pages/RelicPage', params: p });
}

export function goSandtable(): void {
  router.pushUrl({ url: 'pages/SandtablePage' });
}

export function goExperience(type: string): void {
  let p: RouteParam = { type: type };
  router.pushUrl({ url: 'pages/ExperiencePage', params: p });
}

export function goEngineer(): void {
  router.pushUrl({ url: 'pages/EngineerPage' });
}

export function goGuide(): void {
  router.pushUrl({ url: 'pages/GuidePage' });
}

export function goTopic(): void {
  router.pushUrl({ url: 'pages/TopicPage' });
}

export function goQuiz(from: string): void {
  let p: RouteParam = { from: from };
  router.pushUrl({ url: 'pages/QuizPage', params: p });
}

export function goBack(): void {
  router.back();
}

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

export function openSignOutAsk(): void {
  AppStorage.setOrCreate('signOutAsk', true);
}

export function closeSignOutAsk(): void {
  AppStorage.setOrCreate('signOutAsk', false);
}

export function params(): RouteParam {
  return (router.getParams() ?? {}) as RouteParam;
}
